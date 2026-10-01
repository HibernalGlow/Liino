import 'dart:io';

import 'package:flutter/services.dart';

/// Hides and shows the Android navigation bar (3-button bar or gesture
/// pill) without leaving edge-to-edge, via MainActivity - Flutter's
/// SystemChrome modes switch edge-to-edge off and use the legacy flags,
/// which newer target SDKs ignore.
/// No-op on other platforms.
class SystemNavigationBar {
  SystemNavigationBar._();

  static const _channel = MethodChannel('com.looper.player/system_ui');

  static Future<void> setHidden(bool hidden) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setNavigationBarHidden', {'hidden': hidden});
    } catch (_) {}
  }
}
