@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/daos/settings_dao.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/downloads/download_dao.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
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
      expect(database.schemaVersion, 10);
    });

    test('a fresh v6 database creates a usable downloads table', () async {
      // Proves the fresh-install path (createAll) produces the same downloads
      // table the migration path does — not just that the constant is 5.
      final DownloadDao downloads = DownloadDao(database);
      final DownloadRecord record = DownloadRecord(
        id: 'Movie|movie|2024',
        mediaKey: 'Movie|movie|2024',
        mediaType: MediaType.movie,
        title: 'Movie',
        status: DownloadStatus.queued,
        bytesDownloaded: 0,
        filePath: '/data/media/Movie (x).mp4',
        attempt: 0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await downloads.upsert(record);

      final DownloadRecord? read = await downloads.recordFor(record.id);
      expect(read, isNotNull);
      expect(read!.id, 'Movie|movie|2024');
      expect(read.status, DownloadStatus.queued);
    });

    test('writes and reads a setting back', () async {
      await dao.write('downloads.concurrency', '3');

      expect(await dao.read('downloads.concurrency'), '3');
    });

    test('replacing a value keeps a single row per key', () async {
      await dao.write('downloads.concurrency', '3');
      await dao.write('downloads.concurrency', '5');

      expect(await dao.readAll(), <String, String>{
        'downloads.concurrency': '5',
      });
    });

    test('missing settings read as null and can be removed', () async {
      expect(await dao.read('absent.key'), isNull);

      await dao.write('absent.key', 'value');
      await dao.remove('absent.key');

      expect(await dao.read('absent.key'), isNull);
    });
  });

  test('upgrades the oldest supported database (v1) straight through to v6', () async {
    // A Phase 0 install: the settings table and nothing else, at
    // user_version = 1. This is the LONGEST upgrade path the code can be asked
    // to walk, so it is the one that proves every step from 2 to 5 runs in
    // sequence rather than only the last one.
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
      ..execute(
        'INSERT INTO settings_entries (key, value, updated_at) VALUES (?, ?, ?)',
        <Object?>['theme.preset', 'cyan', 1700000000],
      )
      ..execute('PRAGMA user_version = 1');

    final SpectaDatabase upgraded = SpectaDatabase(NativeDatabase.opened(raw));
    addTearDown(upgraded.close);

    // The v1 row survives and the version lands on the schema this build ships.
    expect(await SettingsDao(upgraded).read('theme.preset'), 'cyan');
    expect(upgraded.schemaVersion, 10);

    // Step 2's extension tables exist and are empty. Queried directly because
    // this test is about the CHAIN running on a v1 database; the registry DAO
    // has its own suite. A missing table throws here rather than passing.
    for (final String table in <String>[
      'extensions',
      'extension_versions',
      'extension_failure_logs',
    ]) {
      final int rows = await upgraded
          .customSelect('SELECT count(*) AS c FROM $table')
          .map((row) => row.read<int>('c'))
          .getSingle();
      expect(rows, 0, reason: '$table was not created by the upgrade');
    }

    // Step 3 (watch_progress) and step 4 (media_references) are usable.
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
    await library.saveReferences('Movie|movie|2024', const <DiscoveryReference>[
      DiscoveryReference(extensionId: 'extA', url: 'https://a/movie'),
    ]);
    expect((await library.referencesFor('Movie|movie|2024')).length, 1);

    // Step 5 (downloads) is usable.
    final DownloadDao downloads = DownloadDao(upgraded);
    await downloads.upsert(
      DownloadRecord(
        id: 'Movie|movie|2024',
        mediaKey: 'Movie|movie|2024',
        mediaType: MediaType.movie,
        title: 'Movie',
        status: DownloadStatus.queued,
        bytesDownloaded: 0,
        filePath: '/data/media/Movie (x).mp4',
        attempt: 0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    expect((await downloads.all()).length, 1);
  });

  test(
    'upgrades an installed v2 database to v3 in place, preserving data',
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

      final SpectaDatabase upgraded = SpectaDatabase(
        NativeDatabase.opened(raw),
      );
      addTearDown(upgraded.close);

      // The upgrade runs on first use, and the pre-existing row survives.
      expect(await SettingsDao(upgraded).read('theme.preset'), 'cyan');
      expect(upgraded.schemaVersion, 10);

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

      // The v4 provenance table exists too (resume follow-up).
      await library.saveReferences(
        'Movie|movie|2024',
        const <DiscoveryReference>[
          DiscoveryReference(extensionId: 'extA', url: 'https://a/movie'),
        ],
      );
      expect((await library.referencesFor('Movie|movie|2024')).length, 1);
    },
  );

  test(
    'upgrades an installed v4 database to v6 in place, preserving data',
    () async {
      // Build exactly the schema the 2F resume follow-up left on disk: all v2
      // extension tables, the v3 watch_progress table and the v4
      // media_references table, with user_version = 4. DateTime columns hold
      // integer timestamps, which is how Drift stores them.
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
        ..execute('''
        CREATE TABLE watch_progress (
          id TEXT NOT NULL,
          media_key TEXT NOT NULL,
          media_type TEXT NOT NULL,
          title TEXT NOT NULL,
          subtitle_line TEXT,
          season_number INTEGER,
          episode_number INTEGER,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER,
          elapsed_ms INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (id)
        )
      ''')
        ..execute('''
        CREATE TABLE media_references (
          media_key TEXT NOT NULL,
          ordinal INTEGER NOT NULL,
          extension_id TEXT NOT NULL,
          reference_url TEXT NOT NULL,
          PRIMARY KEY (media_key, ordinal)
        )
      ''')
        ..execute(
          'INSERT INTO settings_entries (key, value, updated_at) VALUES (?, ?, ?)',
          <Object?>['downloads.concurrency', '3', 1700000000],
        )
        ..execute(
          'INSERT INTO watch_progress '
          '(id, media_key, media_type, title, subtitle_line, season_number, '
          'episode_number, position_ms, duration_ms, elapsed_ms, completed, '
          'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            'Movie|movie|2024',
            'Movie|movie|2024',
            'movie',
            'Movie',
            null,
            null,
            null,
            30000,
            null,
            25000,
            0,
            1700000001,
          ],
        )
        ..execute(
          'INSERT INTO media_references (media_key, ordinal, extension_id, '
          'reference_url) VALUES (?, ?, ?, ?)',
          <Object?>['Movie|movie|2024', 0, 'extA', 'https://a/movie'],
        )
        ..execute('PRAGMA user_version = 4');

      final SpectaDatabase upgraded = SpectaDatabase(
        NativeDatabase.opened(raw),
      );
      addTearDown(upgraded.close);

      // The upgrade runs on first use; the pre-2G data survives verbatim.
      expect(await SettingsDao(upgraded).read('downloads.concurrency'), '3');
      expect(upgraded.schemaVersion, 10);

      // Phase 2F watch progress and provenance survive the migration.
      final LibraryDao library = LibraryDao(upgraded);
      final List<WatchProgress> history = await library.history();
      expect(history.length, 1);
      expect(history.single.id, 'Movie|movie|2024');
      expect(history.single.position, const Duration(seconds: 30));
      expect((await library.referencesFor('Movie|movie|2024')).length, 1);

      // The v5 downloads table exists and is usable through its DAO —
      // including the failure columns the records persist.
      final DownloadDao downloads = DownloadDao(upgraded);
      final DownloadRecord record = DownloadRecord(
        id: 'Movie|movie|2024',
        mediaKey: 'Movie|movie|2024',
        mediaType: MediaType.movie,
        title: 'Movie',
        status: DownloadStatus.failed,
        bytesDownloaded: 1024,
        totalBytes: 4096,
        filePath: '/data/media/Movie (x).mp4',
        sourceExtensionId: 'extA',
        sourceReference: 'https://a/movie',
        attempt: 2,
        failure: DownloadFailure(
          type: DownloadFailureType.networkError,
          message: 'The network dropped during the download.',
        ),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );
      await downloads.upsert(record);

      final DownloadRecord? read = await downloads.recordFor(record.id);
      expect(read, isNotNull);
      expect(read!.status, DownloadStatus.failed);
      expect(read.bytesDownloaded, 1024);
      expect(read.totalBytes, 4096);
      expect(read.failure, isNotNull);
      expect(read.failure!.type, DownloadFailureType.networkError);
      expect(read.failure!.isRetryable, isTrue);
      expect(read.attempt, 2);

      // A second upsert of the same identity replaces the row — the identity
      // is the primary key, so retries cannot duplicate records.
      await downloads.upsert(
        record.copyWith(status: DownloadStatus.queued, attempt: 3),
      );
      expect(await downloads.recordFor(record.id).then((r) => r!.attempt), 3);
      expect((await downloads.all()).length, 1);
    },
  );
}
