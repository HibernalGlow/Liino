/// The whole-UI scale a desktop user can pick.
class UiScaleSteps {
  static const List<double> steps = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5];

  /// The nearest step. Rows saved before the setting existed read back as
  /// NaN - those, and anything else unusable, mean 100%.
  static double normalize(double value) {
    if (!value.isFinite || value <= 0) return 1.0;
    return steps.reduce(
      (a, b) => (value - a).abs() <= (value - b).abs() ? a : b,
    );
  }

  static double next(double value) {
    final i = steps.indexOf(normalize(value));
    return steps[(i + 1).clamp(0, steps.length - 1)];
  }

  static double previous(double value) {
    final i = steps.indexOf(normalize(value));
    return steps[(i - 1).clamp(0, steps.length - 1)];
  }
}
