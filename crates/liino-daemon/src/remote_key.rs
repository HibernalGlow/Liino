//! Remote key trigger (no pairing): the phone sends tap / down / up actions over
//! the existing audio connection as a cross-device plugin message on topic
//! `liino.remote_key`; the daemon synthesizes the configured desktop key so a
//! bound hotkey (e.g. a voice-input trigger) fires without touching the keyboard.
//!
//! Injection is OFF by default (dry-run logs only) so an unattended desktop never
//! receives stray keystrokes; the user arms it explicitly over IPC.

use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};

use serde::Deserialize;

/// macOS virtual keycode for F13; override over IPC to match the bound hotkey.
const DEFAULT_TARGET_KEY: u16 = 106;

static ARMED: AtomicBool = AtomicBool::new(false);
static TARGET_KEY: AtomicU16 = AtomicU16::new(DEFAULT_TARGET_KEY);

#[derive(Deserialize)]
struct KeyAction {
    action: String,
}

pub fn set_enabled(enabled: bool) {
    ARMED.store(enabled, Ordering::Relaxed);
}

pub fn enabled() -> bool {
    ARMED.load(Ordering::Relaxed)
}

pub fn set_target(keycode: u16) {
    TARGET_KEY.store(keycode, Ordering::Relaxed);
}

pub fn target() -> u16 {
    TARGET_KEY.load(Ordering::Relaxed)
}

pub fn handle_payload(payload: &[u8]) {
    let parsed: KeyAction = match serde_json::from_slice(payload) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[remote-key] bad payload: {e}");
            return;
        }
    };
    let action = parsed.action.as_str();
    if !matches!(action, "tap" | "down" | "up") {
        eprintln!("[remote-key] unknown action: {action}");
        return;
    }
    if !enabled() {
        eprintln!("[remote-key] dry-run (disarmed): {action} key={}", target());
        return;
    }
    synthesize(action, target());
}

#[cfg(target_os = "macos")]
fn synthesize(action: &str, keycode: u16) {
    use core_graphics::event::{CGEvent, CGEventTapLocation, CGKeyCode};
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
    let post = |down: bool| {
        let Ok(source) = CGEventSource::new(CGEventSourceStateID::HIDSystemState) else {
            return;
        };
        if let Ok(ev) = CGEvent::new_keyboard_event(source, keycode as CGKeyCode, down) {
            ev.post(CGEventTapLocation::HID);
        }
    };
    match action {
        "down" => post(true),
        "up" => post(false),
        _ => {
            post(true);
            post(false);
        }
    }
}

#[cfg(not(target_os = "macos"))]
fn synthesize(action: &str, keycode: u16) {
    eprintln!("[remote-key] key synthesis not implemented on this platform: {action} key={keycode}");
}