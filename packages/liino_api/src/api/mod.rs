use flutter_rust_bridge::frb;
use liino_core::{
    BoundedRingBuffer, DeviceCapabilities, EngineSnapshot, ResolvedRole, RoleMode, TransportType,
};

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[derive(Debug, Clone)]
pub struct FrbDeviceCapabilities {
    pub platform_name: String,
    pub can_capture_audio: bool,
    pub can_play_audio: bool,
    pub can_virtual_microphone: bool,
    pub supported_transports: Vec<String>,
    pub default_role: String,
}

#[derive(Debug, Clone)]
pub struct FrbEngineSnapshot {
    pub role_mode: String,
    pub resolved_role: String,
    pub is_running: bool,
    pub rtt_ms: u32,
    pub jitter_ms: f32,
    pub packet_loss: f32,
    pub ring_buffer_len: usize,
    pub ring_buffer_capacity: usize,
}

#[derive(Debug, Clone)]
pub struct FrbNetworkInterface {
    pub interface_name: String,
    pub ip: String,
}

/// LAN interfaces as detected by the vendored MicYou core. Used by the device
/// page to show which address a peer can reach.
#[frb(sync)]
pub fn network_interfaces() -> Vec<FrbNetworkInterface> {
    micyou_core::discovery::query_network_interfaces()
        .into_iter()
        .map(|iface| FrbNetworkInterface {
            interface_name: iface.interface_name,
            ip: iface.ip,
        })
        .collect()
}

#[frb(sync)]
pub fn detect_capabilities() -> FrbDeviceCapabilities {
    let caps = DeviceCapabilities::detect_current();
    let default_role = match caps.default_role() {
        ResolvedRole::Sender => "sender",
        ResolvedRole::Receiver => "receiver",
    };
    FrbDeviceCapabilities {
        platform_name: caps.platform_name,
        can_capture_audio: caps.can_capture_audio,
        can_play_audio: caps.can_play_audio,
        can_virtual_microphone: caps.can_virtual_microphone,
        supported_transports: caps
            .supported_transports
            .into_iter()
            .map(|t| match t {
                TransportType::LanWifi => "lan_wifi".to_string(),
                TransportType::Usb => "usb".to_string(),
                TransportType::BluetoothRfcomm => "bluetooth_rfcomm".to_string(),
            })
            .collect(),
        default_role: default_role.to_string(),
    }
}

#[frb(sync)]
pub fn preview_snapshot(mode: String) -> Result<FrbEngineSnapshot, String> {
    let caps = DeviceCapabilities::detect_current();
    let parsed_mode = match mode.as_str() {
        "auto" => RoleMode::Auto,
        "sender" => RoleMode::Sender,
        "receiver" => RoleMode::Receiver,
        other => return Err(format!("Unknown role mode: {other}")),
    };
    let resolved = caps.resolve_role(parsed_mode)?;
    let mut rb = BoundedRingBuffer::new(64);
    for i in 0..16 {
        rb.push_overwrite(i);
    }
    let snap = EngineSnapshot {
        role_mode: parsed_mode,
        resolved_role: resolved,
        is_running: false,
        rtt_ms: 0,
        jitter_ms: 0.0,
        packet_loss: 0.0,
        ring_buffer_len: rb.len(),
        ring_buffer_capacity: rb.capacity(),
    };
    Ok(FrbEngineSnapshot {
        role_mode: mode,
        resolved_role: match snap.resolved_role {
            ResolvedRole::Sender => "sender".to_string(),
            ResolvedRole::Receiver => "receiver".to_string(),
        },
        is_running: snap.is_running,
        rtt_ms: snap.rtt_ms,
        jitter_ms: snap.jitter_ms,
        packet_loss: snap.packet_loss,
        ring_buffer_len: snap.ring_buffer_len,
        ring_buffer_capacity: snap.ring_buffer_capacity,
    })
}
