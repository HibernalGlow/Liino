import 'package:flutter/material.dart';

/// Material 3 Expressive (MD3E) Design Tokens for liino.
///
/// Establishes hierarchical shape tokens, expressive typography scale,
/// tonal surface stepping, and spring motion curves.
class LiinoDesignTokens {
  const LiinoDesignTokens._();

  // Seed color: Deep Electric Teal / Cobalt acoustic accent
  static const Color seedColor = Color(0xFF006A6A);

  // Expressive Shape Hierarchy (never uniform rounded rectangles)
  static const double radiusExtraSmall = 6.0;
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 18.0;
  static const double radiusLarge = 26.0;
  static const double radiusExtraLarge = 34.0;
  static const double radiusFull = 9999.0;

  // Expressive Motion Curves
  static const Duration motionEmphasized = Duration(milliseconds: 380);
  static const Duration motionQuick = Duration(milliseconds: 180);
  static const Curve springCurve = Cubic(0.34, 1.35, 0.64, 1.0);

  static ThemeData buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _expressiveTextTheme(scheme),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  static TextTheme _expressiveTextTheme(ColorScheme scheme) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.12,
        color: scheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: scheme.primary,
      ),
    );
  }
}
