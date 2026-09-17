import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_providers.dart';
import '../../core/database/settings_store.dart';
import '../../core/settings/specta_setting_keys.dart';
import 'specta_theme_preset.dart';

/// Manages the active theme preset for the application.
///
/// The brand default (cyan/teal) renders for the first frame; the persisted
/// choice, if any, is restored asynchronously from the settings store.
class SpectaThemePresetNotifier extends Notifier<SpectaThemePreset> {
  @override
  SpectaThemePreset build() {
    unawaited(_restore());
    return SpectaThemePreset.cyanTeal;
  }

  /// Applies the persisted value once the store answers.
  Future<void> _restore() async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final String? stored = await store.read(SpectaSettingKeys.themePreset);
    final SpectaThemePreset? preset = SpectaThemePreset.values
        .where((SpectaThemePreset p) => p.name == stored)
        .firstOrNull;
    if (preset != null && preset != state) {
      state = preset;
    }
  }

  /// Applies and persists a new theme preset.
  Future<void> setPreset(SpectaThemePreset preset) async {
    state = preset;
    await ref
        .read(settingsStoreProvider)
        .write(SpectaSettingKeys.themePreset, preset.name);
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
