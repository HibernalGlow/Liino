import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Phase 3 Android platform adapter bridge.
///
/// Keeps Android ForegroundService, RECORD_AUDIO / BLUETOOTH_CONNECT
/// permission checks, and AudioRecord / RFCOMM lifecycle isolated from
/// shared Rust core logic.
class AndroidAudioBridge {
  static const MethodChannel _channel = MethodChannel('dev.liino.app/android_audio');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> ensureAudioPermissions() async {
    if (!isSupported) return true;
    final granted = await _channel.invokeMethod<bool>('ensureAudioPermissions');
    return granted ?? false;
  }

  Future<void> startForegroundAudioService({required String roleMode}) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('startForegroundAudioService', {
      'roleMode': roleMode,
    });
  }

  Future<void> stopForegroundAudioService() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('stopForegroundAudioService');
  }
}
