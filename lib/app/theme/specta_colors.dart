import 'package:flutter/material.dart';

/// SPECTA color tokens and surface styling constants.
///
/// SPECTA uses a deep, dark cinematic aesthetic with futuristic glow surfaces
/// and customizable accent colors defined by [SpectaThemePreset].
abstract final class SpectaColors {
  // --- Deep Canvas & Surfaces ---
  static const Color background = Color(0xFF080B11);
  static const Color backgroundSecondary = Color(0xFF0D111A);
  static const Color surface = Color(0xFF131826);
  static const Color surfaceElevated = Color(0xFF1B2236);
  static const Color surfaceGlass = Color(0xCC131826);
  static const Color surfaceHighlight = Color(0xFF232C46);

  // --- Borders & Outlines ---
  static const Color outline = Color(0xFF222B3D);
  static const Color outlineBright = Color(0xFF33415C);
  static const Color outlineGlass = Color(0x335670A3);

  // --- Typography & Content ---
  static const Color textPrimary = Color(0xFFF4F7FC);
  static const Color textSecondary = Color(0xFF9AA7C0);
  static const Color textMuted = Color(0xFF5F6E8A);

  // --- Semantic States ---
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB300);
  static const Color failure = Color(0xFFFF5252);
  static const Color info = Color(0xFF00E5FF);

  // --- Default Accent (Cyan / Teal) ---
  static const Color defaultAccent = Color(0xFF00E5FF);
  static const Color defaultAccentSecondary = Color(0xFF0099FF);
}

/// Spacing, corner radii, and interaction metrics.
abstract final class SpectaMetrics {
  static const double gutter = 16;
  static const double gutterLarge = 24;
  static const double cardRadius = 12;
  static const double buttonRadius = 24;
  static const double pillRadius = 999;
  static const double minTouchTarget = 48;

  /// Minimum focus target for D-pad driven Android TV navigation.
  static const double minFocusTarget = 56;
}
