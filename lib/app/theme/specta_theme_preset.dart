import 'package:flutter/material.dart';

/// Theme preset defining the accent color palette for SPECTA.
enum SpectaThemePreset {
  /// Cyan / Teal (default SPECTA brand)
  cyanTeal(
    primaryAccent: Color(0xFF00D9FF),
    secondaryAccent: Color(0xFF00FFAA),
  ),

  /// Emerald Green
  emeraldGreen(
    primaryAccent: Color(0xFF00FF88),
    secondaryAccent: Color(0xFF00DD66),
  ),

  /// Ocean / Sapphire Blue
  oceanBlue(
    primaryAccent: Color(0xFF0099FF),
    secondaryAccent: Color(0xFF00AAFF),
  ),

  /// Midnight / Deep Violet
  deepViolet(
    primaryAccent: Color(0xFF8866FF),
    secondaryAccent: Color(0xFFAA88FF),
  ),

  /// Warm Amber / Gold
  warmAmber(
    primaryAccent: Color(0xFFFFAA33),
    secondaryAccent: Color(0xFFFFBB55),
  );

  const SpectaThemePreset({
    required this.primaryAccent,
    required this.secondaryAccent,
  });

  final Color primaryAccent;
  final Color secondaryAccent;

  String get label => switch (this) {
    SpectaThemePreset.cyanTeal => 'Cyan / Teal',
    SpectaThemePreset.emeraldGreen => 'Emerald Green',
    SpectaThemePreset.oceanBlue => 'Ocean / Sapphire Blue',
    SpectaThemePreset.deepViolet => 'Midnight / Deep Violet',
    SpectaThemePreset.warmAmber => 'Warm Amber / Gold',
  };
}
