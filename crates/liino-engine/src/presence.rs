//! LAN presence discovery and a minimal control channel.
//!
//! Each instance announces a JSON identity over UDP broadcast and answers TCP
//! handshakes on an ephemeral port. This is the "see each other" layer only:
//! audio transport is wired separately (LAN first, Bluetooth RFCOMM later).
//!
//! Threads are owned by the presence instance and stopped via [`Presence::shutdown`].

use liino_protocol::{DISCOVERY_PORT, PRESENCE_VERSION};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{IpAddr, Shutdown, SocketAddr, TcpListener, TcpStream, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

/// Peers disappear from the list when no announcement arrives for this long.
pub const PEER_TIMEOUT: Duration = Duration::from_secs(6);
const ANNOUNCE_INTERVAL: Duration = Duration::from_millis(1500);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(3);
const ACCEPT_POLL: Duration = Duration::from_millis(150);

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Announcement {
    pub v: u32,
    pub id: String,
    pub name: String,
    pub platform: String,
    pub role: String,
    pub control_port: u16,
    #[serde(default)]
    pub transports: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PeerInfo {
    pub id: String,
    pub name: String,
    pub platform: String,
    pub role: String,
    pub address: String,
    pub control_port: u16,
    pub transports: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Handshake {
    v: u32,
    id: String,
    name: String,
}

struct Inner {
    identity: Mutex<Announcement>,
    peers: Mutex<HashMap<String, (PeerInfo, Instant)>>,
    connected: Mutex<Option<PeerInfo>>,
    connecting: Mutex<Option<String>>,
    stream: Mutex<Option<TcpStream>>,
    stop: AtomicBool,
    discovery_port: u16,
}

impl Inner {
    fn me(&self) -> Announcement {
        self.identity
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_else(|poison| poison.into_inner().clone())
    }

    fn remember_peer(&self, peer: PeerInfo) {
        let mut peers = self
            .peers
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        peers.insert(peer.id.clone(), (peer, Instant::now()));
    }

    fn clear_connected(&self, id: &str) {
        let mut connected = self
            .connected
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if connected.as_ref().is_some_and(|peer| peer.id == id) {
            *connected = None;
        }
    }
}

pub struct Presence {
    inner: Arc<Inner>,
}

pub struct PresenceConfig {
    pub name: String,
    pub platform: String,
    pub role: String,
    pub transports: Vec<String>,
}

impl Presence {
    /// Starts discovery on the protocol port with an ephemeral control port.
    pub fn start(config: PresenceConfig) -> Result<Self, String> {
        Self::start_on(config, DISCOVERY_PORT)
    }

    /// Testable variant with an explicit discovery port. `control_port` is
    /// always ephemeral and published in the announcement.
    pub fn start_on(config: PresenceConfig, discovery_port: u16) -> Result<Self, String> {
        let listener =
            TcpListener::bind(("0.0.0.0", 0)).map_err(|e| format!("bind control port: {e}"))?;
        let control_port = listener
            .local_addr()
            .map_err(|e| format!("read control port: {e}"))?
            .port();
        listener
            .set_nonblocking(true)
            .map_err(|e| format!("control listener nonblocking: {e}"))?;

        let udp = bind_discovery_socket(discovery_port)?;

        let identity = Announcement {
            v: PRESENCE_VERSION,
            id: new_instance_id(),
            name: config.name,
            platform: config.platform,
            role: config.role,
            control_port,
            transports: config.transports,
        };

        let inner = Arc::new(Inner {
            identity: Mutex::new(identity),
            peers: Mutex::new(HashMap::new()),
            connected: Mutex::new(None),
            connecting: Mutex::new(None),
            stream: Mutex::new(None),
            stop: AtomicBool::new(false),
            discovery_port,
        });

        spawn_announcer(inner.clone(), udp.try_clone().map_err(|e| e.to_string())?);
        spawn_receiver(inner.clone(), udp);
        spawn_acceptor(inner.clone(), listener);

        Ok(Presence { inner })
    }

    pub fn local_id(&self) -> String {
        self.inner.me().id
    }

    pub fn local_name(&self) -> String {
        self.inner.me().name
    }

    pub fn control_port(&self) -> u16 {
        self.inner.me().control_port
    }

    /// Updates the advertised role without restarting discovery.
    pub fn set_role(&self, role: &str) {
        let mut identity = self
            .inner
            .identity
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        identity.role = role.to_string();
    }

    /// Live peers, pruned by [`PEER_TIMEOUT`], sorted by display name.
    pub fn peers(&self) -> Vec<PeerInfo> {
        let now = Instant::now();
        let mut peers = self
            .inner
            .peers
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        peers.retain(|_, (_, seen)| now.duration_since(*seen) <= PEER_TIMEOUT);
        let mut values: Vec<PeerInfo> = peers.values().map(|(peer, _)| peer.clone()).collect();
        values.sort_by(|a, b| a.name.cmp(&b.name).then(a.id.cmp(&b.id)));
        values
    }

    pub fn connected(&self) -> Option<PeerInfo> {
        self.inner
            .connected
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .clone()
    }

    pub fn connecting(&self) -> Option<String> {
        self.inner
            .connecting
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .clone()
    }

    /// Connects to a discovered peer without blocking the caller. The result is
    /// observed through [`Presence::connected`] / [`Presence::connecting`].
    pub fn request_connect(&self, peer_id: &str) -> Result<(), String> {
        let peer = self
            .peers()
            .into_iter()
            .find(|peer| peer.id == peer_id)
            .ok_or_else(|| format!("Unknown peer: {peer_id}"))?;

        {
            let mut connecting = self
                .inner
                .connecting
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            if connecting.is_some() {
                return Err("A connection attempt is already in progress".to_string());
            }
            *connecting = Some(peer_id.to_string());
        }

        let inner = self.inner.clone();
        thread::spawn(move || {
            let result = connect_out(inner.clone(), peer.clone());
            let mut connecting = inner
                .connecting
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            *connecting = None;
            if let Err(error) = result {
                log::warn!("presence connect to {} failed: {error}", peer.id);
                inner.clear_connected(&peer.id);
            }
        });
        Ok(())
    }

    pub fn disconnect(&self) {
        if let Some(stream) = self
            .inner
            .stream
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .take()
        {
            let _ = stream.shutdown(Shutdown::Both);
        }
        *self
            .inner
            .connected
            .lock()
            .unwrap_or_else(|poison| poison.into_inner()) = None;
    }

    /// Stops background threads and closes any active link.
    pub fn shutdown(&self) {
        self.disconnect();
        self.inner.stop.store(true, Ordering::SeqCst);
    }
}

impl Drop for Presence {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn connect_out(inner: Arc<Inner>, peer: PeerInfo) -> Result<(), String> {
    let ip: IpAddr = peer
        .address
        .parse()
        .map_err(|e| format!("Invalid peer address {}: {e}", peer.address))?;
    let addr = SocketAddr::new(ip, peer.control_port);

    let mut stream = TcpStream::connect_timeout(&addr, HANDSHAKE_TIMEOUT)
        .map_err(|e| format!("connect {}: {e}", peer.address))?;
    stream
        .set_read_timeout(Some(HANDSHAKE_TIMEOUT))
        .map_err(|e| e.to_string())?;
    stream
        .set_nodelay(true)
        .map_err(|e| e.to_string())?;

    let me = inner.me();
    let hello = Handshake {
        v: PRESENCE_VERSION,
        id: me.id,
        name: me.name,
    };
    let line = serde_json::to_string(&hello).map_err(|e| e.to_string())?;
    stream
        .write_all(format!("{line}\n").as_bytes())
        .map_err(|e| format!("handshake write: {e}"))?;
    stream.flush().map_err(|e| e.to_string())?;

    let mut reader = BufReader::new(stream.try_clone().map_err(|e| e.to_string())?);
    let mut reply = String::new();
    reader
        .read_line(&mut reply)
        .map_err(|e| format!("handshake read: {e}"))?;
    let _: Handshake =
        serde_json::from_str(reply.trim()).map_err(|e| format!("invalid handshake: {e}"))?;

    stream.set_read_timeout(None).ok();
    *inner
        .stream
        .lock()
        .unwrap_or_else(|poison| poison.into_inner()) = Some(stream);
    *inner
        .connected
        .lock()
        .unwrap_or_else(|poison| poison.into_inner()) = Some(peer.clone());
    *inner
        .connecting
        .lock()
        .unwrap_or_else(|poison| poison.into_inner()) = None;

    // Hold the link open until the peer closes it or we shut down.
    let mut sink = [0u8; 64];
    loop {
        match reader.read(&mut sink) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
    }
    inner.clear_connected(&peer.id);
    Ok(())
}

fn spawn_announcer(inner: Arc<Inner>, udp: UdpSocket) {
    thread::spawn(move || {
        let port = inner.discovery_port;
        let targets = [
            SocketAddr::from(([255, 255, 255, 255], port)),
            SocketAddr::from(([127, 0, 0, 1], port)),
        ];
        while !inner.stop.load(Ordering::SeqCst) {
            if let Ok(payload) = serde_json::to_vec(&inner.me()) {
                for target in &targets {
                    let _ = udp.send_to(&payload, target);
                }
            }
            sleep_while(&inner.stop, ANNOUNCE_INTERVAL);
        }
    });
}

fn spawn_receiver(inner: Arc<Inner>, udp: UdpSocket) {
    thread::spawn(move || {
        let mut buf = [0u8; 2048];
        while !inner.stop.load(Ordering::SeqCst) {
            match udp.recv_from(&mut buf) {
                Ok((len, from)) => {
                    let Ok(message) = serde_json::from_slice::<Announcement>(&buf[..len]) else {
                        continue;
                    };
                    if message.v != PRESENCE_VERSION || message.id == inner.me().id {
                        continue;
                    }
                    inner.remember_peer(PeerInfo {
                        id: message.id,
                        name: message.name,
                        platform: message.platform,
                        role: message.role,
                        address: from.ip().to_string(),
                        control_port: message.control_port,
                        transports: message.transports,
                    });
                }
                Err(_) => {}
            }
        }
    });
}

fn spawn_acceptor(inner: Arc<Inner>, listener: TcpListener) {
    thread::spawn(move || {
        while !inner.stop.load(Ordering::SeqCst) {
            match listener.accept() {
                Ok((stream, from)) => {
                    let inner = inner.clone();
                    thread::spawn(move || handle_incoming(inner, stream, from));
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(ACCEPT_POLL);
                }
                Err(_) => thread::sleep(ACCEPT_POLL),
            }
        }
    });
}

fn handle_incoming(inner: Arc<Inner>, mut stream: TcpStream, from: SocketAddr) {
    // Accepted sockets inherit the listener's non-blocking flag on BSD/macOS.
    if stream.set_nonblocking(false).is_err() {
        return;
    }
    stream.set_read_timeout(Some(HANDSHAKE_TIMEOUT)).ok();
    stream.set_nodelay(true).ok();
    let Ok(read_half) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(read_half);
    let mut line = String::new();
    if reader.read_line(&mut line).is_err() {
        return;
    }
    let Ok(hello) = serde_json::from_str::<Handshake>(line.trim()) else {
        return;
    };
    if hello.v != PRESENCE_VERSION || hello.id == inner.me().id {
        return;
    }

    let me = inner.me();
    let reply = Handshake {
        v: PRESENCE_VERSION,
        id: me.id,
        name: me.name,
    };
    let Ok(payload) = serde_json::to_string(&reply) else {
        return;
    };
    if stream
        .write_all(format!("{payload}\n").as_bytes())
        .and_then(|_| stream.flush())
        .is_err()
    {
        return;
    }

    let known = inner
        .peers
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .get(&hello.id)
        .map(|(peer, _)| peer.clone());
    let peer = known.unwrap_or(PeerInfo {
        id: hello.id.clone(),
        name: hello.name,
        platform: "unknown".to_string(),
        role: "unknown".to_string(),
        address: from.ip().to_string(),
        control_port: from.port(),
        transports: Vec::new(),
    });
    inner.remember_peer(peer.clone());
    *inner
        .connected
        .lock()
        .unwrap_or_else(|poison| poison.into_inner()) = Some(peer.clone());
    *inner
        .stream
        .lock()
        .unwrap_or_else(|poison| poison.into_inner()) = stream.try_clone().ok();

    // Idle is normal once the handshake is done; only EOF means disconnect.
    let _ = stream.set_read_timeout(None);
    let mut reader = BufReader::new(stream);

    let mut sink = [0u8; 64];
    while matches!(reader.read(&mut sink), Ok(n) if n > 0) {}
    inner.clear_connected(&peer.id);
}

fn bind_discovery_socket(port: u16) -> Result<UdpSocket, String> {
    let socket = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::DGRAM,
        Some(socket2::Protocol::UDP),
    )
    .map_err(|e| format!("discovery socket: {e}"))?;
    socket
        .set_reuse_address(true)
        .map_err(|e| format!("reuse address: {e}"))?;
    #[cfg(unix)]
    socket
        .set_reuse_port(true)
        .map_err(|e| format!("reuse port: {e}"))?;
    socket
        .set_broadcast(true)
        .map_err(|e| format!("broadcast: {e}"))?;
    socket
        .bind(&SocketAddr::from(([0, 0, 0, 0], port)).into())
        .map_err(|e| format!("bind discovery port {port}: {e}"))?;
    socket
        .set_read_timeout(Some(Duration::from_millis(400)))
        .map_err(|e| format!("read timeout: {e}"))?;
    Ok(socket.into())
}

fn new_instance_id() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{:x}-{:x}", std::process::id(), nanos)
}

fn sleep_while(stop: &AtomicBool, total: Duration) {
    let step = Duration::from_millis(100);
    let mut waited = Duration::ZERO;
    while waited < total && !stop.load(Ordering::SeqCst) {
        thread::sleep(step);
        waited += step;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(name: &str, role: &str) -> PresenceConfig {
        PresenceConfig {
            name: name.to_string(),
            platform: "test".to_string(),
            role: role.to_string(),
            transports: vec!["lan_wifi".to_string()],
        }
    }

    #[test]
    fn announcement_roundtrip() {
        let message = Announcement {
            v: PRESENCE_VERSION,
            id: "abc".into(),
            name: "Mac".into(),
            platform: "macos".into(),
            role: "receiver".into(),
            control_port: 4242,
            transports: vec!["lan_wifi".into()],
        };
        let encoded = serde_json::to_vec(&message).unwrap();
        let decoded: Announcement = serde_json::from_slice(&encoded).unwrap();
        assert_eq!(message, decoded);
    }

    #[test]
    fn two_instances_discover_and_connect() {
        let port = 19126;
        let a = Presence::start_on(config("A", "receiver"), port).unwrap();
        let b = Presence::start_on(config("B", "sender"), port).unwrap();

        let deadline = Instant::now() + Duration::from_secs(5);
        let mut seen = false;
        while Instant::now() < deadline {
            if a.peers().iter().any(|p| p.id == b.local_id())
                && b.peers().iter().any(|p| p.id == a.local_id())
            {
                seen = true;
                break;
            }
            thread::sleep(Duration::from_millis(100));
        }
        assert!(seen, "instances did not discover each other");

        let target = a
            .peers()
            .into_iter()
            .find(|p| p.id == b.local_id())
            .unwrap();
        a.request_connect(&target.id).unwrap();

        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if a.connected().is_some() && b.connected().is_some() {
                break;
            }
            thread::sleep(Duration::from_millis(100));
        }
        assert_eq!(a.connected().unwrap().id, b.local_id());
        assert_eq!(b.connected().unwrap().id, a.local_id());

        a.disconnect();
        b.disconnect();
        a.shutdown();
        b.shutdown();
    }

    #[test]
    fn request_connect_rejects_unknown_peer() {
        let presence = Presence::start_on(config("Solo", "receiver"), 19127).unwrap();
        assert!(presence.request_connect("missing").is_err());
        presence.shutdown();
    }
}
