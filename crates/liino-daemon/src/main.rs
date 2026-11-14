mod ipc;

use ipc::{
    default_ipc_endpoint, parse_ipc_line, IpcRequest, IpcResponse, MAX_IPC_FRAME_BYTES,
    MAX_IPC_QUEUE_DEPTH,
};
use liino_core::{ResolvedRole, RoleMode, TransportType};
use liino_engine::presence::{Presence, PresenceConfig};
use liino_engine::stats::NetworkStats;
use liino_platform::{enriched_capabilities, probe_current_platform, VirtualMicStatus};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot, watch};

struct DaemonState {
    role_mode: RoleMode,
    active_transport: String,
    is_running: bool,
    stats: NetworkStats,
    presence: Option<Presence>,
}

impl Default for DaemonState {
    fn default() -> Self {
        let stats = NetworkStats::default();
        stats.set_audio_info(48_000, 1);
        let caps = enriched_capabilities();
        let role = caps
            .resolve_role(RoleMode::Auto)
            .unwrap_or_else(|_| caps.default_role());
        let presence = Presence::start(PresenceConfig {
            name: host_name(),
            platform: caps.platform_name.clone(),
            role: resolved_role_str(role).to_string(),
            transports: caps
                .supported_transports
                .iter()
                .map(|transport| transport_str(*transport))
                .collect(),
        })
        .map_err(|error| eprintln!("[liino-daemon] presence disabled: {error}"))
        .ok();
        Self {
            role_mode: RoleMode::Auto,
            active_transport: "lan_wifi".to_string(),
            is_running: false,
            stats,
            presence,
        }
    }
}

fn host_name() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .unwrap_or_else(|_| "liino desktop".to_string())
}

fn transport_str(transport: TransportType) -> String {
    match transport {
        TransportType::LanWifi => "lan_wifi",
        TransportType::Usb => "usb",
        TransportType::BluetoothRfcomm => "bluetooth_rfcomm",
    }
    .to_string()
}

struct QueuedCommand {
    req: IpcRequest,
    reply: oneshot::Sender<IpcResponse>,
}

fn role_mode_str(mode: RoleMode) -> &'static str {
    match mode {
        RoleMode::Auto => "auto",
        RoleMode::Sender => "sender",
        RoleMode::Receiver => "receiver",
    }
}

fn resolved_role_str(role: ResolvedRole) -> &'static str {
    match role {
        ResolvedRole::Sender => "sender",
        ResolvedRole::Receiver => "receiver",
    }
}

fn handle_request(
    req: IpcRequest,
    state: &mut DaemonState,
    shutdown_tx: &watch::Sender<bool>,
) -> IpcResponse {
    match req {
        IpcRequest::Ping => IpcResponse::Pong {
            pid: std::process::id(),
        },
        IpcRequest::GetStatus => {
            let caps = enriched_capabilities();
            let probe = probe_current_platform();
            let resolved = caps
                .resolve_role(state.role_mode)
                .unwrap_or_else(|_| caps.default_role());
            let metrics = state.stats.to_metrics(if state.is_running { 20 } else { 0 });
            IpcResponse::Status {
                pid: std::process::id(),
                platform: caps.platform_name,
                role_mode: role_mode_str(state.role_mode).to_string(),
                resolved_role: resolved_role_str(resolved).to_string(),
                active_transport: state.active_transport.clone(),
                is_running: state.is_running,
                virtual_mic_installed: probe.virtual_mic == VirtualMicStatus::Installed,
                virtual_mic_driver: probe.virtual_mic_driver,
                rtt_ms: metrics.network_latency_ms,
                jitter_ms: metrics.jitter_ms,
                packet_loss_rate: metrics.packet_loss_rate,
                bitrate: metrics.bitrate,
                sample_rate: metrics.sample_rate,
                buffer_duration_ms: metrics.buffer_duration_ms,
            }
        }
        IpcRequest::GetPeers => {
            let (peers, connected, connecting) = match &state.presence {
                Some(presence) => (
                    presence.peers(),
                    presence.connected(),
                    presence.connecting(),
                ),
                None => (Vec::new(), None, None),
            };
            IpcResponse::Peers {
                peers,
                connected,
                connecting,
            }
        }
        IpcRequest::ConnectPeer { id } => match &state.presence {
            Some(presence) => match presence.request_connect(&id) {
                Ok(()) => IpcResponse::Ok,
                Err(message) => IpcResponse::Error { message },
            },
            None => IpcResponse::Error {
                message: "Presence is not running".to_string(),
            },
        },
        IpcRequest::DisconnectPeer => {
            if let Some(presence) = &state.presence {
                presence.disconnect();
            }
            IpcResponse::Ok
        }
        IpcRequest::SetRoleMode { mode } => {
            let parsed = match mode.as_str() {
                "auto" => RoleMode::Auto,
                "sender" => RoleMode::Sender,
                "receiver" => RoleMode::Receiver,
                other => {
                    return IpcResponse::Error {
                        message: format!("Unknown role mode: {other}"),
                    }
                }
            };
            let caps = enriched_capabilities();
            let resolved = match caps.resolve_role(parsed) {
                Ok(resolved) => resolved,
                Err(err) => return IpcResponse::Error { message: err },
            };
            state.role_mode = parsed;
            if let Some(presence) = &state.presence {
                presence.set_role(resolved_role_str(resolved));
            }
            IpcResponse::Ok
        }
        IpcRequest::SetTransport { transport } => {
            if matches!(
                transport.as_str(),
                "lan_wifi" | "usb" | "bluetooth_rfcomm"
            ) {
                state.active_transport = transport;
                IpcResponse::Ok
            } else {
                IpcResponse::Error {
                    message: format!("Unsupported transport: {transport}"),
                }
            }
        }
        IpcRequest::StartLink => {
            state.is_running = true;
            state.stats.mark_tcp_connected(liino_engine::stats::unix_millis());
            IpcResponse::Ok
        }
        IpcRequest::StopLink => {
            state.is_running = false;
            state.stats.mark_tcp_disconnected();
            IpcResponse::Ok
        }
        IpcRequest::ShutdownDaemon => {
            state.is_running = false;
            state.stats.mark_tcp_disconnected();
            let _ = shutdown_tx.send(true);
            IpcResponse::Ok
        }
    }
}

