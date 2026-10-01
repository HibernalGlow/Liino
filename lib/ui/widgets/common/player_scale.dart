import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The player scale [PlayerScaled] draws its subtree at. Heroes read it to
/// fly between a scaled and an unscaled end without a jump on landing.
class PlayerScale extends InheritedWidget {
  final double scale;

  const PlayerScale({super.key, required this.scale, required super.child});

  static double of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerScale>()?.scale ?? 1.0;

  @override
  bool updateShouldNotify(PlayerScale oldWidget) => oldWidget.scale != scale;
}

/// Lays [child] out at 1/[scale] of the space it's given and draws it
/// [scale] times larger, so it looks exactly as it does at the reference
/// density. Returns [child] untouched at scale 1.
class PlayerScaled extends StatelessWidget {
  final double scale;
  final Widget child;

  const PlayerScaled({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    return _UniformScale(
      scale: scale,
      child: PlayerScale(scale: scale, child: child),
    );
  }
}

class _UniformScale extends SingleChildRenderObjectWidget {
  final double scale;

  const _UniformScale({required this.scale, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUniformScale(scale);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderUniformScale renderObject,
  ) => renderObject.scale = scale;
}

class _RenderUniformScale extends RenderProxyBox {
  _RenderUniformScale(this._scale);

  double _scale;
  double get scale => _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsLayout();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1.0);

  BoxConstraints _inner(BoxConstraints c) => BoxConstraints(
    minWidth: c.minWidth / _scale,
    maxWidth: c.maxWidth / _scale,
    minHeight: c.minHeight / _scale,
    maxHeight: c.maxHeight / _scale,
  );

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_inner(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final RenderBox? child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      child.getDryLayout(_inner(constraints)) * _scale,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height / _scale) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height / _scale) ?? 0) * _scale;

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(width / _scale) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(width / _scale) ?? 0) * _scale;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}

/// A hero flight shuttle for heroes that may sit inside a [PlayerScaled]
/// subtree. The default shuttle lays the hero out at the flight's rect, so
/// a scaled end's contents (icons, text) would draw at their unscaled size
/// and snap by the scale on landing. This one lays the child out at the
/// rect divided by the current scale and draws it enlarged, the scale
/// moving from one end's to the other's.
Widget playerScaleAwareShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final double fromScale = PlayerScale.of(fromHeroContext);
  final double toScale = PlayerScale.of(toHeroContext);
  final Widget child = (toHeroContext.widget as Hero).child;
  // animation runs 0 -> 1 on push and 1 -> 0 on pop, so its value always
  // measures how far the pushed route is shown.
  final bool push = direction == HeroFlightDirection.push;
  final double hiddenScale = push ? fromScale : toScale;
  final double shownScale = push ? toScale : fromScale;
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final double s =
          hiddenScale + (shownScale - hiddenScale) * animation.value;
      return PlayerScaled(scale: s, child: child);
    },
  );
}
