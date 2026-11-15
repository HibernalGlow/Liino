//! macOS Bluetooth link over the bundled Swift helper.
//!
//! The helper owns `IOBluetooth` (ADR-0009) and bridges the RFCOMM channel to
//! its stdin/stdout. `BluetoothLink` frames that byte stream with the
//! `MicYouCheck1`/`MicYouCheck2` handshake + `PACKET_MAGIC` protobuf frames and
//! bridges it to the local `micyou-core` TCP server so audio, ping/pong, and
//! stats flow through the standard pipeline.

use micyou_core::micyou_protocol::{
    HANDSHAKE_CLIENT_STR, HANDSHAKE_SERVER_STR, PACKET_MAGIC,
};
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const CONNECT_GRACE: Duration = Duration::from_millis(900);
const FRAME_HEADER_LEN: usize = 8;
const MAX_BT_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BtDevice {
    pub address: String,
    pub name: String,
}

/// Resolves the helper: explicit override, next to the daemon (App bundle), or
/// the workspace build directory.
pub fn helper_path() -> Result<PathBuf, String> {
    if let Ok(path) = std::env::var("LIINO_BT_HELPER") {
        if !path.is_empty() {
            return Ok(PathBuf::from(path));
        }
    }
    if let Ok(executable) = std::env::current_exe() {
        if let Some(dir) = executable.parent() {
            let candidate = dir.join("liino-bt-helper");
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../apps/liino_app/build/bt_helper/liino-bt-helper");
    if dev.is_file() {
        return Ok(dev);
    }
    Err("liino-bt-helper not found; set LIINO_BT_HELPER".to_string())
}

pub fn list_devices() -> Result<Vec<BtDevice>, String> {
    let helper = helper_path()?;
    let output = Command::new(&helper)
        .arg("--list")
        .output()
        .map_err(|e| format!("run {}: {e}", helper.display()))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("bluetooth helper exited: {}", stderr.trim()));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| format!("invalid helper output: {e}"))
}

/// Reads one `PACKET_MAGIC (4B BE) + len (4B BE) + payload` frame.
pub fn read_framed_packet<R: Read>(reader: &mut R) -> io::Result<Vec<u8>> {
    let mut header = [0u8; FRAME_HEADER_LEN];
    reader.read_exact(&mut header)?;
    let magic = i32::from_be_bytes(header[0..4].try_into().unwrap());
    if magic != PACKET_MAGIC {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid BT frame magic: 0x{magic:08x}"),
        ));
    }
    let len_i32 = i32::from_be_bytes(header[4..8].try_into().unwrap());
    if len_i32 < 0 || len_i32 as usize > MAX_BT_FRAME_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid BT frame length: {len_i32}"),
        ));
    }
    let len = len_i32 as usize;
    let mut frame = Vec::with_capacity(FRAME_HEADER_LEN + len);
    frame.extend_from_slice(&header);
    frame.resize(FRAME_HEADER_LEN + len, 0);
    reader.read_exact(&mut frame[FRAME_HEADER_LEN..])?;
    Ok(frame)
}

