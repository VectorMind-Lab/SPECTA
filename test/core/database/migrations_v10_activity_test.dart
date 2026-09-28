@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Slice 7 — the v9 -> v10 upgrade, proved against a REAL v9 database file.
///
/// v10 adds one nullable column, `last_success_at`. The fact that matters is
/// what it becomes for a user who already had sources installed: NULL. Those
/// sources have no recorded success, and SPECTA must not invent one to make
/// the health screen look better. They honestly read "No data yet".
void main() {
  late Directory dir;
  late String dbPath;
  late sq.Database rawV9;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('specta_v9_upgrade');
    dbPath = p.join(dir.path, 'specta.sqlite');
    rawV9 = sq.sqlite3.open(dbPath);

    // The v9 extensions table, exactly as it was after Slice 3.
    rawV9.execute('''
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
        installed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        previous_version_path TEXT,
        previous_version TEXT,
        contract_version TEXT NOT NULL DEFAULT '2.0.0',
        node_index INTEGER,
        node_space TEXT,
        node_locked INTEGER NOT NULL DEFAULT 0,
        node_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
      )
    ''');
    rawV9.execute('''
      CREATE TABLE extension_versions (
        id TEXT NOT NULL,
        extension_id TEXT NOT NULL,
        version TEXT NOT NULL,
        file_path TEXT NOT NULL,
        is_current INTEGER NOT NULL DEFAULT 0,
        is_rollback_point INTEGER NOT NULL DEFAULT 1,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        contract_version TEXT NOT NULL DEFAULT '2.0.0',
        PRIMARY KEY (id),
        FOREIGN KEY (extension_id) REFERENCES extensions (id)
      )
    ''');
    rawV9.execute('''
      CREATE TABLE extension_failure_logs (
        id TEXT NOT NULL,
        extension_id TEXT NOT NULL,
        failure_type TEXT NOT NULL,
        operation TEXT NOT NULL,
        message TEXT NOT NULL,
        detail TEXT,
        timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        retryable INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        FOREIGN KEY (extension_id) REFERENCES extensions (id)
      )
    ''');

    // Two real sources: one on, one off, each already carrying a node.
    //
    // Values are BOUND, not interpolated. SQL string literals need single
    // quotes, which fights the repo's single-quote lint; binding sidesteps the
    // quoting question entirely and is the safer way to write a fixture anyway.
    const String insertSql =
        'INSERT INTO extensions (id, name, version, author, api_version, '
        'content_type, trust_level, enabled, file_path, installed_at, '
        'updated_at, node_index, node_space, node_locked, node_order) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    rawV9.execute(insertSql, <Object?>[
      'com.a.first', 'Alpha', '1.0.0', 'spec', 2, //
      'movies_series', 'unverified', 1, '/data/first.js', //
      1767261600, 1767261600, 1, 'user', 0, 0,
    ]);
    rawV9.execute(insertSql, <Object?>[
      'com.b.second', 'Bravo', '1.0.0', 'spec', 2, //
      'movies_series', 'unverified', 0, '/data/second.js', //
      1767348000, 1767348000, 2, 'user', 0, 1,
    ]);

    // Genuine v9 marker, or step 10 would never run.
    rawV9.execute('PRAGMA user_version = 9');
  });

  tearDown(() {
    try {
      rawV9.close();
    } on Object catch (_) {
      // Already closed by the upgraded handle.
    }
    try {
      dir.deleteSync(recursive: true);
    } on Object catch (_) {
      // Best-effort cleanup.
    }
  });

  test('a real v9 file upgrades to v10 and loses nothing', () async {
    final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    // The upgrade runs on first use.
    final DriftExtensionRegistry registry = DriftExtensionRegistry(db);
    final List<ExtensionRecord> all = await registry.getAll();

    expect(db.schemaVersion, 10);
    expect(all, hasLength(2), reason: 'both installed sources survive');

    final ExtensionRecord first =
        all.firstWhere((ExtensionRecord r) => r.id == 'com.a.first');
    expect(first.name, 'Alpha');
    expect(first.enabled, isTrue);
    expect(first.nodeLabel, 'Node 1');
    expect(first.filePath, '/data/first.js');

    // The honest default: no recorded success for anything that predates v10.
    expect(
      first.lastSuccessAt,
      isNull,
      reason: 'SPECTA must not invent a success for a pre-v10 source',
    );
    expect(
      first.hasRecordedActivity,
      isFalse,
      reason: 'so the health screen honestly reads "No data yet"',
    );

    // The disabled state and node order survive too.
    final ExtensionRecord second =
        all.firstWhere((ExtensionRecord r) => r.id == 'com.b.second');
    expect(second.enabled, isFalse, reason: 'the OFF state is not reset');
    expect(second.nodeLabel, 'Node 2');
  });

  test('the new column is writable and round-trips', () async {
    final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);
    final DriftExtensionRegistry registry = DriftExtensionRegistry(db);

    await registry.setLastSuccess('com.a.first', DateTime.utc(2026, 2, 3, 4));
    final ExtensionRecord after = (await registry.getById('com.a.first'))!;
    // Compared as an INSTANT. Drift hands the value back in the local zone, so
    // asserting on the wall-clock string would fail on any machine that is not
    // on UTC — a test bug, not a product bug.
    expect(
      after.lastSuccessAt!.isAtSameMomentAs(DateTime.utc(2026, 2, 3, 4)),
      isTrue,
    );
    expect(after.hasRecordedActivity, isTrue);

    // The other source is untouched: activity is per source, not global.
    expect((await registry.getById('com.b.second'))!.lastSuccessAt, isNull);
  });

  test('an older success never overwrites a newer one', () async {
    final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);
    final DriftExtensionRegistry onDisk = DriftExtensionRegistry(db);

    await onDisk.setLastSuccess('com.a.first', DateTime.utc(2026, 2, 3));
    await onDisk.setLastSuccess('com.a.first', DateTime.utc(2026, 1, 1));
    expect(
      (await onDisk.getById('com.a.first'))!.lastSuccessAt!
          .isAtSameMomentAs(DateTime.utc(2026, 2, 3)),
      isTrue,
      reason: 'the column means "most recent success"',
    );

    // The in-memory registry must agree, or health would depend on which
    // registry the app happened to be built with.
    final InMemoryExtensionRegistry memory = InMemoryExtensionRegistry();
    await memory.install((await onDisk.getById('com.a.first'))!);
    await memory.setLastSuccess('com.a.first', DateTime.utc(2026, 2, 3));
    await memory.setLastSuccess('com.a.first', DateTime.utc(2026, 1, 1));
    expect(
      (await memory.getById('com.a.first'))!.lastSuccessAt!
          .isAtSameMomentAs(DateTime.utc(2026, 2, 3)),
      isTrue,
    );
  });

  test('a fresh v10 database has the same column', () async {
    final SpectaDatabase fresh = SpectaDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    await fresh.customStatement('SELECT 1');

    // `PRAGMA table_info` reports one row per column, with the name in `name`.
    final List<QueryRow> rows = await fresh
        .customSelect('PRAGMA table_info(extensions)')
        .get();
    final List<String> columns = <String>[
      for (final QueryRow row in rows) row.read<String>('name'),
    ];

    expect(fresh.schemaVersion, 10);
    expect(
      columns,
      contains('last_success_at'),
      reason: 'an upgraded file and a fresh one must agree',
    );
  });
}
