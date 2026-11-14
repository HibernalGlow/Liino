//! `liino-core`: Unified, platform-agnostic domain models, capability detection,
//! and bounded memory primitives for liino.

use std::collections::VecDeque;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoleMode {
    Auto,
    Sender,
    Receiver,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResolvedRole {
    Sender,
    Receiver,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportType {
    LanWifi,
    Usb,
    BluetoothRfcomm,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceCapabilities {
    pub platform_name: String,
    pub can_capture_audio: bool,
    pub can_play_audio: bool,
    pub can_virtual_microphone: bool,
    pub supported_transports: Vec<TransportType>,
}

impl DeviceCapabilities {
    /// Detects baseline capabilities for the current compile target.
    /// Platform adapters will refine runtime device availability in Phase 2+.
    pub fn detect_current() -> Self {
        #[cfg(any(target_os = "android", target_os = "ios"))]
        {
            Self {
                platform_name: std::env::consts::OS.to_string(),
                can_capture_audio: true,
                can_play_audio: true,
                can_virtual_microphone: false,
                supported_transports: vec![
                    TransportType::LanWifi,
                    TransportType::Usb,
                    TransportType::BluetoothRfcomm,
                ],
            }
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        {
            Self {
                platform_name: std::env::consts::OS.to_string(),
                can_capture_audio: true,
                can_play_audio: true,
                can_virtual_microphone: true,
                supported_transports: vec![
                    TransportType::LanWifi,
                    TransportType::Usb,
                    TransportType::BluetoothRfcomm,
                ],
            }
        }
    }

    pub fn default_role(&self) -> ResolvedRole {
        #[cfg(any(target_os = "android", target_os = "ios"))]
        {
            ResolvedRole::Sender
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        {
            if self.can_virtual_microphone || self.can_play_audio {
                ResolvedRole::Receiver
            } else {
                ResolvedRole::Sender
            }
        }
    }

    pub fn supports_role(&self, role: ResolvedRole) -> bool {
        match role {
            ResolvedRole::Sender => self.can_capture_audio,
            ResolvedRole::Receiver => self.can_play_audio || self.can_virtual_microphone,
        }
    }

    pub fn resolve_role(&self, mode: RoleMode) -> Result<ResolvedRole, String> {
        let target = match mode {
            RoleMode::Auto => self.default_role(),
            RoleMode::Sender => ResolvedRole::Sender,
            RoleMode::Receiver => ResolvedRole::Receiver,
        };
        if self.supports_role(target) {
            Ok(target)
        } else {
            Err(format!(
                "Platform '{}' does not support role {:?}",
                self.platform_name, target
            ))
        }
    }
}

/// Fixed-capacity ring buffer to guarantee bounded memory in audio/telemetry paths.
#[derive(Debug)]
pub struct BoundedRingBuffer<T> {
    capacity: usize,
    buf: VecDeque<T>,
}

impl<T> BoundedRingBuffer<T> {
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "BoundedRingBuffer capacity must be > 0");
        Self {
            capacity,
            buf: VecDeque::with_capacity(capacity),
        }
    }

    pub fn push_overwrite(&mut self, item: T) -> Option<T> {
        let evicted = if self.buf.len() == self.capacity {
            self.buf.pop_front()
        } else {
            None
        };
        self.buf.push_back(item);
        evicted
    }

    pub fn len(&self) -> usize {
        self.buf.len()
    }

    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn drain_all(&mut self) -> Vec<T> {
        self.buf.drain(..).collect()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct EngineSnapshot {
    pub role_mode: RoleMode,
    pub resolved_role: ResolvedRole,
    pub is_running: bool,
    pub rtt_ms: u32,
    pub jitter_ms: f32,
    pub packet_loss: f32,
    pub ring_buffer_len: usize,
    pub ring_buffer_capacity: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ring_buffer_stays_bounded() {
        let mut rb = BoundedRingBuffer::new(3);
        assert_eq!(rb.push_overwrite(1), None);
        assert_eq!(rb.push_overwrite(2), None);
        assert_eq!(rb.push_overwrite(3), None);
        assert_eq!(rb.push_overwrite(4), Some(1));
        assert_eq!(rb.len(), 3);
        assert_eq!(rb.drain_all(), vec![2, 3, 4]);
    }

    #[test]
    fn capability_resolution_respects_constraints() {
        let mobile = DeviceCapabilities {
            platform_name: "android".into(),
            can_capture_audio: true,
            can_play_audio: false,
            can_virtual_microphone: false,
            supported_transports: vec![TransportType::LanWifi],
        };
        assert_eq!(mobile.resolve_role(RoleMode::Sender), Ok(ResolvedRole::Sender));
        assert!(mobile.resolve_role(RoleMode::Receiver).is_err());
    }
}
