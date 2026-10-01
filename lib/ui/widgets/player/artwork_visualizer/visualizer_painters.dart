part of 'artwork_visualizer.dart';

/// The effect's two colors: [a] leads (the artwork's/theme's primary), [b]
/// accompanies (its second color).
class _ScenePalette {
  final Color a;
  final Color b;

  const _ScenePalette(this.a, this.b);

  static _ScenePalette lerp(_ScenePalette x, _ScenePalette y, double t) =>
      _ScenePalette(Color.lerp(x.a, y.a, t)!, Color.lerp(x.b, y.b, t)!);

  @override
  bool operator ==(Object other) =>
      other is _ScenePalette && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}

/// Mutable state shared between the ticker and the painters.
class _VisualizerScene {
  final VisualizerLevels levels = VisualizerLevels();
  late _ScenePalette palette;
  ArtworkVisualizerType type = ArtworkVisualizerType.none;
  double gain = 1;
  double radius = 12;
  bool light = false;

  /// Extra cover scale for the breathing effect: a ~3% push on each kick
  /// over a slight lift with the bass.
  double get breathingScale =>
      gain * (0.028 * levels.beat + 0.008 * levels.bass.clamp(0.0, 1.0));

  // Spectrum ring bar anchors (x, y, normal x, normal y per bar), cached
  // per size.
  static const int ringBars = 72;
  Size? _ringSize;
  double _ringRadius = -1;
  Float32List _ring = Float32List(0);

  Float32List ringAnchors(Size size) {
    if (size == _ringSize && radius == _ringRadius) return _ring;
    _ringSize = size;
    _ringRadius = radius;
    _ring = _perimeterAnchors(Offset.zero & size, radius, ringBars);
    return _ring;
  }

  /// [count] evenly spaced points around the rounded rect's outline, going
  /// clockwise from the top center, each with its outward normal.
  static Float32List _perimeterAnchors(Rect rect, double radius, int count) {
    final double r = math.min(radius, rect.shortestSide / 2);
    final double w = rect.width - 2 * r;
    final double h = rect.height - 2 * r;
    final double arc = math.pi / 2 * r;
    final double total = 2 * w + 2 * h + 4 * arc;
    final out = Float32List(count * 4);
    for (int i = 0; i < count; i++) {
      double s = total * i / count;
      double x, y, nx, ny;
      // Walk: top (right half), TR corner, right, BR, bottom, BL, left, TL,
      // top (left half).
      if (s < w / 2) {
        x = rect.center.dx + s;
        y = rect.top;
        nx = 0;
        ny = -1;
      } else if ((s -= w / 2) < arc) {
        final double a = -math.pi / 2 + s / r;
        (x, y, nx, ny) = _corner(rect.right - r, rect.top + r, r, a);
      } else if ((s -= arc) < h) {
        x = rect.right;
        y = rect.top + r + s;
        nx = 1;
        ny = 0;
      } else if ((s -= h) < arc) {
        (x, y, nx, ny) = _corner(rect.right - r, rect.bottom - r, r, s / r);
      } else if ((s -= arc) < w) {
        x = rect.right - r - s;
        y = rect.bottom;
        nx = 0;
        ny = 1;
      } else if ((s -= w) < arc) {
        final double a = math.pi / 2 + s / r;
        (x, y, nx, ny) = _corner(rect.left + r, rect.bottom - r, r, a);
      } else if ((s -= arc) < h) {
        x = rect.left;
        y = rect.bottom - r - s;
        nx = -1;
        ny = 0;
      } else if ((s -= h) < arc) {
        final double a = math.pi + s / r;
        (x, y, nx, ny) = _corner(rect.left + r, rect.top + r, r, a);
      } else {
        s -= arc;
        x = rect.left + r + s;
        y = rect.top;
        nx = 0;
        ny = -1;
      }
      out[i * 4] = x;
      out[i * 4 + 1] = y;
      out[i * 4 + 2] = nx;
      out[i * 4 + 3] = ny;
    }
    return out;
  }

  static (double, double, double, double) _corner(
    double cx,
    double cy,
    double r,
    double angle,
  ) {
    final double c = math.cos(angle), s = math.sin(angle);
    return (cx + c * r, cy + s * r, c, s);
  }
}

