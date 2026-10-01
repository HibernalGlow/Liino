import 'dart:math' as math;
import 'dart:typed_data';

/// Turns raw (unsmoothed) spectrum frames into levels that move with the
/// song's rhythm, for the artwork visualizer.
///
/// Three things make it rhythmic where a plain smoothed spectrum isn't:
/// * **Adaptive range per band.** Each band is measured against its own
///   recent floor and peak, so a kick reads as a jump even in a loud master
///   where the absolute level barely moves (and would sit pinned near max).
///   A share of the absolute level is kept so sustained sound still shows.
/// * **Short smoothing.** Bands rise almost at once and fall within ~0.15s,
///   so they drop between beats instead of hovering.
/// * **A beat envelope.** [beat] jumps on bass onsets (the bass rising
///   sharply) and decays over ~0.25s - what the glow and breathing effects
///   pulse with.
///
/// [presence] eases to 1 while playing and 0 on pause, so effects fade in
/// and out instead of popping. Kept free of Flutter so it can be unit tested.
class VisualizerLevels {
  VisualizerLevels([int bandCount = 16])
    : bands = Float32List(bandCount),
      _targets = Float32List(bandCount),
      _floor = Float32List(bandCount),
      _peak = Float32List(bandCount);

  /// Bands below this frequency count as bass.
  static const double bassMaxHz = 180;

  static const double _bandAttackTau = 0.025;
  static const double _bandReleaseTau = 0.15;
  static const double _bassAttackTau = 0.03;
  static const double _bassReleaseTau = 0.18;
  static const double _energyAttackTau = 0.05;
  static const double _energyReleaseTau = 0.3;
  static const double _beatDecayTau = 0.25;
  static const double _presenceTau = 0.5;
  static const double _revealTau = 0.35;

  // Adaptive range: the peak falls back and the floor creeps up over a few
  // seconds, so the range follows the song's current section.
  static const double _peakDecayTau = 4;
  static const double _floorRiseTau = 3;
  // Below this range a band is treated as steady (avoids blowing up noise).
  static const double _minRange = 0.12;
  // How much of a band's value is its absolute level vs. its movement.
  static const double _absoluteShare = 0.35;

  /// Levels, low to high, each in `[0, 1]`.
  final Float32List bands;
  final Float32List _targets;
  final Float32List _floor;
  final Float32List _peak;
  bool _primed = false;

  double _bassTarget = 0;
  double _energyTarget = 0;
  double _prevBassRaw = 0;
  double _onsetAverage = 0;

  double bass = 0;
  double energy = 0;

  /// Bass onset envelope, `[0, 1]`: jumps on a kick, decays in ~0.25s.
  double beat = 0;
  double presence = 0;

  /// Eases 0 -> 1 after [clear] (the effect coming back into view), so
  /// even the parts that stay while paused (the aura's resting glow) fade
  /// in rather than pop.
  double reveal = 0;

  /// Seconds of motion so far; slows to a stop with [presence].
  double time = 0;

  /// Feeds one raw spectrum frame (log-spaced bands from [lowHz] to
  /// [highHz], each in `[0, 1]`), [dt] seconds after the previous one.
  void addFrame(
    Float32List input,
    double lowHz,
    double highHz, {
    double dt = 0.05,
  }) {
    final int m = input.length;
    final int n = bands.length;
    if (m == 0 || n == 0) return;
    final double peakK = _k(dt, _peakDecayTau);
    final double floorK = _k(dt, _floorRiseTau);
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final double pos = n == 1 ? 0 : i * (m - 1) / (n - 1);
      final int lo = pos.floor();
      final int hi = math.min(lo + 1, m - 1);
      final double f = pos - lo;
      final double v = input[lo] * (1 - f) + input[hi] * f;
      if (!_primed) {
        _floor[i] = v;
        _peak[i] = v;
      }
      _peak[i] = v > _peak[i] ? v : _peak[i] + (v - _peak[i]) * peakK;
      _floor[i] = v < _floor[i] ? v : _floor[i] + (v - _floor[i]) * floorK;
      final double range = math.max(_peak[i] - _floor[i], _minRange);
      final double moving = ((v - _floor[i]) / range).clamp(0.0, 1.0);
      // Highs carry far less energy than lows; tilt the absolute part so
      // the whole spectrum shows, not just its left end.
      final double tilt = 1 + 0.8 * (n == 1 ? 0 : i / (n - 1));
      final double absolute = (v * tilt).clamp(0.0, 1.0);
      _targets[i] = _absoluteShare * absolute + (1 - _absoluteShare) * moving;
      sum += _targets[i];
    }
    _primed = true;
    _energyTarget = sum / n;

