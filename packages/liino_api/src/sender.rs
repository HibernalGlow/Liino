//! Liino sender client: captures the local microphone and streams PCM audio to
//! a MicYou/liino receiver over TCP (ADR-0004 / ADR-0005).
//!
//! Wire format mirrors the vendored receiver (`micyou-core/src/transport/tcp.rs`):
//! handshake strings, then `PACKET_MAGIC + len` framed protobuf `MessageWrapper`.
//! `connect.transport = "tcp"` makes the receiver accept audio on the TCP socket
//! (TCP-only mode), so the same sender works over USB (adb reverse) and Wi-Fi.
//! PCM (codec 0) is used because the vendored core ships only an Opus *decoder*;
//! Opus encoding is a follow-up (needs an on-device encoder).

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use micyou_core::micyou_protocol as proto;
use proto::micyou as wire;
use prost::Message;

const AUDIO_FORMAT_PCM_16BIT: i32 = 2;
const CHUNK_CHANNEL_DEPTH: usize = 64;

struct AudioChunk {
    buffer: Vec<u8>,
    sample_rate: u32,
    channels: u16,
}

pub struct SenderHandle {
    stop: Arc<AtomicBool>,
    // Dropping the sender closes the channel, unblocking the send thread.
    _chunk_tx: mpsc::SyncSender<AudioChunk>,
    capture: Option<std::thread::JoinHandle<()>>,
    send: Option<std::thread::JoinHandle<()>>,
}

static SENDER: Mutex<Option<SenderHandle>> = Mutex::new(None);

/// Live control socket of the running sender, for out-of-band control frames
/// (remote key trigger). Shares the send loop's write lock.
static CONTROL: Mutex<Option<Arc<Mutex<TcpStream>>>> = Mutex::new(None);

fn unix_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn write_frame(stream: &mut TcpStream, msg: &wire::MessageWrapper) -> std::io::Result<()> {
    let payload = msg.encode_to_vec();
    let mut frame = Vec::with_capacity(8 + payload.len());
    frame.extend_from_slice(&proto::PACKET_MAGIC.to_be_bytes());
    frame.extend_from_slice(&(payload.len() as i32).to_be_bytes());
    frame.extend_from_slice(&payload);
    stream.write_all(&frame)
}

fn push_pcm16(out: &mut Vec<u8>, sample: f32) {
    let clamped = sample.clamp(-1.0, 1.0);
    out.extend_from_slice(&((clamped * 32767.0) as i16).to_le_bytes());
}

pub fn start_sender(target: String, port: u16) -> Result<(), String> {
    stop_sender();

    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or_else(|| "no default input device".to_string())?;
    let config = device
        .default_input_config()
        .map_err(|e| format!("input config: {e}"))?;
    let sample_rate = config.sample_rate();
    let channels = config.channels();
    let sample_format = config.sample_format();

    let (chunk_tx, chunk_rx) = mpsc::sync_channel::<AudioChunk>(CHUNK_CHANNEL_DEPTH);
    let stop = Arc::new(AtomicBool::new(false));

    let cb_stop = stop.clone();
    let cb_tx = chunk_tx.clone();
    let send_chunk = move |buffer: Vec<u8>| {
        if cb_stop.load(Ordering::Relaxed) {
            return;
        }
        let _ = cb_tx.try_send(AudioChunk {
            buffer,
            sample_rate,
            channels,
        });
    };
    let err_fn = |err| eprintln!("[sender] input stream error: {err}");

    let stream = match sample_format {
        cpal::SampleFormat::F32 => {
            let emit = send_chunk;
            device.build_input_stream(
                config.config(),
                move |data: &[f32], _| {
                    let mut buffer = Vec::with_capacity(data.len() * 2);
                    for &s in data {
                        push_pcm16(&mut buffer, s);
                    }
                    emit(buffer);
                },
                err_fn,
                None,
            )
        }
        cpal::SampleFormat::I16 => {
            let emit = send_chunk;
            device.build_input_stream(
                config.config(),
                move |data: &[i16], _| {
                    let mut buffer = Vec::with_capacity(data.len() * 2);
                    for &s in data {
                        buffer.extend_from_slice(&s.to_le_bytes());
                    }
                    emit(buffer);
                },
                err_fn,
                None,
            )
        }
        other => return Err(format!("unsupported input sample format: {other:?}")),
    }
    .map_err(|e| format!("build input stream: {e}"))?;
    stream.play().map_err(|e| format!("play input stream: {e}"))?;

    let capture_stop = stop.clone();
    let capture = std::thread::spawn(move || {
        let _stream = stream;
        while !capture_stop.load(Ordering::Relaxed) {
            std::thread::sleep(Duration::from_millis(50));
        }
    });

    let send_stop = stop.clone();
    let session_id = unix_millis();
    let send = std::thread::spawn(move || {
        if let Err(e) = run_send_loop(&target, port, session_id, &chunk_rx, send_stop) {
            eprintln!("[sender] send loop ended: {e}");
        }
    });

    let handle = SenderHandle {
        stop,
        _chunk_tx: chunk_tx,
        capture: Some(capture),
        send: Some(send),
    };
    *SENDER.lock().unwrap_or_else(|p| p.into_inner()) = Some(handle);
    Ok(())
}

