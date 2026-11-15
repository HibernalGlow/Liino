//! macOS Bluetooth link over the bundled Swift helper.
//!
//! The helper owns `IOBluetooth` (ADR-0009) and bridges the RFCOMM channel to
//! its stdin/stdout. The daemon treats that pipe as a raw byte stream; framing
//! is added by the transport layer.

use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::thread;
use std::time::Duration;

const CONNECT_GRACE: Duration = Duration::from_millis(900);

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

pub struct BluetoothLink {
    address: String,
    child: Child,
    stdin: ChildStdin,
    _reader: thread::JoinHandle<()>,
}

impl BluetoothLink {
    pub fn connect(address: &str) -> Result<Self, String> {
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

        // Drain incoming bytes so a slow consumer cannot block the helper.
        // The transport layer will replace this with a framed channel.
        let reader = thread::spawn(move || {
            let mut reader = std::io::BufReader::new(stdout);
            let mut buffer = [0u8; 4096];
            while let Ok(read) = reader.read(&mut buffer) {
                if read == 0 {
                    break;
                }
            }
        });

        thread::sleep(CONNECT_GRACE);
        if let Some(status) = child
            .try_wait()
            .map_err(|e| format!("helper status: {e}"))?
        {
            return Err(format!("Bluetooth helper exited early ({status})"));
        }

        Ok(Self {
            address: address.to_string(),
            child,
            stdin,
            _reader: reader,
        })
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    /// Writes raw bytes to the RFCOMM channel. Used once the framed transport
    /// lands; kept here so the link and the pipe stay a single unit.
    #[allow(dead_code)]
    pub fn write(&mut self, bytes: &[u8]) -> Result<(), String> {
        self.stdin
            .write_all(bytes)
            .and_then(|_| self.stdin.flush())
            .map_err(|e| format!("bluetooth write: {e}"))
    }
}

impl Drop for BluetoothLink {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
