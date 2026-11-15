//! liino's sink for micyou-core's `ServerEvents`.
//!
//! The daemon hosts the real `micyou-core` server (ADR-0004). The core never
//! talks to a UI toolkit; it fans events out through this sink. For now the
//! sink captures a live snapshot (connection / mute / monitoring / metrics)
//! that the IPC layer reads, and logs lifecycle edges. Pushing these to IPC
//! subscribers (ADR-0004 decision 3, event subscription) is the next step.

use micyou_core::events::{AecStatus, DownloadProgress, ServerEvents, SpectrumPayload};
use micyou_core::host::{HostIntegration, HotkeyCallback};
use micyou_core::stats::AudioMetrics;
use micyou_core::transport::tcp::DeviceInfo;
use std::sync::{Arc, Mutex};

/// liino's host integration (ADR-0001 thin adapt layer, ADR-0004 decision 4).
///
/// The OS-level pieces — tray, notifications, global hotkeys, plugin windows —
/// are pending; for now they log and succeed so the core server runs headless
/// without pulling the upstream `headless-host` dependencies. `open_plugin_panel`
/// will later forward to the GUI over IPC (the core stays UI-free).
pub struct LiinoHost;

impl HostIntegration for LiinoHost {
    fn open_url(&self, url: &str) -> Result<(), String> {
        eprintln!("[host] open_url (pending): {url}");
        Ok(())
    }

    fn notify(&self, title: &str, body: &str) -> Result<(), String> {
        eprintln!("[host] notify (pending): {title} — {body}");
        Ok(())
    }

    fn register_hotkey(&self, shortcut: &str, _on_press: HotkeyCallback) -> Result<(), String> {
        eprintln!("[host] register_hotkey (pending): {shortcut}");
        Ok(())
    }

    fn open_plugin_panel(&self, plugin_id: &str, panel_id: &str, title: &str) -> Result<(), String> {
        eprintln!("[host] open_plugin_panel (pending IPC forward): {plugin_id}/{panel_id} \"{title}\"");
        Ok(())
    }
}

/// Latest engine state, shared between the event sink and the IPC actor.
#[derive(Default, Clone)]
pub struct EngineSnapshot {
    pub connected: bool,
    pub peer_name: Option<String>,
    pub peer_ip: Option<String>,
    pub muted: bool,
    pub monitoring: bool,
    pub last_metrics: Option<AudioMetrics>,
}

pub struct LiinoEventSink {
    snapshot: Arc<Mutex<EngineSnapshot>>,
}

impl LiinoEventSink {
    pub fn new(snapshot: Arc<Mutex<EngineSnapshot>>) -> Self {
        Self { snapshot }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, EngineSnapshot> {
        self.snapshot.lock().unwrap_or_else(|p| p.into_inner())
    }
}

impl ServerEvents for LiinoEventSink {
    fn device_connected(&self, info: DeviceInfo) {
        eprintln!("[engine] device connected: {} ({})", info.name, info.ip);
        let mut snap = self.lock();
        snap.connected = true;
        snap.peer_name = Some(info.name);
        snap.peer_ip = Some(info.ip);
    }

    fn device_disconnected(&self) {
        eprintln!("[engine] device disconnected");
        let mut snap = self.lock();
        snap.connected = false;
        snap.peer_name = None;
        snap.peer_ip = None;
    }

    fn audio_metrics(&self, metrics: AudioMetrics) {
        self.lock().last_metrics = Some(metrics);
    }

    fn udp_audio_warning(&self) {
        eprintln!("[engine] UDP audio warning (no audio packets)");
    }

    fn mute_state_changed(&self, is_muted: bool) {
        self.lock().muted = is_muted;
    }

    fn audio_level(&self, _level: u32) {
        // High-frequency; not captured in the snapshot. Future: throttle-push.
    }

    fn audio_spectrum(&self, _spectrum: SpectrumPayload) {
        // High-frequency; not captured in the snapshot. Future: throttle-push.
    }

    fn server_stopped(&self) {
        eprintln!("[engine] server stopped");
        let mut snap = self.lock();
        snap.connected = false;
        snap.peer_name = None;
        snap.peer_ip = None;
    }

    fn web_client_count(&self, _count: u32) {}

    fn install_progress(&self, message: String) {
        eprintln!("[engine] install: {message}");
    }

    fn aec_status_changed(&self, _status: AecStatus) {}

    fn monitoring_state_changed(&self, enabled: bool) {
        self.lock().monitoring = enabled;
    }

    fn plugin_download_progress(&self, _progress: DownloadProgress) {}
}