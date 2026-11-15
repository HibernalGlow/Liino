mod bluetooth;
mod engine;
mod ipc;
mod remote_key;

use ipc::{
    default_ipc_endpoint, parse_ipc_line, IpcRequest, IpcResponse, MAX_IPC_FRAME_BYTES,
    MAX_IPC_QUEUE_DEPTH,
};
use liino_core::{ResolvedRole, RoleMode, TransportType};
use liino_engine::presence::{Presence, PresenceConfig};
use liino_platform::{enriched_capabilities, probe_current_platform, VirtualMicStatus};
use micyou_core::server::{self, ServerState, StartRequest};
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot, watch};

struct DaemonState {
    role_mode: RoleMode,
    active_transport: String,
    is_running: bool,
    server: Option<Arc<ServerState>>,
    server_port: Option<u16>,
    engine_snapshot: Arc<Mutex<engine::EngineSnapshot>>,
    presence: Option<Presence>,
    bluetooth: Option<bluetooth::BluetoothLink>,
}

impl Default for DaemonState {
    fn default() -> Self {
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
            server: None,
            server_port: None,
            engine_snapshot: Arc::new(Mutex::new(engine::EngineSnapshot::default())),
            presence,
            bluetooth: None,
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

async fn handle_request(
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
            let metrics = match &state.server {
                Some(server) => server
                    .network_stats
                    .to_metrics(if state.is_running { 20 } else { 0 }),
                None => micyou_core::stats::AudioMetrics {
                    bitrate: 0,
                    sample_rate: 48_000,
                    latency_ms: 0,
                    network_latency_ms: 0,
                    packet_loss_rate: 0.0,
                    jitter_ms: 0.0,
                    buffer_duration_ms: 0,
                },
            };
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
                bluetooth_address: state
                    .bluetooth
                    .as_ref()
                    .map(|link| link.address().to_string()),
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
        IpcRequest::ListBluetoothDevices => match bluetooth::list_devices() {
            Ok(devices) => IpcResponse::BluetoothDevices { devices },
            Err(message) => IpcResponse::Error { message },
        },
        IpcRequest::ConnectBluetooth { address } => {
            state.bluetooth = None;
            match bluetooth::BluetoothLink::connect(&address, state.server_port) {
                Ok(link) => {
                    state.bluetooth = Some(link);
                    IpcResponse::Ok
                }
                Err(message) => IpcResponse::Error { message },
            }
        }
        IpcRequest::DisconnectBluetooth => {
            state.bluetooth = None;
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
        IpcRequest::SetRemoteKeyEnabled { enabled } => {
            remote_key::set_enabled(enabled);
            IpcResponse::Ok
        }
        IpcRequest::SetRemoteKeyTarget { keycode } => {
            remote_key::set_target(keycode);
            IpcResponse::Ok
        }
        IpcRequest::GetRemoteKey => IpcResponse::RemoteKeyState {
            enabled: remote_key::enabled(),
            target_key: remote_key::target(),
        },
        IpcRequest::StartLink => {
            if state.server.is_some() {
                return IpcResponse::Ok;
            }
            let mode = match state.active_transport.as_str() {
                "usb" | "bluetooth_rfcomm" => "usb",
                _ => "wifi",
            };
            let request = match StartRequest::resolve(None, Some(mode), None, None) {
                Ok(request) => request,
                Err(message) => return IpcResponse::Error { message },
            };
            let listen_port = request.port;
            let events = Arc::new(engine::LiinoEventSink::new(state.engine_snapshot.clone()));
            let server = Arc::new(ServerState::new(events, Arc::new(engine::LiinoHost), None));
            match server::start_server(&server, request).await {
                Ok(_) => {
                    let _ = server.plugins.bus.subscribe(
                        "liino.remote_key",
                        Arc::new(|msg: &micyou_core::micyou_plugin::bus::PluginMessage| {
                            remote_key::handle_payload(&msg.payload);
                        }),
                    );
                    state.server = Some(server);
                    state.server_port = Some(listen_port);
                    state.is_running = true;
                    if state.active_transport == "bluetooth_rfcomm" {
                        if let Some(addr) = state.bluetooth.take().map(|b| b.address().to_string()) {
                            match bluetooth::BluetoothLink::connect(&addr, Some(listen_port)) {
                                Ok(link) => state.bluetooth = Some(link),
                                Err(err) => {
                                    eprintln!("[liino-daemon] bluetooth rebind failed: {err}");
                                }
                            }
                        }
                    }
                    IpcResponse::Ok
                }
                Err(message) => IpcResponse::Error { message },
            }
        }
        IpcRequest::StopLink => {
            if let Some(server) = state.server.take() {
                let _ = server::stop_server(&server).await;
                server::service::close_output_device(&server);
            }
            state.server_port = None;
            state.is_running = false;
            IpcResponse::Ok
        }
        IpcRequest::ShutdownDaemon => {
            if let Some(server) = state.server.take() {
                let _ = server::stop_server(&server).await;
                server::service::close_output_device(&server);
            }
            state.is_running = false;
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
            let resp = handle_request(cmd.req, &mut state, &shutdown_actor).await;
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