async fn dispatch_command(tx: &mpsc::Sender<QueuedCommand>, req: IpcRequest) -> IpcResponse {
    let (reply_tx, reply_rx) = oneshot::channel();
    if tx.try_send(QueuedCommand { req, reply: reply_tx }).is_err() {
        return IpcResponse::Error {
            message: "Daemon IPC queue full".to_string(),
        };
    }
    reply_rx.await.unwrap_or(IpcResponse::Error {
        message: "Daemon actor dropped reply".to_string(),
    })
}

#[cfg(unix)]
async fn run_ipc_server(
    endpoint: &str,
    cmd_tx: mpsc::Sender<QueuedCommand>,
    mut shutdown_rx: watch::Receiver<bool>,
) -> std::io::Result<()> {
    use tokio::net::UnixListener;

    let _ = std::fs::remove_file(endpoint);
    let listener = UnixListener::bind(endpoint)?;

    loop {
        tokio::select! {
            _ = shutdown_rx.changed() => {
                if *shutdown_rx.borrow() {
                    break;
                }
            }
            accept_res = listener.accept() => {
                let (stream, _) = accept_res?;
                let tx_cloned = cmd_tx.clone();
                tokio::spawn(async move {
                    let (reader, mut writer) = stream.into_split();
                    let mut buf_reader = BufReader::new(reader);
                    let mut line = String::new();
                    loop {
                        line.clear();
                        match buf_reader.read_line(&mut line).await {
                            Ok(0) | Err(_) => break,
                            Ok(n) if n > MAX_IPC_FRAME_BYTES => {
                                let err = serde_json::to_string(&IpcResponse::Error {
                                    message: "Frame too large".to_string(),
                                }).unwrap_or_default();
                                let _ = writer.write_all(format!("{err}\n").as_bytes()).await;
                                break;
                            }
                            Ok(_) => {
                                let resp = match parse_ipc_line(&line) {
                                    Ok(req) => dispatch_command(&tx_cloned, req).await,
                                    Err(msg) => IpcResponse::Error { message: msg },
                                };
                                if let Ok(json) = serde_json::to_string(&resp) {
                                    let _ = writer.write_all(format!("{json}\n").as_bytes()).await;
                                }
                            }
                        }
                    }
                });
            }
        }
    }

    let _ = std::fs::remove_file(endpoint);
    Ok(())
}

#[cfg(windows)]
async fn run_ipc_server(
    endpoint: &str,
    cmd_tx: mpsc::Sender<QueuedCommand>,
    mut shutdown_rx: watch::Receiver<bool>,
) -> std::io::Result<()> {
    use tokio::net::windows::named_pipe::ServerOptions;

    let mut server = ServerOptions::new()
        .first_pipe_instance(true)
        .create(endpoint)?;

    loop {
        tokio::select! {
            _ = shutdown_rx.changed() => {
                if *shutdown_rx.borrow() {
                    break;
                }
            }
            conn_res = server.connect() => {
                conn_res?;
                let connected = server;
                server = ServerOptions::new().create(endpoint)?;
                let tx_cloned = cmd_tx.clone();
                tokio::spawn(async move {
                    let (reader, mut writer) = tokio::io::split(connected);
                    let mut buf_reader = BufReader::new(reader);
                    let mut line = String::new();
                    loop {
                        line.clear();
                        match buf_reader.read_line(&mut line).await {
                            Ok(0) | Err(_) => break,
                            Ok(n) if n > MAX_IPC_FRAME_BYTES => break,
                            Ok(_) => {
                                let resp = match parse_ipc_line(&line) {
                                    Ok(req) => dispatch_command(&tx_cloned, req).await,
                                    Err(msg) => IpcResponse::Error { message: msg },
                                };
                                if let Ok(json) = serde_json::to_string(&resp) {
                                    let _ = writer.write_all(format!("{json}\n").as_bytes()).await;
                                }
                            }
                        }
                    }
                });
            }
        }
    }
    Ok(())
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let endpoint = default_ipc_endpoint();
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<QueuedCommand>(MAX_IPC_QUEUE_DEPTH);
    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    let shutdown_actor = shutdown_tx.clone();
    tokio::spawn(async move {
        let mut state = DaemonState::default();
        while let Some(cmd) = cmd_rx.recv().await {
            let resp = handle_request(cmd.req, &mut state, &shutdown_actor);
            let _ = cmd.reply.send(resp);
        }
    });

    let tx_sig = shutdown_tx.clone();
    tokio::spawn(async move {
        let _ = tokio::signal::ctrl_c().await;
        let _ = tx_sig.send(true);
    });

    run_ipc_server(&endpoint, cmd_tx, shutdown_rx).await
}