fn run_send_loop(
    target: &str,
    port: u16,
    session_id: i64,
    chunk_rx: &mpsc::Receiver<AudioChunk>,
    stop: Arc<AtomicBool>,
) -> Result<(), String> {
    let addr = format!("{target}:{port}");
    let mut stream = TcpStream::connect(&addr).map_err(|e| format!("connect {addr}: {e}"))?;
    stream.set_nodelay(true).map_err(|e| format!("nodelay: {e}"))?;

    stream
        .write_all(proto::HANDSHAKE_CLIENT_STR)
        .map_err(|e| format!("handshake write: {e}"))?;
    let mut reply = [0u8; 12];
    stream
        .read_exact(&mut reply)
        .map_err(|e| format!("handshake read: {e}"))?;
    if reply != proto::HANDSHAKE_SERVER_STR {
        return Err("unexpected handshake reply".to_string());
    }

    write_frame(
        &mut stream,
        &wire::MessageWrapper {
            connect: Some(wire::ConnectMessage {
                session_id,
                platform: "android".to_string(),
                transport: "tcp".to_string(),
            }),
            ..Default::default()
        },
    )
    .map_err(|e| format!("connect frame: {e}"))?;

    // All writes (audio, ping, pong, remote-key control) share one lock so
    // frames never interleave on the socket.
    let writer = Arc::new(Mutex::new(stream));
    *CONTROL.lock().unwrap_or_else(|p| p.into_inner()) = Some(writer.clone());

    // Answer receiver pings so it can compute RTT; ignore everything else.
    let mut read_half = writer
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .try_clone()
        .map_err(|e| format!("clone: {e}"))?;
    let reader_stop = stop.clone();
    let pong_writer = writer.clone();
    let reader_handle = std::thread::spawn(move || {
        let mut header = [0u8; 8];
        while !reader_stop.load(Ordering::Relaxed) {
            if read_half.read_exact(&mut header).is_err() {
                break;
            }
            let len = i32::from_be_bytes(header[4..8].try_into().unwrap()) as usize;
            if len > 1024 * 1024 {
                break;
            }
            let mut payload = vec![0u8; len];
            if read_half.read_exact(&mut payload).is_err() {
                break;
            }
            if let Ok(msg) = wire::MessageWrapper::decode(&payload[..]) {
                if let Some(ping) = msg.ping {
                    let mut w = pong_writer.lock().unwrap_or_else(|p| p.into_inner());
                    let _ = write_frame(
                        &mut w,
                        &wire::MessageWrapper {
                            pong: Some(wire::PongMessage {
                                timestamp: ping.timestamp,
                            }),
                            ..Default::default()
                        },
                    );
                }
            }
        }
    });

    let mut sequence: i32 = 0;
    let mut last_ping = unix_millis();
    while !stop.load(Ordering::Relaxed) {
        match chunk_rx.recv_timeout(Duration::from_millis(200)) {
            Ok(chunk) => {
                write_frame(
                    &mut writer.lock().unwrap_or_else(|p| p.into_inner()),
                    &wire::MessageWrapper {
                        audio_packet: Some(wire::AudioPacketMessageOrdered {
                            sequence_number: sequence,
                            audio_packet: Some(wire::AudioPacketMessage {
                                buffer: chunk.buffer,
                                sample_rate: chunk.sample_rate as i32,
                                channel_count: chunk.channels as i32,
                                audio_format: AUDIO_FORMAT_PCM_16BIT,
                                codec: proto::CODEC_PCM,
                            }),
                            timestamp: unix_millis(),
                            session_id,
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                )
                .map_err(|e| format!("audio frame: {e}"))?;
                sequence = sequence.wrapping_add(1);
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        let now = unix_millis();
        if now - last_ping >= 1000 {
            last_ping = now;
            write_frame(
                &mut writer.lock().unwrap_or_else(|p| p.into_inner()),
                &wire::MessageWrapper {
                    ping: Some(wire::PingMessage { timestamp: now }),
                    ..Default::default()
                },
            )
            .map_err(|e| format!("ping: {e}"))?;
        }
    }

    *CONTROL.lock().unwrap_or_else(|p| p.into_inner()) = None;
    drop(writer);
    let _ = reader_handle.join();
    Ok(())
}

/// Sends a remote-key action (tap / down / up) to the receiver over the live
/// control socket as a cross-device plugin message; the desktop daemon
/// synthesizes its configured key. No Bluetooth pairing involved.
pub fn send_remote_key(action: String) -> Result<(), String> {
    if !matches!(action.as_str(), "tap" | "down" | "up") {
        return Err(format!("unknown remote key action: {action}"));
    }
    let control = CONTROL.lock().unwrap_or_else(|p| p.into_inner());
    let writer = control
        .as_ref()
        .ok_or_else(|| "sender not connected".to_string())?;
    let payload = format!(r#"{{"action":"{action}"}}"#).into_bytes();
    let mut w = writer.lock().unwrap_or_else(|p| p.into_inner());
    write_frame(
        &mut w,
        &wire::MessageWrapper {
            plugin_message: Some(wire::PluginMessage {
                source: "liino-remote".to_string(),
                target: String::new(),
                topic: "liino.remote_key".to_string(),
                payload,
                ..Default::default()
            }),
            ..Default::default()
        },
    )
    .map_err(|e| format!("remote key frame: {e}"))
}

pub fn stop_sender() {
    let handle = SENDER.lock().unwrap_or_else(|p| p.into_inner()).take();
    if let Some(mut h) = handle {
        h.stop.store(true, Ordering::Relaxed);
        drop(h._chunk_tx);
        if let Some(t) = h.capture.take() {
            let _ = t.join();
        }
        if let Some(t) = h.send.take() {
            let _ = t.join();
        }
    }
}

pub fn sender_running() -> bool {
    SENDER.lock().unwrap_or_else(|p| p.into_inner()).is_some()
}