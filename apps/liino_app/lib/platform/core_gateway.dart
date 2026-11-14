import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:liino_api/liino_api.dart';

import 'android_audio_bridge.dart';

/// Unified gateway between Flutter UI and Rust core:
/// - Mobile (Android/iOS): calls Rust core in-process via FRB.
/// - Desktop (macOS/Windows/Linux): prefers IPC to `liino-daemon` so the
///   audio service survives Flutter GUI exit; falls back to in-process FRB.
abstract class CoreGateway {
  Future<GatewayStatus> getStatus({required String preferredMode});
  Future<void> setRoleMode(String mode);
  Future<void> setTransport(String transport);
  Future<void> startLink();
  Future<void> stopLink();

  factory CoreGateway.platformDefault() {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return DesktopIpcCoreGateway();
    }
    return MobileFrbCoreGateway();
  }
}

class GatewayStatus {
  const GatewayStatus({
    required this.platformName,
    required this.roleMode,
    required this.resolvedRole,
    required this.activeTransport,
    required this.isRunning,
    required this.viaDaemon,
    required this.canCaptureAudio,
    required this.canPlayAudio,
    required this.canVirtualMicrophone,
    this.daemonPid,
    this.virtualMicDriver,
    this.rttMs = 0,
    this.jitterMs = 0.0,
    this.packetLossRate = 0.0,
    this.bitrate = 0,
    this.sampleRate = 48000,
    this.bufferDurationMs = 0,
    this.ringBufferSummary,
  });

  final String platformName;
  final String roleMode;
  final String resolvedRole;
  final String activeTransport;
  final bool isRunning;
  final bool viaDaemon;
  final bool canCaptureAudio;
  final bool canPlayAudio;
  final bool canVirtualMicrophone;
  final int? daemonPid;
  final String? virtualMicDriver;
  final int rttMs;
  final double jitterMs;
  final double packetLossRate;
  final int bitrate;
  final int sampleRate;
  final int bufferDurationMs;
  final String? ringBufferSummary;
}

class MobileFrbCoreGateway implements CoreGateway {
  String _mode = 'auto';
  String _transport = 'lan_wifi';
  bool _running = false;

  @override
  Future<GatewayStatus> getStatus({required String preferredMode}) async {
    _mode = preferredMode;
    final caps = detectCapabilities();
    final snap = previewSnapshot(mode: _mode);
    return GatewayStatus(
      platformName: caps.platformName,
      roleMode: snap.roleMode,
      resolvedRole: snap.resolvedRole,
      activeTransport: _transport,
      isRunning: _running,
      viaDaemon: false,
      canCaptureAudio: caps.canCaptureAudio,
      canPlayAudio: caps.canPlayAudio,
      canVirtualMicrophone: caps.canVirtualMicrophone,
      rttMs: snap.rttMs,
      jitterMs: snap.jitterMs,
      packetLossRate: snap.packetLoss,
      sampleRate: 48000,
      bufferDurationMs: _running ? 20 : 0,
      ringBufferSummary: '${snap.ringBufferLen}/${snap.ringBufferCapacity}',
    );
  }

  @override
  Future<void> setRoleMode(String mode) async {
    _mode = mode;
  }

  @override
  Future<void> setTransport(String transport) async {
    _transport = transport;
  }

  @override
  Future<void> startLink() async {
    if (AndroidAudioBridge.isSupported) {
      final bridge = AndroidAudioBridge();
      try {
        if (await bridge.ensureAudioPermissions()) {
          await bridge.startForegroundAudioService(roleMode: _mode);
          if (_transport == 'bluetooth_rfcomm') {
            await bridge.startBluetoothServer();
          }
        }
      } catch (_) {
        // The foreground host is best-effort; the link itself stays usable.
      }
    }
    _running = true;
  }

  @override
  Future<void> stopLink() async {
    if (AndroidAudioBridge.isSupported) {
      try {
        await AndroidAudioBridge().stopBluetoothServer();
        await AndroidAudioBridge().stopForegroundAudioService();
      } catch (_) {
        // Service may already be gone.
      }
    }
    _running = false;
  }
}

class DesktopIpcCoreGateway implements CoreGateway {
  final MobileFrbCoreGateway _frbFallback = MobileFrbCoreGateway();

  /// Set once a daemon answered over IPC; avoids re-probing on every request.
  bool _daemonReady = false;

