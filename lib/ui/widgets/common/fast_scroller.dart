import 'dart:async';

import 'package:flutter/material.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';

/// Where a list of [itemCount] equal rows is scrolled to, as the index of the
/// row at the top of the viewport. Pure, so the label logic is testable.
int fastScrollIndex({
  required double offset,
  required double maxScrollExtent,
  required double viewportDimension,
  required int itemCount,
}) {
  if (itemCount <= 0) return 0;
  final contentExtent = maxScrollExtent + viewportDimension;
  if (contentExtent <= 0) return 0;
  final index = (offset / contentExtent * itemCount).floor();
  return index.clamp(0, itemCount - 1);
}

/// The first letter of [text] as a fast-scroll section label: an upper-case
/// letter, or '#' for anything else (digits, symbols, empty).
String fastScrollLetter(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) return '#';
  final first = String.fromCharCode(trimmed.runes.first).toUpperCase();
  return RegExp(r'^[\p{L}]$', unicode: true).hasMatch(first) ? first : '#';
}

/// A draggable thumb on the trailing edge of a long scrolling list, driven by
/// the same [controller] as the list in [child]. It appears while the list
/// moves, can be dragged to jump anywhere, and shows [labelBuilder]'s text
/// (a letter, usually) beside it during the drag.
///
/// Only the thumb itself takes touches, so the rows under the rest of the
/// track stay tappable.
class FastScroller extends StatefulWidget {
  const FastScroller({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.child,
    this.labelBuilder,
    this.padding = EdgeInsets.zero,
    this.minScreens = 3,
  });

  final ScrollController controller;
  final int itemCount;
  final Widget child;

  /// Label for the row at [index]; null hides the bubble.
  final String? Function(int index)? labelBuilder;

  /// Insets of the thumb's track inside the list's box (e.g. the list's own
  /// bottom padding under a floating bar).
  final EdgeInsets padding;

  /// The thumb only exists once the list is at least this many screens long.
  final double minScreens;

  @override
  State<FastScroller> createState() => _FastScrollerState();
}

class _FastScrollerState extends State<FastScroller> {
  static const double _thumbHeight = 52;
  static const double _touchWidth = 36;
  static const Duration _hideDelay = Duration(milliseconds: 1400);

  final ValueNotifier<bool> _visible = ValueNotifier(false);
  final ValueNotifier<bool> _dragging = ValueNotifier(false);
  Timer? _hideTimer;
  String? _lastLabel;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _visible.dispose();
    _dragging.dispose();
    super.dispose();
  }

  ScrollPosition? get _position =>
      widget.controller.hasClients ? widget.controller.position : null;

  bool get _longEnough {
    final p = _position;
    if (p == null || !p.hasContentDimensions) return false;
    return p.maxScrollExtent > p.viewportDimension * widget.minScreens;
  }

  void _show() {
    if (!_longEnough) return;
    _visible.value = true;
    _hideTimer?.cancel();
    if (!_dragging.value) {
      _hideTimer = Timer(_hideDelay, () => _visible.value = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n is ScrollUpdateNotification) _show();
    return false;
  }

  double _fraction() {
    final p = _position;
    if (p == null || !p.hasContentDimensions || p.maxScrollExtent <= 0) {
      return 0;
    }
    return (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
  }

  String? _label() {
    final p = _position;
    final builder = widget.labelBuilder;
    if (p == null || builder == null || widget.itemCount == 0) return null;
    return builder(
      fastScrollIndex(
        offset: p.pixels.clamp(0.0, p.maxScrollExtent),
        maxScrollExtent: p.maxScrollExtent,
        viewportDimension: p.viewportDimension,
        itemCount: widget.itemCount,
      ),
    );
  }

  void _dragTo(double localDy, double trackExtent) {
    final p = _position;
    if (p == null || trackExtent <= 0) return;
    final fraction = ((localDy - _thumbHeight / 2) / trackExtent).clamp(
      0.0,
      1.0,
    );
    p.jumpTo(fraction * p.maxScrollExtent);
    final label = _label();
    if (label != null && label != _lastLabel) {
      _lastLabel = label;
      AppHaptics.tick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: Padding(
              padding: widget.padding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackExtent = constraints.maxHeight - _thumbHeight;
                  if (trackExtent <= 0) return const SizedBox.shrink();
                  return ListenableBuilder(
                    listenable: Listenable.merge([
                      widget.controller,
                      _visible,
                      _dragging,
                    ]),
                    builder: (context, _) {
                      final visible = _visible.value && _longEnough;
                      final dragging = _dragging.value;
                      final top = _fraction() * trackExtent;
                      final label = dragging ? _label() : null;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (label != null)
                            PositionedDirectional(
                              top: top + (_thumbHeight - 56) / 2,
                              end: _touchWidth + 12,
                              child: IgnorePointer(
                                child: _LabelBubble(
                                  label: label,
                                  color: accent,
                                ),
                              ),
                            ),
                          PositionedDirectional(
                            top: top,
                            end: 0,
                            width: _touchWidth,
                            height: _thumbHeight,
                            child: IgnorePointer(
                              ignoring: !visible,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: (d) {
                                  _hideTimer?.cancel();
                                  _lastLabel = _label();
                                  _dragging.value = true;
                                  _visible.value = true;
                                },
                                onVerticalDragUpdate: (d) {
                                  final box =
                                      context.findRenderObject() as RenderBox;
                                  _dragTo(
                                    box.globalToLocal(d.globalPosition).dy,
                                    trackExtent,
                                  );
                                },
                                onVerticalDragEnd: (_) {
                                  _dragging.value = false;
                                  _show();
                                },
                                onVerticalDragCancel: () {
                                  _dragging.value = false;
                                  _show();
                                },
                                child: AnimatedOpacity(
                                  opacity: visible ? 1 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      margin: const EdgeInsetsDirectional.only(
                                        end: 4,
                                      ),
                                      width: dragging ? 8 : 5,
                                      height: _thumbHeight,
                                      decoration: BoxDecoration(
                                        color: dragging
                                            ? accent
                                            : Colors.white.withValues(
                                                alpha: 0.45,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelBubble extends StatelessWidget {
  const _LabelBubble({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56, maxWidth: 220),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppFonts.jostStyle(
          fontSize: label.length > 2 ? 16 : 24,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