    // Bass: the levels of every band below bassMaxHz.
    double bassSum = 0;
    int bassCount = 0;
    if (lowHz > 0 && highHz > lowHz) {
      final double ratio = math.pow(highHz / lowHz, 1 / n).toDouble();
      double edge = lowHz;
      for (int i = 0; i < n; i++) {
        final double center = edge * math.sqrt(ratio);
        edge *= ratio;
        if (center >= bassMaxHz) break;
        bassSum += _targets[i];
        bassCount++;
      }
    }
    final double bassRaw = bassCount == 0 ? _targets[0] : bassSum / bassCount;
    _bassTarget = bassRaw;

    // Onset: the bass jumping up, compared with how jumpy it usually is,
    // so busy mixes don't fire on every frame and sparse ones still do.
    final double onset = math.max(0.0, bassRaw - _prevBassRaw);
    _prevBassRaw = bassRaw;
    final double strength =
        ((onset - _onsetAverage * 1.2) / math.max(_onsetAverage * 2, 0.08))
            .clamp(0.0, 1.0);
    _onsetAverage += (onset - _onsetAverage) * _k(dt, 1.5);
    if (strength > beat) beat = strength;
  }

  /// Advances the smoothing by [dt] seconds. While not [playing] no frames
  /// arrive, so every target falls to zero and it all settles.
  void step(double dt, {required bool playing}) {
    if (dt <= 0) return;
    if (!playing) {
      _targets.fillRange(0, _targets.length, 0);
      _bassTarget = 0;
      _energyTarget = 0;
    }
    for (int i = 0; i < bands.length; i++) {
      bands[i] = _ease(
        bands[i],
        _targets[i],
        dt,
        _bandAttackTau,
        _bandReleaseTau,
      );
    }
    bass = _ease(bass, _bassTarget, dt, _bassAttackTau, _bassReleaseTau);
    energy = _ease(
      energy,
      _energyTarget,
      dt,
      _energyAttackTau,
      _energyReleaseTau,
    );
    beat *= math.exp(-dt / _beatDecayTau);
    presence += ((playing ? 1.0 : 0.0) - presence) * _k(dt, _presenceTau);
    reveal += (1 - reveal) * _k(dt, _revealTau);
    time += dt * presence;
  }

  /// The spectrum at [u] in `[0, 1]` (0 = lowest band), interpolated.
  double bandAt(double u) {
    final int n = bands.length;
    if (n == 0) return 0;
    final double pos = u.clamp(0.0, 1.0) * (n - 1);
    final int lo = pos.floor();
    final int hi = math.min(lo + 1, n - 1);
    final double f = pos - lo;
    return bands[lo] * (1 - f) + bands[hi] * f;
  }

  /// True once paused, every level has faded out and [reveal] is done, so
  /// the caller can stop ticking.
  bool get settled {
    if (presence >= 0.01 || bass >= 0.005 || energy >= 0.005) return false;
    if (beat >= 0.005 || reveal < 0.99) return false;
    for (final double b in bands) {
      if (b >= 0.005) return false;
    }
    return true;
  }

  /// Drops everything to rest at once (e.g. when the effect was hidden).
  /// The adaptive range restarts from the next frame.
  void clear() {
    bands.fillRange(0, bands.length, 0);
    _targets.fillRange(0, _targets.length, 0);
    _primed = false;
    _bassTarget = 0;
    _energyTarget = 0;
    _prevBassRaw = 0;
    _onsetAverage = 0;
    bass = 0;
    energy = 0;
    beat = 0;
    presence = 0;
    reveal = 0;
  }

  static double _k(double dt, double tau) => 1 - math.exp(-dt / tau);

  static double _ease(
    double current,
    double target,
    double dt,
    double attack,
    double release,
  ) =>
      current +
      (target - current) * _k(dt, target > current ? attack : release);
}