/// Bridges a framed `MicYouCheck1`/`MicYouCheck2` + `PACKET_MAGIC` stream
/// (`peer_rx`/`peer_tx`, e.g. `liino-bt-helper` stdout/stdin) to a local
/// `micyou-core` TCP stream (`127.0.0.1:<port>`).
pub fn bridge_framed_streams<R, W>(
    mut peer_rx: R,
    mut peer_tx: W,
    mut tcp: TcpStream,
    stop: Arc<AtomicBool>,
) -> io::Result<()>
where
    R: Read + Send + 'static,
    W: Write + Send + 'static,
{
    tcp.set_nodelay(true)?;
    let mut tcp_rx = tcp.try_clone()?;

    let mut client_hs = vec![0u8; HANDSHAKE_CLIENT_STR.len()];
    peer_rx.read_exact(&mut client_hs)?;
    if client_hs != HANDSHAKE_CLIENT_STR {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid BT client handshake",
        ));
    }
    tcp.write_all(HANDSHAKE_CLIENT_STR)?;
    tcp.flush()?;

    let mut server_hs = vec![0u8; HANDSHAKE_SERVER_STR.len()];
    tcp_rx.read_exact(&mut server_hs)?;
    if server_hs != HANDSHAKE_SERVER_STR {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid BT server handshake",
        ));
    }
    peer_tx.write_all(HANDSHAKE_SERVER_STR)?;
    peer_tx.flush()?;

    let stop_out = stop.clone();
    let outbound = thread::spawn(move || {
        while !stop_out.load(Ordering::Relaxed) {
            match read_framed_packet(&mut tcp_rx) {
                Ok(frame) => {
                    if peer_tx.write_all(&frame).is_err() || peer_tx.flush().is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        stop_out.store(true, Ordering::Relaxed);
    });

    while !stop.load(Ordering::Relaxed) {
        match read_framed_packet(&mut peer_rx) {
            Ok(frame) => {
                if tcp.write_all(&frame).is_err() || tcp.flush().is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    stop.store(true, Ordering::Relaxed);
    let _ = outbound.join();
    Ok(())
}

pub struct BluetoothLink {
    address: String,
    child: Child,
    stop: Arc<AtomicBool>,
    _bridge: Option<thread::JoinHandle<()>>,
}

impl BluetoothLink {
    pub fn connect(address: &str, target_tcp_port: Option<u16>) -> Result<Self, String> {
        if address.trim().is_empty() {
            return Err("Bluetooth address is empty".to_string());
        }
        let helper = helper_path()?;
        let mut child = Command::new(&helper)
            .arg("--address")
            .arg(address)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| format!("spawn {}: {e}", helper.display()))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "helper stdin unavailable".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "helper stdout unavailable".to_string())?;

        thread::sleep(CONNECT_GRACE);
        if let Some(status) = child
            .try_wait()
            .map_err(|e| format!("helper status: {e}"))?
        {
            return Err(format!("Bluetooth helper exited early ({status})"));
        }

        let stop = Arc::new(AtomicBool::new(false));
        let bridge = if let Some(port) = target_tcp_port {
            let tcp = TcpStream::connect(("127.0.0.1", port))
                .map_err(|e| format!("connect local audio server 127.0.0.1:{port}: {e}"))?;
            let stop_flag = stop.clone();
            Some(thread::spawn(move || {
                if let Err(e) = bridge_framed_streams(stdout, stdin, tcp, stop_flag) {
                    eprintln!("[liino-daemon] bluetooth audio bridge ended: {e}");
                }
            }))
        } else {
            let stop_flag = stop.clone();
            Some(thread::spawn(move || {
                let _stdin = stdin;
                let mut reader = io::BufReader::new(stdout);
                let mut buffer = [0u8; 4096];
                while !stop_flag.load(Ordering::Relaxed) {
                    match reader.read(&mut buffer) {
                        Ok(0) | Err(_) => break,
                        Ok(_) => {}
                    }
                }
            }))
        };

        Ok(Self {
            address: address.to_string(),
            child,
            stop,
            _bridge: bridge,
        })
    }

    pub fn address(&self) -> &str {
        &self.address
    }
}

impl Drop for BluetoothLink {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use micyou_core::micyou_protocol::micyou::{
        AudioPacketMessage, AudioPacketMessageOrdered, ConnectMessage, MessageWrapper,
    };
    use prost::Message;
    use std::io::Cursor;
    use std::net::TcpListener;

    fn encode_frame(msg: &MessageWrapper) -> Vec<u8> {
        let payload = msg.encode_to_vec();
        let mut frame = Vec::with_capacity(FRAME_HEADER_LEN + payload.len());
        frame.extend_from_slice(&PACKET_MAGIC.to_be_bytes());
        frame.extend_from_slice(&(payload.len() as i32).to_be_bytes());
        frame.extend_from_slice(&payload);
        frame
    }

    #[test]
    fn read_framed_packet_rejects_bad_magic() {
        let mut bad = Cursor::new(b"BAD!\x00\x00\x00\x04test");
        let err = read_framed_packet(&mut bad).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn bridge_framed_streams_forwards_handshake_and_audio_frames() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();

        let server_thread = thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            let mut hs = [0u8; 12];
            sock.read_exact(&mut hs).unwrap();
            assert_eq!(&hs, HANDSHAKE_CLIENT_STR);
            sock.write_all(HANDSHAKE_SERVER_STR).unwrap();
            sock.flush().unwrap();

            let f1 = read_framed_packet(&mut sock).unwrap();
            let m1 = MessageWrapper::decode(&f1[FRAME_HEADER_LEN..]).unwrap();
            assert_eq!(m1.connect.unwrap().platform, "android");

            let f2 = read_framed_packet(&mut sock).unwrap();
            let m2 = MessageWrapper::decode(&f2[FRAME_HEADER_LEN..]).unwrap();
            let audio = m2.audio_packet.unwrap();
            assert_eq!(audio.sequence_number, 42);
            assert_eq!(audio.audio_packet.unwrap().buffer, vec![1, 2, 3, 4]);
        });

        let mut peer_input = Vec::new();
        peer_input.extend_from_slice(HANDSHAKE_CLIENT_STR);
        peer_input.extend_from_slice(&encode_frame(&MessageWrapper {
            connect: Some(ConnectMessage {
                session_id: 99,
                platform: "android".to_string(),
                transport: "tcp".to_string(),
            }),
            ..Default::default()
        }));
        peer_input.extend_from_slice(&encode_frame(&MessageWrapper {
            audio_packet: Some(AudioPacketMessageOrdered {
                sequence_number: 42,
                audio_packet: Some(AudioPacketMessage {
                    buffer: vec![1, 2, 3, 4],
                    sample_rate: 48_000,
                    channel_count: 1,
                    audio_format: 2,
                    codec: 0,
                }),
                ..Default::default()
            }),
            ..Default::default()
        }));

        let peer_output: Vec<u8> = Vec::new();
        let tcp = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let _ = bridge_framed_streams(Cursor::new(peer_input), peer_output, tcp, stop);
        server_thread.join().unwrap();
    }
}
