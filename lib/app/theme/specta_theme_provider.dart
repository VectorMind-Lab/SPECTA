import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'specta_theme_preset.dart';

/// Manages the active theme preset for the application.
class SpectaThemePresetNotifier extends Notifier<SpectaThemePreset> {
  @override
  SpectaThemePreset build() => SpectaThemePreset.cyanTeal;

  void setPreset(SpectaThemePreset preset) {
    state = preset;
  }
}

/// Provides the active [SpectaThemePreset] for the application.
///
/// Default is [SpectaThemePreset.cyanTeal] (the SPECTA brand theme).
/// User can change this through settings to customize accent colors.
final NotifierProvider<SpectaThemePresetNotifier, SpectaThemePreset>
    spectaThemePresetProvider = NotifierProvider<SpectaThemePresetNotifier, SpectaThemePreset>(
  SpectaThemePresetNotifier.new,
);
