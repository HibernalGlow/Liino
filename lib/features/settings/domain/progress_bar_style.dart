import 'dart:math' as math;

import 'package:looper_player/features/library/domain/models/models.dart';

/// How the thumb (the handle at the current position) is drawn.
enum ProgressThumbStyle { pill, round, none }

/// Every user-tunable look of the Android player's seek bar (the expanded
/// player and the lyrics screen). The defaults are the exact values the bar
/// used before it became customisable, so an untouched install looks the
/// same. The Linux/desktop bar keeps its own fixed values and ignores this.
class ProgressBarStyle {
  /// Squiggle on/off (stored inverted as `AppSettings.disableSquiggle`).
  final bool wave;
  final double thickness;

  /// Peak height of the wave, in dp above/below the track's center line.
  final double waveHeight;

  /// Distance between two wave peaks, in dp. Fixed in dp (not a count), so
  /// the wider landscape bar shows more waves.
  final double waveLength;

  /// Waves passing by per second.
  final double waveSpeed;
  final ProgressThumbStyle thumbStyle;
  final double thumbWidth;
  final double thumbHeight;

  /// Empty space between the thumb and each side of the track.
  final double thumbGap;
  final double inactiveOpacity;

  /// Show the wave right away instead of only past 12% of the song.
  final bool waveFromStart;

  /// Keep the wave (standing still) while paused instead of flattening it.
  final bool freezeWhenPaused;
  final bool growThumbOnDrag;

  const ProgressBarStyle({
    this.wave = true,
    this.thickness = defaultThickness,
    this.waveHeight = defaultWaveHeight,
    this.waveLength = defaultWaveLength,
    this.waveSpeed = defaultWaveSpeed,
    this.thumbStyle = ProgressThumbStyle.pill,
    this.thumbWidth = defaultThumbWidth,
    this.thumbHeight = defaultThumbHeight,
    this.thumbGap = defaultThumbGap,
    this.inactiveOpacity = defaultInactiveOpacity,
    this.waveFromStart = false,
    this.freezeWhenPaused = false,
    this.growThumbOnDrag = false,
  });

  static const double defaultThickness = 8;
  static const double defaultWaveHeight = 2;
  // The old fixed `squiggleWavelength: 6.0` fed sin(x / 6), i.e. one wave
  // every 2 * pi * 6 dp.
  static const double defaultWaveLength = 12 * math.pi;
  static const double defaultWaveSpeed = 0.05;
  static const double defaultThumbWidth = 6;
  static const double defaultThumbHeight = 16;
  // The old track shape hard-coded the gap as 0.75 * thumb width.
  static const double defaultThumbGap = 4.5;
  // Colors.white10.
  static const double defaultInactiveOpacity = 0x1A / 0xFF;

  static const ProgressBarStyle defaults = ProgressBarStyle();

  // Slider ranges shown in settings; stored values are clamped to them.
  static const double minThickness = 3, maxThickness = 14;
  static const double minWaveHeight = 0.5, maxWaveHeight = 6;
  static const double minWaveLength = 16, maxWaveLength = 80;
  static const double minWaveSpeed = 0, maxWaveSpeed = 0.3;
  static const double minThumbWidth = 2, maxThumbWidth = 10;
  static const double minThumbHeight = 8, maxThumbHeight = 28;
  static const double minThumbGap = 0, maxThumbGap = 10;
  static const double minInactiveOpacity = 0.05, maxInactiveOpacity = 0.4;

  /// The value passed to the squiggle track, which draws sin(x / it).
  double get squiggleWavelength => waveLength / (2 * math.pi);