/// Paints one layer of the effect: behind the cover ([front] false: aura,
/// ring) or over it, clipped to its rounded corners ([front] true: wave,
/// bars). All sizes are relative to the cover, so the same effect fits the
/// big portrait cover, the landscape one and the settings preview.
class _VisualizerPainter extends CustomPainter {
  final _VisualizerScene scene;
  final ArtworkVisualizerType type;
  final bool front;

  _VisualizerPainter({
    required this.scene,
    required this.type,
    required this.front,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Paint _paint = Paint();
  final Path _path = Path();
  final Float32List _wave = Float32List(_waveSamples + 1);

  static const int _waveSamples = 20;
  static const int _barCount = 28;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (type) {
      case ArtworkVisualizerType.aura when !front:
        _paintAura(canvas, size);
      case ArtworkVisualizerType.ring when !front:
        _paintRing(canvas, size);
      case ArtworkVisualizerType.wave when front:
        _paintWave(canvas, size);
      case ArtworkVisualizerType.bars when front:
        _paintBars(canvas, size);
      default:
    }
  }

  /// Two soft halos in the cover's shape: the lead color pulsing with the
  /// kick, the second one glowing with the whole mix from the opposite
  /// side, both slowly orbiting. A faint halo stays while paused.
  void _paintAura(Canvas canvas, Size size) {
    final levels = scene.levels;
    final palette = scene.palette;
    final double side = size.shortestSide;
    // The lead glow punches out on each kick and eases back before the
    // next; the bass underneath keeps it from dropping flat between them.
    final double beat = (levels.beat * scene.gain).clamp(0.0, 1.2);
    final double bass = (levels.bass * scene.gain).clamp(0.0, 1.2);
    final double mix = (levels.energy * scene.gain).clamp(0.0, 1.2);
    final RRect cover = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(scene.radius),
    );
    final double angle = levels.time * 0.45;
    final Offset orbit =
        Offset(math.cos(angle), math.sin(angle)) * (side * 0.035);
    // Light themes need a touch more to show against a pale background.
    final double base = (scene.light ? 0.42 : 0.34) * levels.reveal;

    _paint
      ..style = PaintingStyle.fill
      ..color = palette.a.withValues(
        alpha: (base + 0.3 * beat + 0.12 * bass).clamp(0.0, 0.9),
      )
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        side * (0.07 + 0.025 * beat + 0.01 * bass),
      );
    canvas.drawRRect(
      cover.inflate(side * (0.01 + 0.04 * beat + 0.012 * bass)).shift(orbit),
      _paint,
    );

