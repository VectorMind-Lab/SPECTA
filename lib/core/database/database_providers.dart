import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'daos/metadata_cache_dao.dart';
import 'daos/settings_dao.dart';
import 'settings_store.dart';
import 'specta_database.dart';

/// The single database handle for the process.
///
/// Tests override this with an in-memory database (or override
/// [settingsStoreProvider] directly).
final Provider<SpectaDatabase> spectaDatabaseProvider =
    Provider<SpectaDatabase>((Ref ref) {
      final SpectaDatabase database = SpectaDatabase();
      ref.onDispose(() {
        unawaited(database.close());
      });
      return database;
    });

/// Settings persistence, exposed as the [SettingsStore] contract.
final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>((
  Ref ref,
) {
  return SettingsDao(ref.watch(spectaDatabaseProvider));
});

/// Persistent catalogue metadata cache shared by TMDB and TVMaze.
final Provider<MetadataCacheDao> metadataCacheDaoProvider =
    Provider<MetadataCacheDao>((Ref ref) {
      return MetadataCacheDao(ref.watch(spectaDatabaseProvider));
    });
