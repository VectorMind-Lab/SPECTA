import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_providers.dart';
import '../../core/settings/specta_setting_keys.dart';
import '../../core/database/settings_store.dart';
import '../../core/database/specta_database.dart';
import '../../core/storage/specta_storage.dart';

/// A single row of real, read-back state on the Phase 0 foundation screen.
class FoundationStatusItem {
  const FoundationStatusItem(this.label, this.value);

  final String label;
  final String value;
}

/// Reads live values out of the foundation layers.
///
/// Every row is produced by the layer it describes (SQLite, the settings
/// store, the storage layout) — nothing is hard-coded, so the screen cannot
/// claim working state that does not exist.
final FutureProvider<List<FoundationStatusItem>> foundationStatusProvider =
    FutureProvider<List<FoundationStatusItem>>((Ref ref) async {
      final SpectaDatabase database = ref.watch(spectaDatabaseProvider);
      final SettingsStore store = ref.watch(settingsStoreProvider);

      // Round-trip proof: write through the store, read it back.
      final DateTime now = DateTime.now().toUtc();
      await store.write(SpectaSettingKeys.lastOpenedAt, now.toIso8601String());
      final String? echo = await store.read(SpectaSettingKeys.lastOpenedAt);
      final Map<String, String> settings = await store.readAll();

      final Directory mediaDirectory = await const SpectaStorage()
          .mediaDirectory();

      return <FoundationStatusItem>[
        FoundationStatusItem('SQLite schema', 'v${database.schemaVersion}'),
        FoundationStatusItem(
          'Settings round trip',
          echo == null ? 'FAILED' : 'OK',
        ),
        FoundationStatusItem('Persisted settings', '${settings.length} key(s)'),
        FoundationStatusItem('Media directory', mediaDirectory.path),
      ];
    });
