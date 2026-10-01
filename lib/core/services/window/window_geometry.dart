import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:path_provider/path_provider.dart';

/// Where the desktop window was, and how big, when the app last ran.
class WindowGeometry {
  static const Size minimumSize = Size(720, 480);
  static const Size defaultSize = Size(1150, 700);

  /// A restored window must show at least this much of itself on the
  /// desktop, or its position is discarded.
  static const double _visibleMargin = 100;

  final double width;
  final double height;
  final double? x;
  final double? y;
  final bool maximized;

  const WindowGeometry({
    required this.width,
    required this.height,
    this.x,
    this.y,
    this.maximized = false,
  });

  Size get size => Size(width, height);

  WindowGeometry copyWith({bool? maximized}) => WindowGeometry(
    width: width,
    height: height,
    x: x,
    y: y,
    maximized: maximized ?? this.maximized,
  );

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'maximized': maximized,
  };

  /// Null for anything that isn't a usable geometry map.
  static WindowGeometry? fromJson(Object? json) {
    if (json is! Map) return null;
    final width = json['width'];
    final height = json['height'];
    if (width is! num || height is! num) return null;
    final x = json['x'];
    final y = json['y'];
    final hasPosition = x is num && y is num;
    return WindowGeometry(
      width: width.toDouble(),
      height: height.toDouble(),
      x: hasPosition ? x.toDouble() : null,
      y: hasPosition ? y.toDouble() : null,
      maximized: json['maximized'] == true,
    );
  }

  /// A geometry that is safe to open with, or null to use the default.
  /// [desktop] is the combined size of the connected displays (null when
  /// unknown): the size is cut down to it, and a position that would leave
  /// the window off-screen - saved on a monitor since unplugged - is dropped.
  static WindowGeometry? sanitize(WindowGeometry? raw, Size? desktop) {
    if (raw == null || !raw.width.isFinite || !raw.height.isFinite) {
      return null;
    }
    var width = math.max(raw.width, minimumSize.width);
    var height = math.max(raw.height, minimumSize.height);
    if (desktop != null) {
      width = math.min(width, math.max(desktop.width, minimumSize.width));
      height = math.min(height, math.max(desktop.height, minimumSize.height));
    }

    double? x = raw.x;
    double? y = raw.y;
    final positionUsable =
        x != null &&
        y != null &&
        x.isFinite &&
        y.isFinite &&
        x >= 0 &&
        y >= 0 &&
        (desktop == null ||
            (x <= desktop.width - _visibleMargin &&
                y <= desktop.height - _visibleMargin));
    if (!positionUsable) {
      x = null;
      y = null;
    }

    return WindowGeometry(
      width: width,
      height: height,
      x: x,
      y: y,
      maximized: raw.maximized,
    );
  }

  /// The connected displays laid side by side, in logical pixels. Null when
  /// the platform reports none.
  static Size? desktopSize() {
    final displays = PlatformDispatcher.instance.displays;
    if (displays.isEmpty) return null;
    double width = 0;
    double height = 0;
    for (final display in displays) {
      final ratio = display.devicePixelRatio <= 0
          ? 1.0
          : display.devicePixelRatio;
      width += display.size.width / ratio;
      height = math.max(height, display.size.height / ratio);
    }
    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }
}

/// Keeps [WindowGeometry] in a small file rather than the database, so it
/// can be read before the window is shown.
class WindowGeometryStore {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/window_state.json');
  }

  static Future<WindowGeometry?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return WindowGeometry.fromJson(jsonDecode(await file.readAsString()));
    } catch (e, s) {
      LoggerHelper.write('Failed to read window geometry', e, s);
      return null;
    }
  }

  static Future<void> save(WindowGeometry geometry) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(geometry.toJson()), flush: true);
    } catch (e, s) {
      LoggerHelper.write('Failed to save window geometry', e, s);
    }
  }
}
