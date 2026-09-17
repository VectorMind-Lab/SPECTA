import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/database/settings_store.dart';
import '../../../core/settings/specta_setting_keys.dart';

/// Whether extensions and sources should auto-update.
///
/// The toggle is persisted immediately. The update machinery that honours it
/// arrives with extension catalogue integration (Phase 2H); this is the
/// settings foundation it will read.
class AutoUpdateExtensionsNotifier extends Notifier<bool> {
  static const bool defaultEnabled = true;

  @override
  bool build() {
    unawaited(_restore());
    return defaultEnabled;
  }

  /// Applies the persisted value once the store answers.
  Future<void> _restore() async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final String? stored = await store.read(
      SpectaSettingKeys.autoUpdateExtensions,
    );
    final bool? parsed = stored == null ? null : stored == 'true';
    if (parsed != null && parsed != state) {
      state = parsed;
    }
  }

  /// Applies and persists the new value.
  Future<void> setEnabled(bool value) async {
    state = value;
    await ref
        .read(settingsStoreProvider)
        .write(SpectaSettingKeys.autoUpdateExtensions, '$value');
  }
}

/// Current auto-update preference for extensions and sources.
final NotifierProvider<AutoUpdateExtensionsNotifier, bool>
autoUpdateExtensionsProvider =
    NotifierProvider<AutoUpdateExtensionsNotifier, bool>(
      AutoUpdateExtensionsNotifier.new,
    );
