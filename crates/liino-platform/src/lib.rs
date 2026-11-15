use liino_core::{DeviceCapabilities, TransportType};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VirtualMicStatus {
    Installed,
    Missing,
    Unsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BluetoothCapability {
    RfcommClientAndServer,
    RfcommClientWithSdpHelper,
    Unsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BluetoothBackendKind {
    WebBluetoothRfcomm,
    WebBluetoothWithMacSdpShim,
    Unsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RfcommConnectionRole {
    Client,
    Server,
}

/// Resolves the RFCOMM connection initiator role independently from the audio
/// sender/receiver role (ADR-0001):
/// - Android <-> Windows: Windows listens (Server), Android connects (Client).
/// - Android <-> macOS: Android listens (Server), macOS queries SDP & connects (Client).
pub fn recommended_rfcomm_role(local_os: &str, peer_os: &str) -> Option<RfcommConnectionRole> {
    match (local_os, peer_os) {
        ("windows", "android") => Some(RfcommConnectionRole::Server),
        ("android", "windows") => Some(RfcommConnectionRole::Client),
        ("android", "macos") => Some(RfcommConnectionRole::Server),
        ("macos", "android") => Some(RfcommConnectionRole::Client),
        ("linux", "android") => Some(RfcommConnectionRole::Server),
        ("android", "linux") => Some(RfcommConnectionRole::Client),
        _ => None,
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformProbe {
    pub os: String,
    pub virtual_mic: VirtualMicStatus,
    pub virtual_mic_driver: Option<String>,
    pub bluetooth: BluetoothCapability,
    pub bluetooth_backend: BluetoothBackendKind,
    pub adb_in_path: bool,
}

pub fn probe_current_platform() -> PlatformProbe {
    let os = std::env::consts::OS.to_string();

    #[cfg(target_os = "macos")]
    let (virtual_mic, virtual_mic_driver, bluetooth, bluetooth_backend) = {
        let bh2 = Path::new("/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver").exists();
        let bh16 = Path::new("/Library/Audio/Plug-Ins/HAL/BlackHole16ch.driver").exists();
        (
            if bh2 || bh16 {
                VirtualMicStatus::Installed
            } else {
                VirtualMicStatus::Missing
            },
            Some(if bh2 {
                "BlackHole 2ch"
            } else if bh16 {
                "BlackHole 16ch"
            } else {
                "BlackHole"
            }
            .to_string()),
            BluetoothCapability::RfcommClientWithSdpHelper,
            BluetoothBackendKind::WebBluetoothWithMacSdpShim,
        )
    };

    #[cfg(target_os = "windows")]
    let (virtual_mic, virtual_mic_driver, bluetooth, bluetooth_backend) = (
        VirtualMicStatus::Missing,
        Some("VB-CABLE".to_string()),
        BluetoothCapability::RfcommClientAndServer,
        BluetoothBackendKind::WebBluetoothRfcomm,
    );

    #[cfg(target_os = "linux")]
    let (virtual_mic, virtual_mic_driver, bluetooth, bluetooth_backend) = (
        VirtualMicStatus::Installed,
        Some("PipeWire".to_string()),
        BluetoothCapability::RfcommClientAndServer,
        BluetoothBackendKind::WebBluetoothRfcomm,
    );

    #[cfg(target_os = "android")]
    let (virtual_mic, virtual_mic_driver, bluetooth, bluetooth_backend) = (
        VirtualMicStatus::Unsupported,
        None,
        BluetoothCapability::RfcommClientAndServer,
        BluetoothBackendKind::WebBluetoothRfcomm,
    );

    #[cfg(target_os = "ios")]
    let (virtual_mic, virtual_mic_driver, bluetooth, bluetooth_backend) = (
        VirtualMicStatus::Unsupported,
        None,
        BluetoothCapability::Unsupported,
        BluetoothBackendKind::Unsupported,
    );

    let adb_in_path = command_exists("adb");

    PlatformProbe {
        os,
        virtual_mic,
        virtual_mic_driver,
        bluetooth,
        bluetooth_backend,
        adb_in_path,
    }
}

pub fn enriched_capabilities() -> DeviceCapabilities {
    let mut caps = DeviceCapabilities::detect_current();
    let probe = probe_current_platform();
    caps.can_virtual_microphone = probe.virtual_mic == VirtualMicStatus::Installed;
    if !caps.supported_transports.contains(&TransportType::LanWifi) {
        caps.supported_transports.push(TransportType::LanWifi);
    }
    caps
}

fn command_exists(bin: &str) -> bool {
    let Some(paths) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&paths).any(|dir| {
        let candidate = dir.join(bin);
        candidate.is_file()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_returns_valid_os_and_capabilities() {
        let probe = probe_current_platform();
        assert!(!probe.os.is_empty());
        let caps = enriched_capabilities();
        assert_eq!(caps.platform_name, probe.os);
    }

    #[test]
    fn rfcomm_topology_decouples_initiator_from_audio_role() {
        assert_eq!(
            recommended_rfcomm_role("windows", "android"),
            Some(RfcommConnectionRole::Server)
        );
        assert_eq!(
            recommended_rfcomm_role("macos", "android"),
            Some(RfcommConnectionRole::Client)
        );
        assert_eq!(
            recommended_rfcomm_role("android", "macos"),
            Some(RfcommConnectionRole::Server)
        );
    }
}
