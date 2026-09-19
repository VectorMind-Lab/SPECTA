@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/daos/settings_dao.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_dao.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:sqlite3/sqlite3.dart';

// sqlite3 3.x ships its SQLite build as a Dart native code asset, which the
// Dart VM resolves automatically (including under `flutter test`); Android
// builds get the same treatment through drift_flutter. No host-OS loader
// override is needed.

void main() {
  group('SpectaDatabase — settings and schema version', () {
    late SpectaDatabase database;
    late SettingsDao dao;

    setUp(() {
      database = SpectaDatabase(NativeDatabase.memory());
      dao = SettingsDao(database);
    });

    tearDown(() => database.close());

    test('opens the schema at the version this build declares', () {
      expect(database.schemaVersion, 3);
    });

    test('writes and reads a setting back', () async {
      await dao.write('downloads.concurrency', '3');

      expect(await dao.read('downloads.concurrency'), '3');
    });

    test('replacing a value keeps a single row per key', () async {
      await dao.write('downloads.concurrency', '3');
      await dao.write('downloads.concurrency', '5');

      expect(
        await dao.readAll(),
        <String, String>{'downloads.concurrency': '5'},
      );
    });

    test('missing settings read as null and can be removed', () async {
      expect(await dao.read('absent.key'), isNull);

      await dao.write('absent.key', 'value');
      await dao.remove('absent.key');

      expect(await dao.read('absent.key'), isNull);
    });
  });

  test('upgrades an installed v2 database to v3 in place, preserving data',
      () async {
    // Build exactly the schema a pre-2F build left on disk: the v1 settings
    // table plus the v2 extension tables, with user_version = 2. DateTime
    // columns hold integer timestamps, which is how Drift stores them.
    final Database raw = sqlite3.openInMemory();
    raw
      ..execute('''
        CREATE TABLE settings_entries (
          key TEXT NOT NULL,
          value TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (key)
        )
      ''')
      ..execute('''
        CREATE TABLE extensions (
          id TEXT NOT NULL,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          author TEXT NOT NULL,
          api_version INTEGER NOT NULL,
          content_type TEXT NOT NULL,
          signature TEXT,
          trust_level TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          file_path TEXT NOT NULL,
          installed_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          previous_version_path TEXT,
          previous_version TEXT,
          PRIMARY KEY (id)
        )
      ''')
      ..execute('''
        CREATE TABLE extension_versions (
          id TEXT NOT NULL,
          extension_id TEXT NOT NULL,
          version TEXT NOT NULL,
          file_path TEXT NOT NULL,
          is_current INTEGER NOT NULL DEFAULT 0,
          is_rollback_point INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (id),
          FOREIGN KEY (extension_id) REFERENCES extensions (id)
        )
      ''')
      ..execute('''
        CREATE TABLE extension_failure_logs (
          id TEXT NOT NULL,
          extension_id TEXT NOT NULL,
          failure_type TEXT NOT NULL,
          operation TEXT NOT NULL,
          message TEXT NOT NULL,
          detail TEXT,
          timestamp INTEGER NOT NULL,
          retryable INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (id),
          FOREIGN KEY (extension_id) REFERENCES extensions (id)
        )
      ''')
      ..execute(
        'INSERT INTO settings_entries (key, value, updated_at) VALUES (?, ?, ?)',
        <Object?>['theme.preset', 'cyan', 1700000000],
      )
      ..execute('PRAGMA user_version = 2');

    final SpectaDatabase upgraded = SpectaDatabase(NativeDatabase.opened(raw));
    addTearDown(upgraded.close);

    // The upgrade runs on first use, and the pre-existing row survives.
    expect(await SettingsDao(upgraded).read('theme.preset'), 'cyan');
    expect(upgraded.schemaVersion, 3);

    // The new v3 table exists and is writable/readable.
    final LibraryDao library = LibraryDao(upgraded);
    await library.upsert(
      WatchProgress(
        id: 'Movie|movie|2024',
        mediaKey: 'Movie|movie|2024',
        mediaType: MediaType.movie,
        title: 'Movie',
        position: const Duration(seconds: 30),
        completed: false,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    expect((await library.history()).length, 1);
  });
}