    _paint
      ..color = palette.b.withValues(
        alpha: (base * 0.65 + 0.32 * mix).clamp(0.0, 0.75),
      )
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        side * (0.06 + 0.03 * mix),
      );
    canvas.drawRRect(cover.inflate(side * 0.03 * mix).shift(-orbit), _paint);
  }

  /// Thin bars standing out of the cover's edge all the way round. The
  /// spectrum is mirrored left/right with the bass at the bottom and the
  /// highs at the top, and the whole pattern slowly turns.
  void _paintRing(Canvas canvas, Size size) {
    final levels = scene.levels;
    final double fade = levels.presence;
    if (fade < 0.01) return;
    final palette = scene.palette;
    final Float32List anchors = scene.ringAnchors(size);
    final int count = anchors.length ~/ 4;
    final double side = size.shortestSide;
    final double gap = side * 0.014;
    final double minLength = side * 0.006;
    final double maxLength = side * 0.065;
    final double turn = levels.time * 0.015;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (side * 0.0095).clamp(2.0, 4.0)
      ..maskFilter = null
      ..shader = null;
    for (int i = 0; i < count; i++) {
      final double u = (i / count + turn) % 1.0;
      // 0 at the bottom center (bass), 1 at the top center (highs).
      final double pos = 1 - (2 * u - 1).abs();
      final double at = 1 - pos;
      // Bass-side bars also jump with the kick.
      final double level =
          (levels.bandAt(at) * scene.gain + 0.25 * levels.beat * (1 - at))
              .clamp(0.0, 1.0);
      final double length = minLength + (maxLength - minLength) * level;
      final double x = anchors[i * 4], y = anchors[i * 4 + 1];
      final double nx = anchors[i * 4 + 2], ny = anchors[i * 4 + 3];
      final Offset start = Offset(x + nx * gap, y + ny * gap);
      _paint.color = Color.lerp(
        palette.a,
        palette.b,
        at,
      )!.withValues(alpha: (0.45 + 0.55 * level) * fade);
      canvas.drawLine(
        start,
        Offset(start.dx + nx * length, start.dy + ny * length),
        _paint,
      );
    }
  }

  /// Two layered, gently flowing waves rising from the bottom edge, shaped
  /// by the spectrum mirrored around the center (bass in the middle).
  void _paintWave(Canvas canvas, Size size) {
    final levels = scene.levels;
    final double fade = levels.presence;
    if (fade < 0.01) return;
    final palette = scene.palette;
    final double w = size.width, h = size.height;

    _paint
      ..style = PaintingStyle.fill
      ..maskFilter = null;
    for (int layer = 0; layer < 2; layer++) {
      final bool back = layer == 0;
      for (int j = 0; j <= _waveSamples; j++) {
        final double t = j / _waveSamples;
        final double level = (levels.bandAt((2 * t - 1).abs()) * scene.gain)
            .clamp(0.0, 1.1);
        final double amp =
            h * (0.05 + 0.2 * level) * fade * (back ? 1.1 : 0.85);
        final double flow =
            math.sin(
              t * 2 * math.pi * 1.3 +
                  levels.time * (back ? 1.0 : 1.5) +
                  (back ? 1.8 : 0),
            ) *
            h *
            0.012 *
            fade;
        _wave[j] = h - amp + flow;
      }
      _smoothWavePath(w, h, close: true);
      final Color color = back ? palette.b : palette.a;
      _paint.shader = ui.Gradient.linear(Offset(0, h * 0.68), Offset(0, h), [
        color.withValues(alpha: (back ? 0.4 : 0.6) * fade),
        color.withValues(alpha: (back ? 0.6 : 0.85) * fade),
      ]);
      canvas.drawPath(_path, _paint);
    }
    _paint.shader = null;

    // A fine highlight along the front wave's crest.
    _smoothWavePath(w, h, close: false);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.28 * fade);
    canvas.drawPath(_path, _paint);
  }

  /// Rebuilds [_path] through the [_wave] samples with quadratic curves
  /// between midpoints, so the crest has no corners.
  void _smoothWavePath(double w, double h, {required bool close}) {
    _path.reset();
    double px = 0, py = _wave[0];
    if (close) {
      _path
        ..moveTo(0, h)
        ..lineTo(px, py);
    } else {
      _path.moveTo(px, py);
    }
    for (int j = 1; j <= _waveSamples; j++) {
      final double x = w * j / _waveSamples;
      final double y = _wave[j];
      _path.quadraticBezierTo(px, py, (px + x) / 2, (py + y) / 2);
      px = x;
      py = y;
    }
    _path.lineTo(px, py);
    if (close) {
      _path
        ..lineTo(w, h)
        ..close();
    }
  }

  /// A small mirrored equalizer along the bottom edge over a soft shade, so
  /// the bars read on any artwork.
  void _paintBars(Canvas canvas, Size size) {
    final levels = scene.levels;
    final double fade = levels.presence;
    if (fade < 0.01) return;
    final palette = scene.palette;
    final double w = size.width, h = size.height;

    _paint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..shader = ui.Gradient.linear(Offset(0, h * 0.55), Offset(0, h), [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.4 * fade),
      ]);
    canvas.drawRect(Rect.fromLTRB(0, h * 0.55, w, h), _paint);
    _paint.shader = null;

    final double margin = w * 0.06;
    final double slot = (w - 2 * margin) / _barCount;
    final double barWidth = slot * 0.56;
    final double floor = h - margin * 0.8;
    for (int j = 0; j < _barCount; j++) {
      final double at = ((j + 0.5) / _barCount * 2 - 1).abs();
      final double level = (levels.bandAt(at) * scene.gain).clamp(0.0, 1.1);
      final double barHeight = h * (0.025 + 0.25 * level) * fade;
      final double x = margin + slot * j + (slot - barWidth) / 2;
      _paint.color = Color.lerp(
        palette.a,
        palette.b,
        at,
      )!.withValues(alpha: 0.92 * fade);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, floor - barHeight, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.front != front ||
      oldDelegate.scene != scene;
}
