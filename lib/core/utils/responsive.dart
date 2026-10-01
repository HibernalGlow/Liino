import 'package:flutter/widgets.dart';

/// How much horizontal room a desktop window offers.
enum WindowClass { compact, medium, expanded }

/// Window-shape checks shared by the orientation-aware layouts.
///
/// These key off the window size rather than `Orientation` or the platform: a
/// landscape phone is wide but *short*, and it's the height that breaks
/// layouts designed portrait-first.
class Responsive {
  /// Below this window height the landscape layouts switch to compact metrics.
  /// Phones in landscape (roughly 320-430dp tall) fall under it; tablets don't.
  static const double shortHeight = 480;

  static bool isLandscape(Size size) => size.width > size.height;

  static bool isShort(Size size) => size.height < shortHeight;

  /// From this width the sidebar is shown beside the content.
  static const double mediumWidth = 800;

  /// From this width there is room for extra panes.
  static const double expandedWidth = 1400;

  static WindowClass windowClass(double width) {
    if (width < mediumWidth) return WindowClass.compact;
    if (width < expandedWidth) return WindowClass.medium;
    return WindowClass.expanded;
  }
}
