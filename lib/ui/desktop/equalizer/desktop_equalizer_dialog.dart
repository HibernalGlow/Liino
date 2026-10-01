import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:looper_player/ui/android/player/equalizer/android_equalizer_screen.dart';

const double _margin = 64;
const double _maxWidth = 1100;
const double _twoColumnWidth = 820;

/// The equalizer dialog's size for a window: as wide as allowed, and always
/// wider than it is tall (at most 70% as tall as wide).
Size equalizerDialogSize(Size window) {
  final width = math.max(math.min(_maxWidth, window.width - _margin), 120.0);
  final height = math.max(
    math.min(window.height - _margin, width * 0.7),
    math.min(80.0, width * 0.7),
  );
  return Size(width, height);
}

bool equalizerUsesTwoColumns(double dialogWidth) =>
    dialogWidth >= _twoColumnWidth;

/// Desktop: the equalizer as a centred landscape dialog instead of a
/// phone-shaped sheet.
Future<void> showDesktopEqualizer(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final size = equalizerDialogSize(MediaQuery.sizeOf(context));
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox.fromSize(
            size: size,
            child: AndroidEqualizerScreen(
              twoColumn: equalizerUsesTwoColumns(size.width),
            ),
          ),
        ),
      );
    },
  );
}