  String _unixSocketPath() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && runtimeDir.isNotEmpty) {
      return '$runtimeDir/liino-daemon.sock';
    }
    return '/tmp/liino-daemon.sock';
  }

  /// Starts the daemon when no instance is listening, so the desktop build
  /// keeps audio alive after the GUI process exits.
  Future<bool> _ensureDaemon() async {
    if (_daemonReady) return true;
    if (!(Platform.isMacOS || Platform.isLinux)) return false;

    final sockPath = _unixSocketPath();
    if (await _pingDaemon(sockPath)) {
      _daemonReady = true;
      return true;
    }

    final binary = _locateDaemonBinary();
    if (binary == null) return false;
    try {
      await Process.start(
        binary,
        const <String>[],
        mode: ProcessStartMode.detached,
        workingDirectory: File(binary).parent.path,
      );
    } catch (_) {
      return false;
    }

    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (await _pingDaemon(sockPath)) {
        _daemonReady = true;
        return true;
      }
    }
    return false;
  }

  Future<bool> _pingDaemon(String sockPath) async {
    if (!File(sockPath).existsSync()) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 200),
      );
      socket.write('${jsonEncode({'type': 'ping'})}\n');
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 200));
      return (jsonDecode(line) as Map<String, dynamic>)['type'] == 'pong';
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Resolution order: explicit override, bundle resource, then the workspace
  /// `target/release` directory (walking up from the executable for dev runs).
  String? _locateDaemonBinary() {
    final override = Platform.environment['LIINO_DAEMON_BIN'];
    if (override != null &&
        override.isNotEmpty &&
        File(override).existsSync()) {
      return override;
    }

    final executable = File(Platform.resolvedExecutable);
    final bundled = File(
      '${executable.parent.parent.path}/Resources/liino-daemon',
    );
    if (bundled.existsSync()) return bundled.path;

    var dir = executable.parent;
    for (var depth = 0; depth < 8; depth++) {
      final candidate = File('${dir.path}/target/release/liino-daemon');
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _sendUnixIpc(
    Map<String, dynamic> payload,
  ) async {
    if (!(Platform.isMacOS || Platform.isLinux)) {
      return null;
    }
    if (!await _ensureDaemon()) return null;
    final sockPath = _unixSocketPath();
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('${jsonEncode(payload)}\n');
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 500));
      return jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<GatewayStatus> getStatus({required String preferredMode}) async {
    final resp = await _sendUnixIpc({'type': 'get_status'});
    if (resp != null && resp['type'] == 'status') {
      return GatewayStatus(
        platformName: resp['platform'] as String? ?? Platform.operatingSystem,
        roleMode: resp['role_mode'] as String? ?? preferredMode,
        resolvedRole: resp['resolved_role'] as String? ?? 'receiver',
        activeTransport: resp['active_transport'] as String? ?? 'lan_wifi',
        isRunning: resp['is_running'] as bool? ?? false,
        viaDaemon: true,
        daemonPid: resp['pid'] as int?,
        canCaptureAudio: true,
        canPlayAudio: true,
        canVirtualMicrophone: resp['virtual_mic_installed'] as bool? ?? false,
        virtualMicDriver: resp['virtual_mic_driver'] as String?,
        rttMs: (resp['rtt_ms'] as num?)?.toInt() ?? 0,
        jitterMs: (resp['jitter_ms'] as num?)?.toDouble() ?? 0.0,
        packetLossRate: (resp['packet_loss_rate'] as num?)?.toDouble() ?? 0.0,
        bitrate: (resp['bitrate'] as num?)?.toInt() ?? 0,
        sampleRate: (resp['sample_rate'] as num?)?.toInt() ?? 48000,
        bufferDurationMs: (resp['buffer_duration_ms'] as num?)?.toInt() ?? 0,
      );
    }
    return _frbFallback.getStatus(preferredMode: preferredMode);
  }

  @override
  Future<void> setRoleMode(String mode) async {
    final resp = await _sendUnixIpc({'type': 'set_role_mode', 'mode': mode});
    if (resp == null) {
      await _frbFallback.setRoleMode(mode);
    }
  }

  @override
  Future<void> setTransport(String transport) async {
    final resp = await _sendUnixIpc({
      'type': 'set_transport',
      'transport': transport,
    });
    if (resp == null) {
      await _frbFallback.setTransport(transport);
    }
  }

  @override
  Future<void> startLink() async {
    final resp = await _sendUnixIpc({'type': 'start_link'});
    if (resp == null) {
      await _frbFallback.startLink();
    }
  }

  @override
  Future<void> stopLink() async {
    final resp = await _sendUnixIpc({'type': 'stop_link'});
    if (resp == null) {
      await _frbFallback.stopLink();
    }
  }
}
