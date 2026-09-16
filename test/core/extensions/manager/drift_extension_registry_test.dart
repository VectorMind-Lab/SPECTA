@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';

/// Exercises the real Drift-backed registry against an in-memory SQLite
/// database.  The in-memory registry double cannot catch schema, constraint or
/// statement errors, so these tests cover the same contract against the
/// implementation that actually ships.
void main() {
  late SpectaDatabase database;
  late DriftExtensionRegistry registry;

  setUp(() {
    database = SpectaDatabase(NativeDatabase.memory());
    registry = DriftExtensionRegistry(database);
  });

  tearDown(() => database.close());

  group('DriftExtensionRegistry', () {
    test('install then getById round-trips every persisted field', () async {
      await registry.install(_record(id: 'com.example.full'));

      final ExtensionRecord? loaded = await registry.getById(
        'com.example.full',
      );

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Extension com.example.full');
      expect(loaded.version, '1.0.0');
      expect(loaded.author, 'Test Author');
      expect(loaded.apiVersion, 2);
      expect(loaded.contentType, 'movies_series');
      expect(loaded.signature, 'ed25519:dGVzdA==');
      expect(loaded.trustLevel, TrustLevel.official);
      expect(loaded.enabled, isTrue);
      expect(loaded.filePath, '/ext/com.example.full.js');
      expect(loaded.previousVersion, '0.9.0');
      expect(loaded.previousVersionPath, '/ext/previous.js');
    });

    test(
      'getById returns null for an extension that was never installed',
      () async {
        expect(await registry.getById('com.example.absent'), isNull);
      },
    );

    test('installing the same id twice replaces the row', () async {
      await registry.install(_record(id: 'com.example.dup'));
      await registry.install(
        _record(id: 'com.example.dup', name: 'Replaced', version: '2.0.0'),
      );

      final List<ExtensionRecord> all = await registry.getAll();
      expect(all.length, 1);
      expect(all.single.name, 'Replaced');
      expect(all.single.version, '2.0.0');
    });

    test('getAll returns every extension and getEnabled filters', () async {
      await registry.install(_record(id: 'com.example.on', enabled: true));
      await registry.install(_record(id: 'com.example.off', enabled: false));

      expect((await registry.getAll()).length, 2);

      final List<ExtensionRecord> enabled = await registry.getEnabled();
      expect(enabled.length, 1);
      expect(enabled.single.id, 'com.example.on');
    });

    test('setEnabled survives a re-read', () async {
      await registry.install(_record(id: 'com.example.toggle'));

      await registry.setEnabled('com.example.toggle', false);
      expect((await registry.getById('com.example.toggle'))!.enabled, isFalse);

      await registry.setEnabled('com.example.toggle', true);
      expect((await registry.getById('com.example.toggle'))!.enabled, isTrue);
    });

    test('getRollbackVersion returns the newest rollback point only', () async {
      await registry.install(_record(id: 'com.example.rollback'));
      final DateTime base = DateTime.now().toUtc();

      await registry.saveVersion(
        _version(
          id: 'v-old',
          extensionId: 'com.example.rollback',
          version: '0.9.0',
          createdAt: base.subtract(const Duration(hours: 2)),
        ),
      );
      await registry.saveVersion(
        _version(
          id: 'v-new',
          extensionId: 'com.example.rollback',
          version: '1.0.0',
          createdAt: base,
        ),
      );
      // The current version is never a rollback target.
      await registry.saveVersion(
        _version(
          id: 'v-current',
          extensionId: 'com.example.rollback',
          version: '2.0.0',
          isCurrent: true,
          createdAt: base.add(const Duration(hours: 2)),
        ),
      );

      final ExtensionVersionRecord? rollback = await registry
          .getRollbackVersion('com.example.rollback');

      expect(rollback, isNotNull);
      expect(rollback!.version, '1.0.0');
      expect(rollback.isRollbackPoint, isTrue);
    });

    test('getRollbackVersion is null when nothing is saved', () async {
      await registry.install(_record(id: 'com.example.none'));
      expect(await registry.getRollbackVersion('com.example.none'), isNull);
    });

    test('getFailures returns newest first and honours the limit', () async {
      await registry.install(_record(id: 'com.example.failures'));
      final DateTime base = DateTime.now().toUtc();

      for (int i = 0; i < 5; i++) {
        await registry.recordFailure(
          _failure(
            id: 'f$i',
            extensionId: 'com.example.failures',
            message: 'message-$i',
            timestamp: base.add(Duration(seconds: i)),
          ),
        );
      }

      final List<ExtensionFailureRecord> all = await registry.getFailures(
        'com.example.failures',
      );
      expect(all.length, 5);
      expect(all.first.message, 'message-4');

      final List<ExtensionFailureRecord> limited = await registry.getFailures(
        'com.example.failures',
        limit: 2,
      );
      expect(limited.length, 2);
      expect(limited.first.message, 'message-4');
      expect(limited.last.message, 'message-3');
    });

    test('getFailureCount only counts failures inside the window', () async {
      await registry.install(_record(id: 'com.example.count'));
      final DateTime now = DateTime.now().toUtc();

      await registry.recordFailure(
        _failure(
          id: 'old',
          extensionId: 'com.example.count',
          message: 'old',
          timestamp: now.subtract(const Duration(hours: 48)),
        ),
      );
      await registry.recordFailure(
        _failure(
          id: 'recent',
          extensionId: 'com.example.count',
          message: 'recent',
          timestamp: now.subtract(const Duration(minutes: 1)),
        ),
      );

      expect(
        await registry.getFailureCount(
          'com.example.count',
          since: const Duration(hours: 24),
        ),
        1,
      );
    });

    test(
      'clearFailures only removes failures for the named extension',
      () async {
        await registry.install(_record(id: 'com.example.a'));
        await registry.install(_record(id: 'com.example.b'));
        await registry.recordFailure(
          _failure(id: 'a1', extensionId: 'com.example.a', message: 'a'),
        );
        await registry.recordFailure(
          _failure(id: 'b1', extensionId: 'com.example.b', message: 'b'),
        );

        await registry.clearFailures('com.example.a');

        expect(await registry.getFailureCount('com.example.a'), 0);
        expect(await registry.getFailureCount('com.example.b'), 1);
      },
    );

    test(
      'uninstall removes the extension, its versions and its failures',
      () async {
        await registry.install(_record(id: 'com.example.gone'));
        await registry.saveVersion(
          _version(id: 'v1', extensionId: 'com.example.gone', version: '1.0.0'),
        );
        await registry.recordFailure(
          _failure(id: 'f1', extensionId: 'com.example.gone', message: 'boom'),
        );

        await registry.uninstall('com.example.gone');

        expect(await registry.getById('com.example.gone'), isNull);
        expect(await registry.getRollbackVersion('com.example.gone'), isNull);
        expect(await registry.getFailures('com.example.gone'), isEmpty);
      },
    );

    test('uninstall leaves other extensions untouched', () async {
      await registry.install(_record(id: 'com.example.keep'));
      await registry.install(_record(id: 'com.example.drop'));

      await registry.uninstall('com.example.drop');

      expect(await registry.getById('com.example.keep'), isNotNull);
      expect((await registry.getAll()).length, 1);
    });

    test('uninstall of an unknown id is a no-op', () async {
      await registry.uninstall('com.example.never-existed');
      expect(await registry.getAll(), isEmpty);
    });

    test('the foreign key to extensions is actually enforced', () async {
      // specta_database.dart turns PRAGMA foreign_keys ON, so a failure row for
      // an extension that does not exist must be rejected rather than stored.
      expect(
        () => registry.recordFailure(
          _failure(
            id: 'orphan',
            extensionId: 'com.example.not-installed',
            message: 'orphan',
          ),
        ),
        throwsA(anything),
      );
    });
  });
}

