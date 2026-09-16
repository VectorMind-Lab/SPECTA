import 'package:flutter/material.dart';

import 'specta_colors.dart';
import 'specta_theme_preset.dart';

export 'specta_colors.dart';
export 'specta_theme_preset.dart';

/// Builds the comprehensive SPECTA [ThemeData] driven by the active [SpectaThemePreset].
abstract final class SpectaTheme {
  /// Builds a dark [ThemeData] configured with the given [preset].
  static ThemeData dark([
    SpectaThemePreset preset = SpectaThemePreset.cyanTeal,
  ]) {
    final Color primary = preset.primaryAccent;
    final Color secondary = preset.secondaryAccent;

    final ColorScheme scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: SpectaColors.background,
      primaryContainer: primary.withValues(alpha: 0.2),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: SpectaColors.background,
      surface: SpectaColors.surface,
      onSurface: SpectaColors.textPrimary,
      surfaceContainerHighest: SpectaColors.surfaceElevated,
      error: SpectaColors.failure,
      onError: Colors.white,
      outline: SpectaColors.outline,
      outlineVariant: SpectaColors.outlineBright,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SpectaColors.background,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: null, // Uses default clean modern sans-serif
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: SpectaColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: SpectaColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          color: SpectaColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        titleMedium: TextStyle(
          color: SpectaColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        titleSmall: TextStyle(
          color: SpectaColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: SpectaColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: SpectaColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: SpectaColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: SpectaColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        labelSmall: TextStyle(
          color: SpectaColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.8,
        ),
      ),
      cardTheme: const CardThemeData(
        color: SpectaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(SpectaMetrics.cardRadius),
          ),
          side: BorderSide(color: SpectaColors.outline),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: SpectaColors.outline,
        space: 1,
        thickness: 1,
      ),
      // Android TV / D-pad: high-contrast focus highlight visible from 10ft couch distance.
      focusColor: primary.withValues(alpha: 0.3),
      hoverColor: primary.withValues(alpha: 0.1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: SpectaColors.surfaceElevated,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return SpectaColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withValues(alpha: 0.35);
          }
          return SpectaColors.surfaceElevated;
        }),
        trackOutlineColor: WidgetStateProperty.all(SpectaColors.outline),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SpectaColors.surface,
        hintStyle: const TextStyle(
          color: SpectaColors.textMuted,
          fontSize: 14,
        ),
        prefixIconColor: SpectaColors.textMuted,
        suffixIconColor: SpectaColors.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          borderSide: const BorderSide(color: SpectaColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          borderSide: const BorderSide(color: SpectaColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: SpectaColors.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SpectaColors.textPrimary,
          side: const BorderSide(color: SpectaColors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
