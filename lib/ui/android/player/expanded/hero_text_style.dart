part of 'android_expanded_player.dart';

TextStyle _getHeroStyle(Hero hero, TextStyle fallback) {
  final child = hero.child;
  if (child is ScrollingText) {
    return child.style ?? fallback;
  }
  if (child is Text) {
    return child.style ?? fallback;
  }
  return fallback;
}

/// [style] as drawn inside [heroContext]'s PlayerScaled subtree, so a text
/// shuttle lands at the size the scaled player really shows.
TextStyle _scaledHeroStyle(TextStyle style, BuildContext heroContext) {
  final double k = PlayerScale.of(heroContext);
  if (k == 1.0) return style;
  return style.copyWith(
    fontSize: (style.fontSize ?? 14) * k,
    letterSpacing: style.letterSpacing == null
        ? null
        : style.letterSpacing! * k,
  );
}