ExtensionRecord _record({
  required String id,
  String? name,
  String version = '1.0.0',
  bool enabled = true,
}) {
  final DateTime now = DateTime.now().toUtc();
  return ExtensionRecord(
    id: id,
    name: name ?? 'Extension $id',
    version: version,
    author: 'Test Author',
    apiVersion: 2,
    contentType: 'movies_series',
    signature: 'ed25519:dGVzdA==',
    trustLevel: TrustLevel.official,
    enabled: enabled,
    filePath: '/ext/$id.js',
    installedAt: now,
    updatedAt: now,
    previousVersionPath: '/ext/previous.js',
    previousVersion: '0.9.0',
  );
}

ExtensionVersionRecord _version({
  required String id,
  required String extensionId,
  required String version,
  bool isCurrent = false,
  bool isRollbackPoint = true,
  DateTime? createdAt,
}) {
  return ExtensionVersionRecord(
    id: id,
    extensionId: extensionId,
    version: version,
    filePath: '/ext/$id.js',
    isCurrent: isCurrent,
    isRollbackPoint: isRollbackPoint,
    createdAt: createdAt ?? DateTime.now().toUtc(),
  );
}

ExtensionFailureRecord _failure({
  required String id,
  required String extensionId,
  required String message,
  DateTime? timestamp,
}) {
  return ExtensionFailureRecord(
    id: id,
    extensionId: extensionId,
    failureType: 'NETWORK_ERROR',
    operation: 'search',
    message: message,
    timestamp: timestamp ?? DateTime.now().toUtc(),
    retryable: true,
  );
}
