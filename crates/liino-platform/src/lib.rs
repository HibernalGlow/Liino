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
    RfcommReady,
    RequiresNativeBridge,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformProbe {
    pub os: String,
    pub virtual_mic: VirtualMicStatus,
    pub virtual_mic_driver: Option<String>,
    pub bluetooth: BluetoothCapability,
    pub adb_in_path: bool,
}

pub fn probe_current_platform() -> PlatformProbe {
    let os = std::env::consts::OS.to_string();

    #[cfg(target_os = "macos")]
    let (virtual_mic, virtual_mic_driver, bluetooth) = {
        let bh2 = Path::new("/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver").exists();
        let bh16 = Path::new("/Library/Audio/Plug-Ins/HAL/BlackHole16ch.driver").exists();
        if bh2 || bh16 {
            (
                VirtualMicStatus::Installed,
                Some(if bh2 { "BlackHole 2ch" } else { "BlackHole 16ch" }.to_string()),
                BluetoothCapability::RequiresNativeBridge,
            )
        } else {
            (
                VirtualMicStatus::Missing,
                Some("BlackHole".to_string()),
                BluetoothCapability::RequiresNativeBridge,
            )
        }
    };

    #[cfg(target_os = "windows")]
    let (virtual_mic, virtual_mic_driver, bluetooth) = (
        VirtualMicStatus::Missing,
        Some("VB-CABLE".to_string()),
        BluetoothCapability::RfcommReady,
    );

    #[cfg(target_os = "linux")]
    let (virtual_mic, virtual_mic_driver, bluetooth) = (
        VirtualMicStatus::Installed,
        Some("PipeWire".to_string()),
        BluetoothCapability::RfcommReady,
    );

    #[cfg(any(target_os = "android", target_os = "ios"))]
    let (virtual_mic, virtual_mic_driver, bluetooth) = (
        VirtualMicStatus::Unsupported,
        None,
        BluetoothCapability::RequiresNativeBridge,
    );

    let adb_in_path = command_exists("adb");

    PlatformProbe {
        os,
        virtual_mic,
        virtual_mic_driver,
        bluetooth,
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
}
