import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/window/window_geometry.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop only. Remembers the window's size, position and maximized state
/// as the user changes them, and keeps the minimum window size in step with
/// the UI scale so the logical layout never drops below
/// [WindowGeometry.minimumSize].
class WindowGeometryListener extends ConsumerStatefulWidget {
  final Widget child;

  const WindowGeometryListener({super.key, required this.child});

  @override
  ConsumerState<WindowGeometryListener> createState() =>
      _WindowGeometryListenerState();
}

class _WindowGeometryListenerState extends ConsumerState<WindowGeometryListener>
    with WindowListener {
  static const Duration _debounce = Duration(milliseconds: 400);

  Timer? _timer;
  WindowGeometry? _last;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WindowGeometryStore.load().then((stored) => _last ??= stored);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applyMinimumSize(ref.read(settingsProvider).desktopUiScale);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() => _schedule();

  @override
  void onWindowMove() => _schedule();

  @override
  void onWindowMaximize() => _schedule();

  @override
  void onWindowUnmaximize() => _schedule();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, _save);
  }

  Future<void> _save() async {
    try {
      if (await windowManager.isMaximized()) {
        // Keep the normal size and position, so un-maximizing after the
        // next launch returns to them.
        final base =
            _last ??
            WindowGeometry(
              width: WindowGeometry.defaultSize.width,
              height: WindowGeometry.defaultSize.height,
            );
        _last = base.copyWith(maximized: true);
      } else {
        final bounds = await windowManager.getBounds();
        _last = WindowGeometry(
          width: bounds.width,
          height: bounds.height,
          x: bounds.left,
          y: bounds.top,
        );
      }
      await WindowGeometryStore.save(_last!);
    } catch (e, s) {
      LoggerHelper.write('Failed to record window geometry', e, s);
    }
  }

  Future<void> _applyMinimumSize(double uiScale) async {
    final scale = UiScaleSteps.normalize(uiScale);
    final factor = scale > 1.0 ? scale : 1.0;
    try {
      await windowManager.setMinimumSize(WindowGeometry.minimumSize * factor);
    } catch (e, s) {
      LoggerHelper.write('Failed to set minimum window size', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<double>(
      settingsProvider.select((s) => s.desktopUiScale),
      (_, next) => _applyMinimumSize(next),
    );
    return widget.child;
  }
}
