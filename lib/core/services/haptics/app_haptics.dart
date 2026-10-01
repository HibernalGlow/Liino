import 'dart:io';

import 'package:flutter/services.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:vibration/vibration.dart';

/// The single entry point for every haptic in the app.
///
/// Widgets call a named event (`AppHaptics.light()`, `AppHaptics.success()`,
/// ...) instead of Flutter's [HapticFeedback], so one switch in settings
/// silences everything and each event plays the richest pattern the device
/// can do:
///
/// 1. `haptic_feedback` patterns (Android primitives on API 30+, amplitude
///    waveforms on API 26+, a plain buzz before that), tagged as touch
///    feedback so Android 13+ still honours the system "touch haptics" off
///    switch.
/// 2. `vibration` for the few custom multi-pulse patterns the plugin above
///    doesn't have, and only when the motor has amplitude control. Without it
///    those events fall back to the closest built-in pattern.
/// 3. Flutter's [HapticFeedback] where neither plugin works (desktop).
///
/// Capabilities are probed once, lazily; every call is fire-and-forget and
/// never throws.
class AppHaptics {
  AppHaptics._();

  /// Mirrors the "Haptic feedback" setting. Kept static so the ~200 call
  /// sites (many in plain widgets without a `ref`) need no provider access;
  /// the settings notifier writes it whenever settings load or change.
  static bool enabled = true;

  static final bool _mobile = Platform.isAndroid || Platform.isIOS;
  static Future<_Caps>? _caps;

  static Future<_Caps> _probe() async {
    if (!_mobile) return const _Caps(patterns: false, amplitude: false);
    bool patterns = false;
    bool amplitude = false;
    try {
      patterns = await Haptics.canVibrate();
    } catch (_) {}
    try {
      amplitude =
          await Vibration.hasVibrator() &&
          await Vibration.hasAmplitudeControl();
    } catch (_) {}
    return _Caps(patterns: patterns, amplitude: amplitude);
  }

  /// Warms the capability probe so the first tap isn't delayed by it.
  static void init() => _caps ??= _probe();

  /// Small, frequent touches: list taps, chips, menu items.
  static void light() => _play(HapticsType.light, HapticFeedback.lightImpact);

  /// Confirming a choice: toggles, primary buttons, sheet actions.
  static void medium() =>
      _play(HapticsType.medium, HapticFeedback.mediumImpact);

  /// Weighty, rare actions: resets, destructive confirmations.
  static void heavy() => _play(HapticsType.heavy, HapticFeedback.heavyImpact);

  /// A value stepping while dragging: sliders, pickers, segmented rows.
  static void selection() =>
      _play(HapticsType.selection, HapticFeedback.selectionClick);

  /// A crisp click when something locks into place (a slider snapping to
  /// zero or a detent).
  static void snap() => _play(HapticsType.rigid, HapticFeedback.mediumImpact);

  /// A gentle bump for soft UI (reveals, drag handles).
  static void soft() => _play(HapticsType.soft, HapticFeedback.lightImpact);

  /// A task finished well: saved, imported, restored.
  static void success() =>
      _play(HapticsType.success, HapticFeedback.mediumImpact);

  /// Something needs attention but nothing failed.
  static void warning() =>
      _play(HapticsType.warning, HapticFeedback.mediumImpact);

  /// Something failed.
  static void error() => _play(HapticsType.error, HapticFeedback.heavyImpact);

  /// Liking a song: a quick "lub-dub" double beat.
  static void heartbeat() => _custom(
    pattern: const [0, 22, 70, 36],
    intensities: const [0, 150, 0, 255],
    fallback: HapticsType.success,
    desktop: HapticFeedback.mediumImpact,
  );

  static void _play(HapticsType type, Future<void> Function() desktop) {
    if (!enabled) return;
    _run(() async {
      final caps = await (_caps ??= _probe());
      if (caps.patterns) {
        await Haptics.vibrate(type, usage: HapticsUsage.touch);
      } else {
        await desktop();
      }
    });
  }

  static void _custom({
    required List<int> pattern,
    required List<int> intensities,
    required HapticsType fallback,
    required Future<void> Function() desktop,
  }) {
    if (!enabled) return;
    _run(() async {
      final caps = await (_caps ??= _probe());
      if (caps.amplitude) {
        await Vibration.vibrate(pattern: pattern, intensities: intensities);
      } else if (caps.patterns) {
        await Haptics.vibrate(fallback, usage: HapticsUsage.touch);
      } else {
        await desktop();
      }
    });
  }

  static void _run(Future<void> Function() body) {
    body().catchError((_) {});
  }
}

class _Caps {
  const _Caps({required this.patterns, required this.amplitude});

  final bool patterns;
  final bool amplitude;
}