  factory ProgressBarStyle.fromSettings(AppSettings s) {
    double pick(double? v, double def, double min, double max) =>
        v == null || v.isNaN ? def : v.clamp(min, max).toDouble();
    final int style = s.progressThumbStyle ?? 0;
    return ProgressBarStyle(
      wave: !s.disableSquiggle,
      thickness: pick(
        s.progressBarThickness,
        defaultThickness,
        minThickness,
        maxThickness,
      ),
      waveHeight: pick(
        s.progressWaveHeight,
        defaultWaveHeight,
        minWaveHeight,
        maxWaveHeight,
      ),
      waveLength: pick(
        s.progressWaveLength,
        defaultWaveLength,
        minWaveLength,
        maxWaveLength,
      ),
      waveSpeed: pick(
        s.progressWaveSpeed,
        defaultWaveSpeed,
        minWaveSpeed,
        maxWaveSpeed,
      ),
      thumbStyle: style >= 0 && style < ProgressThumbStyle.values.length
          ? ProgressThumbStyle.values[style]
          : ProgressThumbStyle.pill,
      thumbWidth: pick(
        s.progressThumbWidth,
        defaultThumbWidth,
        minThumbWidth,
        maxThumbWidth,
      ),
      thumbHeight: pick(
        s.progressThumbHeight,
        defaultThumbHeight,
        minThumbHeight,
        maxThumbHeight,
      ),
      thumbGap: pick(
        s.progressThumbGap,
        defaultThumbGap,
        minThumbGap,
        maxThumbGap,
      ),
      inactiveOpacity: pick(
        s.progressInactiveOpacity,
        defaultInactiveOpacity,
        minInactiveOpacity,
        maxInactiveOpacity,
      ),
      waveFromStart: s.progressWaveFromStart,
      freezeWhenPaused: s.progressFreezeWhenPaused,
      growThumbOnDrag: s.progressGrowThumbOnDrag,
    );
  }

  /// Writes this style into [s] (for SettingsNotifier's `_update`).
  AppSettings applyTo(AppSettings s) => s
    ..disableSquiggle = !wave
    ..progressBarThickness = thickness
    ..progressWaveHeight = waveHeight
    ..progressWaveLength = waveLength
    ..progressWaveSpeed = waveSpeed
    ..progressThumbStyle = thumbStyle.index
    ..progressThumbWidth = thumbWidth
    ..progressThumbHeight = thumbHeight
    ..progressThumbGap = thumbGap
    ..progressInactiveOpacity = inactiveOpacity
    ..progressWaveFromStart = waveFromStart
    ..progressFreezeWhenPaused = freezeWhenPaused
    ..progressGrowThumbOnDrag = growThumbOnDrag;

  ProgressBarStyle copyWith({
    bool? wave,
    double? thickness,
    double? waveHeight,
    double? waveLength,
    double? waveSpeed,
    ProgressThumbStyle? thumbStyle,
    double? thumbWidth,
    double? thumbHeight,
    double? thumbGap,
    double? inactiveOpacity,
    bool? waveFromStart,
    bool? freezeWhenPaused,
    bool? growThumbOnDrag,
  }) => ProgressBarStyle(
    wave: wave ?? this.wave,
    thickness: thickness ?? this.thickness,
    waveHeight: waveHeight ?? this.waveHeight,
    waveLength: waveLength ?? this.waveLength,
    waveSpeed: waveSpeed ?? this.waveSpeed,
    thumbStyle: thumbStyle ?? this.thumbStyle,
    thumbWidth: thumbWidth ?? this.thumbWidth,
    thumbHeight: thumbHeight ?? this.thumbHeight,
    thumbGap: thumbGap ?? this.thumbGap,
    inactiveOpacity: inactiveOpacity ?? this.inactiveOpacity,
    waveFromStart: waveFromStart ?? this.waveFromStart,
    freezeWhenPaused: freezeWhenPaused ?? this.freezeWhenPaused,
    growThumbOnDrag: growThumbOnDrag ?? this.growThumbOnDrag,
  );

  @override
  bool operator ==(Object other) =>
      other is ProgressBarStyle &&
      other.wave == wave &&
      other.thickness == thickness &&
      other.waveHeight == waveHeight &&
      other.waveLength == waveLength &&
      other.waveSpeed == waveSpeed &&
      other.thumbStyle == thumbStyle &&
      other.thumbWidth == thumbWidth &&
      other.thumbHeight == thumbHeight &&
      other.thumbGap == thumbGap &&
      other.inactiveOpacity == inactiveOpacity &&
      other.waveFromStart == waveFromStart &&
      other.freezeWhenPaused == freezeWhenPaused &&
      other.growThumbOnDrag == growThumbOnDrag;

  @override
  int get hashCode => Object.hash(
    wave,
    thickness,
    waveHeight,
    waveLength,
    waveSpeed,
    thumbStyle,
    thumbWidth,
    thumbHeight,
    thumbGap,
    inactiveOpacity,
    waveFromStart,
    freezeWhenPaused,
    growThumbOnDrag,
  );
}
