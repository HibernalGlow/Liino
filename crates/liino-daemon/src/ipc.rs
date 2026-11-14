use liino_engine::presence::PeerInfo;
use serde::{Deserialize, Serialize};

/// Hard ceiling on a single IPC JSON line to prevent unbounded heap allocation.
pub const MAX_IPC_FRAME_BYTES: usize = 16 * 1024;
/// Bounded control command queue depth inside the daemon.
pub const MAX_IPC_QUEUE_DEPTH: usize = 128;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IpcRequest {
    Ping,
    GetStatus,
    GetPeers,
    ConnectPeer { id: String },
    DisconnectPeer,
    SetRoleMode { mode: String },
    SetTransport { transport: String },
    StartLink,
    StopLink,
    ShutdownDaemon,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IpcResponse {
    Pong {
        pid: u32,
    },
    Status {
        pid: u32,
        platform: String,
        role_mode: String,
        resolved_role: String,
        active_transport: String,
        is_running: bool,
        virtual_mic_installed: bool,
        virtual_mic_driver: Option<String>,
        rtt_ms: i64,
        jitter_ms: f64,
        packet_loss_rate: f64,
        bitrate: i32,
        sample_rate: i32,
        buffer_duration_ms: i64,
    },
    Peers {
        peers: Vec<PeerInfo>,
        connected: Option<PeerInfo>,
        connecting: Option<String>,
    },
    Ok,
    Error {
        message: String,
    },
}

pub fn default_ipc_endpoint() -> String {
    #[cfg(windows)]
    {
        r"\\.\pipe\liino-daemon".to_string()
    }
    #[cfg(unix)]
    {
        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            format!("{runtime_dir}/liino-daemon.sock")
        } else {
            "/tmp/liino-daemon.sock".to_string()
        }
    }
}

pub fn parse_ipc_line(line: &str) -> Result<IpcRequest, String> {
    if line.len() > MAX_IPC_FRAME_BYTES {
        return Err(format!(
            "IPC frame exceeds {} byte limit",
            MAX_IPC_FRAME_BYTES
        ));
    }
    serde_json::from_str(line.trim()).map_err(|e| format!("Invalid IPC JSON: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_oversized_ipc_frame() {
        let huge = "x".repeat(MAX_IPC_FRAME_BYTES + 1);
        assert!(parse_ipc_line(&huge).is_err());
    }

    #[test]
    fn roundtrips_ipc_request_and_response() {
        let req = IpcRequest::SetRoleMode {
            mode: "receiver".to_string(),
        };
        let encoded = serde_json::to_string(&req).unwrap();
        let decoded = parse_ipc_line(&encoded).unwrap();
        assert_eq!(decoded, req);

        let resp = IpcResponse::Pong { pid: 42 };
        let resp_json = serde_json::to_string(&resp).unwrap();
        let parsed: IpcResponse = serde_json::from_str(&resp_json).unwrap();
        assert_eq!(parsed, resp);
    }
}
