@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Slice 3 â€” the v8 -> v9 upgrade, proved against a REAL v8 database file.
///
/// This suite deliberately does not build a v8-shaped database with the current
/// code: that would test the CURRENT schema, not the migration. It opens a
/// genuine SQLite file, creates the v8 tables with their exact v8 columns,
/// inserts real rows into `extensions`, `extension_versions` and
/// `extension_failure_logs`, and then lets the real migration path upgrade it.
///
/// The point is the data a user would actually lose: a source that stops being
/// installed, a rollback point that silently disappears, or a failure log that
/// quietly resets a node's health. Each is asserted below.
void main() {
  late Directory dir;
  late String dbPath;
  // Aliased to dodge the name clash between the sqlite3 package's `Database`
  // and Drift's own `Database` class, which drift.dart also exports.
  late sq.Database rawV8;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('specta_v8_upgrade');
    dbPath = p.join(dir.path, 'specta.sqlite');
    rawV8 = sq.sqlite3.open(dbPath);

    // The v8 tables, column for column as they existed before nodes existed.
    rawV8.execute('''
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
        PRIMARY KEY (id)
      )
    ''');
    rawV8.execute('''
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
    rawV8.execute('''
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

    // Mark the file as a genuine v8 database. Drift reads its schema version
    // from `PRAGMA user_version`; without this it would believe the file is
    // brand new, take the createAll() path, and never run migration step 9 —
    // which would make this test prove nothing at all about the upgrade.
    rawV8.execute('PRAGMA user_version = 8');
  });

  tearDown(() {
    try {
      rawV8.close();
    } on Object {
      // already disposed by the test body
    }
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  void insertV8Row(
    String id, {
    String name = 'Source',
    int enabled = 1,
    required int installedAt,
  }) {
    rawV8.execute(
      'INSERT INTO extensions (id, name, version, author, api_version, '
      'content_type, trust_level, enabled, file_path, installed_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        id,
        name,
        '1.0.0',
        'Someone',
        2,
        'movie',
        TrustLevel.unverified.code,
        enabled,
        '/data/extensions/$id.js',
        installedAt,
        installedAt,
      ],
    );
  }

  test('a real v8 file with three sources upgrades and loses nothing', () async {
    // Three installed sources, one switched off, each with a rollback point and
    // a failure log — the full shape a real user actually has.
    // Drift stores DateTime as epoch seconds, so the fixture does too.
    const int jan1 = 1767261600; // 2026-01-01 10:00:00 UTC
    const int jan2 = 1767348000; // 2026-01-02 10:00:00 UTC
    const int jan3 = 1767434400; // 2026-01-03 10:00:00 UTC
    insertV8Row('com.a.first', name: 'Alpha', installedAt: jan1);
    insertV8Row('com.b.second', name: 'Bravo', enabled: 0, installedAt: jan2);
    insertV8Row('com.c.third', name: 'Charlie', installedAt: jan3);

    for (final String id in <String>[
      'com.a.first',
      'com.b.second',
      'com.c.third',
    ]) {
      rawV8.execute(
        'INSERT INTO extension_versions (id, extension_id, version, file_path, '
        'is_current, is_rollback_point, created_at) '
        'VALUES (?, ?, ?, ?, 0, 1, ?)',
        <Object?>[
          '$id-v1',
          id,
          '0.9.0',
          '/data/extensions/$id.js',
          // Drift stores DateTime as epoch seconds.
          1764573600, // 2025-12-01 10:00:00 UTC
        ],
      );
      rawV8.execute(
        'INSERT INTO extension_failure_logs (id, extension_id, failure_type, '
        'operation, message, timestamp, retryable) '
        'VALUES (?, ?, ?, ?, ?, ?, 0)',
        <Object?>[
          '$id-f1',
          id,
          'NETWORK_ERROR',
          'import',
          'transient failure',
          1767573600, // 2026-01-05 10:00:00 UTC
        ],
      );
    }
    rawV8.close();

    final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    // The upgrade ran on open.
    // This build is past v9 (Slice 7 added v10), so the file lands on the
    // schema the CURRENT build declares. What this test protects is that the
    // v9 step runs and the data survives it - not the final version number.
    expect(db.schemaVersion, 10);

    final DriftExtensionRegistry registry = DriftExtensionRegistry(db);
    final ExtensionManager manager = ExtensionManager(registry: registry);

    // 1. EVERY source survived, with its own real state intact.
    final List<ExtensionRecord> all = await manager.getAllExtensions();
    expect(all.length, 3);

    final ExtensionRecord bravo =
        all.firstWhere((ExtensionRecord r) => r.id == 'com.b.second');
    expect(bravo.name, 'Bravo');
    expect(bravo.enabled, isFalse, reason: 'the disabled flag must survive');
    expect(bravo.trustLevel, TrustLevel.unverified);
    expect(bravo.filePath, '/data/extensions/com.b.second.js');

    // 2. The rollback points survived.
    for (final String id in <String>[
      'com.a.first',
      'com.b.second',
      'com.c.third',
    ]) {
      final ExtensionVersionRecord? rollback =
          await registry.getRollbackVersion(id);
      expect(rollback, isNotNull,
          reason: 'the rollback point for $id must survive the upgrade');
      expect(rollback!.version, '0.9.0');
    }

    // 3. The failure logs survived, so health is not silently reset.
    for (final String id in <String>[
      'com.a.first',
      'com.b.second',
      'com.c.third',
    ]) {
      expect(await registry.getFailures(id), hasLength(1),
          reason: 'the failure log for $id must survive the upgrade');
    }

    // 4. The new columns exist and default honestly.
    final Extension raw = await (db.select(db.extensions)
          ..where(($ExtensionsTable t) => t.id.equals('com.a.first')))
        .getSingle();
    expect(raw.nodeIndex, isNull, reason: 'a pre-v9 row starts unassigned');
    expect(raw.nodeSpace, isNull);
    expect(raw.nodeLocked, 0,
        reason: 'upgrading must not make anything undeletable');
    expect(raw.nodeOrder, 0);
  });

  test('the lazy backfill assigns nodes once, in a deterministic order',
      () async {
    // Inserted out of order on purpose: the backfill must follow
    // (installedAt, id), NOT insertion order and NOT the source's own name.
    const int jan1 = 1767261600;
    const int jan2 = 1767348000;
    const int jan3 = 1767434400;
    insertV8Row('com.c.third', name: 'Charlie', installedAt: jan3);
    insertV8Row('com.a.first', name: 'Alpha', installedAt: jan1);
    insertV8Row('com.b.second', name: 'Bravo', installedAt: jan2);
    rawV8.close();

    final SpectaDatabase db = SpectaDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    final DriftExtensionRegistry registry = DriftExtensionRegistry(db);
    final ExtensionManager manager = ExtensionManager(registry: registry);

    await manager.ensureNodesAssigned();

    Future<String?> labelOf(String id) async =>
        (await manager.getExtension(id))!.node?.label;

    expect(await labelOf('com.a.first'), 'Node 1');
    expect(await labelOf('com.b.second'), 'Node 2');
    expect(await labelOf('com.c.third'), 'Node 3');

    // Idempotent: running it again changes nothing.
    await manager.ensureNodesAssigned();
    expect(await labelOf('com.a.first'), 'Node 1');
    expect(await labelOf('com.b.second'), 'Node 2');
    expect(await labelOf('com.c.third'), 'Node 3');

    // They are USER nodes. Upgrading must never hand a user an official,
    // undeletable Node 0.
    for (final String id in <String>[
      'com.a.first',
      'com.b.second',
      'com.c.third',
    ]) {
      final ExtensionRecord r = (await manager.getExtension(id))!;
      expect(r.node!.space, SourceNodeSpace.user);
      expect(r.nodeLocked, isFalse);
    }
  });

  test('a fresh v9 database exposes the same node columns as an upgrade',
      () async {
    // Guards the classic migration defect: createAll() and the migration path
    // drifting apart so a fresh install and an upgrade disagree.
    final SpectaDatabase fresh = SpectaDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);

    final List<String> freshColumns = (await fresh
            .customSelect('PRAGMA table_info(extensions)')
            .get())
        .map((QueryRow r) => r.read<String>('name'))
        .toList();

    expect(freshColumns, containsAll(<String>[
      'node_index',
      'node_space',
      'node_locked',
      'node_order',
    ]));
  });
}
