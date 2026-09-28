import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/extensions/distribution/extension_storage.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_lifecycle_service.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/errors/specta_result.dart';

import '../../../support/extension_storage_harness.dart';

/// Slice 6: the user's display order is persisted, and Node 0 is not pinned.
void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;
  late ExtensionLifecycleService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_reorder');
    registry = InMemoryExtensionRegistry();
    manager = ExtensionManager(
      registry: registry,
      fileRemover: AppPrivateSourceFileRemover(
        storage: FixedRootExtensionStorage(dir),
      ),
    );
    service = ExtensionLifecycleService(manager: manager);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Best-effort cleanup.
    }
  });

  List<String> idsOf(List<ManagedExtension> items) =>
      <String>[for (final ManagedExtension e in items) e.id];

  /// Seeds [count] sources named so that NAME order and NODE order disagree.
  ///
  /// If the list ever sorted by name again, these expectations would invert —
  /// which is exactly the leak Slice 6 exists to close.
  Future<void> seed(int count) async {
    for (int i = 0; i < count; i++) {
      // Descending letters: 'C Source' sorts first, 'A Source' sorts last.
      final String letter = String.fromCharCode(67 - i);
      final DateTime now = DateTime.utc(2026, 1, 1).add(Duration(minutes: i));
      await registry.install(
        ExtensionRecord(
          id: 'com.test.n$i',
          name: '$letter Source',
          version: '1.0.0',
          author: 'SPECTA Tests',
          apiVersion: 2,
          contentType: 'movies_series',
          trustLevel: TrustLevel.unverified,
          enabled: true,
          filePath: '${dir.path}\\n$i.js',
          installedAt: now,
          updatedAt: now,
          node: SourceNode(space: SourceNodeSpace.user, index: i + 1),
          nodeOrder: i,
        ),
      );
    }
  }

  group('ordering follows the user, not the name', () {
    test('a fresh list is in install order, not name order', () async {
      await seed(3);
      final List<ManagedExtension> items = await service.installed();
      expect(
        idsOf(items),
        <String>['com.test.n0', 'com.test.n1', 'com.test.n2'],
        reason: 'install order, despite names being in reverse order',
      );
      expect(
        <String>[for (final ManagedExtension e in items) e.name],
        <String>['C Source', 'B Source', 'A Source'],
        reason: 'the names really are in the opposite order',
      );
    });
  });

  group('reorder', () {
    test('moves a node down and renumbers the rest densely', () async {
      await seed(3);
      expect(
        idsOf(await service.installed()),
        <String>['com.test.n0', 'com.test.n1', 'com.test.n2'],
      );

      await service.reorder('com.test.n0', 2);

      expect(
        idsOf(await service.installed()),
        <String>['com.test.n1', 'com.test.n2', 'com.test.n0'],
      );
      expect(
        <int>[for (final ManagedExtension e in await service.installed()) e.nodeOrder],
        <int>[0, 1, 2],
        reason: 'dense, no gaps or duplicates',
      );
    });

    test('moves a node up', () async {
      await seed(3);
      await service.reorder('com.test.n2', 0);
      expect(
        idsOf(await service.installed()),
        <String>['com.test.n2', 'com.test.n0', 'com.test.n1'],
      );
    });

    test('moving a node does not change its node label', () async {
      await seed(3);
      await service.reorder('com.test.n0', 2);
      final ManagedExtension moved = (await service.installed())
          .firstWhere((ManagedExtension e) => e.id == 'com.test.n0');
      expect(moved.nodeLabel, 'Node 1', reason: 'identity is not position');
    });

    test('an out-of-range index is clamped, not rejected', () async {
      await seed(3);
      await service.reorder('com.test.n0', 99);
      expect(
        idsOf(await service.installed()),
        <String>['com.test.n1', 'com.test.n2', 'com.test.n0'],
      );
      await service.reorder('com.test.n0', -5);
      expect(
        idsOf(await service.installed()),
        <String>['com.test.n0', 'com.test.n1', 'com.test.n2'],
      );
    });

    test('an unknown id changes nothing', () async {
      await seed(3);
      final List<String> before = idsOf(await service.installed());
      await service.reorder('com.test.nope', 0);
      expect(idsOf(await service.installed()), before);
    });

    test('reordering a single node is a no-op', () async {
      await seed(1);
      await service.reorder('com.test.n0', 0);
      expect((await service.installed()).single.id, 'com.test.n0');
    });
  });

  group('Node 0 is not pinned (A4 / Q5)', () {
    test('Node 0 can be moved to the end and stays undeletable there',
        () async {
      final DateTime now = DateTime.utc(2026, 1, 1);
      await registry.install(
        ExtensionRecord(
          id: 'com.test.core',
          name: 'C Source',
          version: '1.0.0',
          author: 'SPECTA Tests',
          apiVersion: 2,
          contentType: 'movies_series',
          trustLevel: TrustLevel.unverified,
          enabled: true,
          filePath: '${dir.path}\\core.js',
          installedAt: now,
          updatedAt: now,
          node: const SourceNode(space: SourceNodeSpace.official, index: 0),
          nodeLocked: true,
          nodeOrder: 0,
        ),
      );
      await seed(2);

      await service.reorder('com.test.core', 2);

      final List<ManagedExtension> items = await service.installed();
      expect(
        idsOf(items),
        <String>['com.test.n0', 'com.test.n1', 'com.test.core'],
        reason: 'Node 0 moved to last like any other node',
      );
      // ...and it is STILL Node 0, still locked, still undeletable there.
      final ManagedExtension core = items.last;
      expect(core.nodeLabel, 'Node 0');
      expect(core.nodeLocked, isTrue);
      final SpectaResult<Object?> refused =
          await service.uninstall('com.test.core');
      expect(refused.isErr, isTrue, reason: 'still undeletable at the end');
      expect(await registry.getAll(), hasLength(3));
    });
  });

  group('ties break deterministically', () {
    test('two nodes with the same order always render the same way',
        () async {
      final DateTime now = DateTime.utc(2026, 1, 1);
      for (final String id in <String>['com.test.zzz', 'com.test.aaa']) {
        await registry.install(
          ExtensionRecord(
            id: id,
            name: 'Same Name',
            version: '1.0.0',
            author: 'SPECTA Tests',
            apiVersion: 2,
            contentType: 'movies_series',
            trustLevel: TrustLevel.unverified,
            enabled: true,
            filePath: '${dir.path}\\$id.js',
            installedAt: now,
            updatedAt: now,
            node: const SourceNode(space: SourceNodeSpace.user, index: 1),
            // Both share an order AND a node, so only the id can separate them.
            nodeOrder: 0,
          ),
        );
      }

      for (int run = 0; run < 5; run++) {
        expect(
          idsOf(await service.installed()),
          <String>['com.test.aaa', 'com.test.zzz'],
          reason: 'repeated reads must agree (run $run)',
        );
      }
    });
  });

  group('the order survives a restart, on a real on-disk database', () {
    test('a reopened database still shows the user arrangement', () async {
      // An in-memory registry cannot prove persistence. This writes to a REAL
      // SQLite FILE, closes it, and reopens it from disk - the only way to
      // prove the arrangement is stored rather than held in a field.
      final File file = File('${dir.path}\\reorder.db');

      Future<List<String>> arrangeAndRead() async {
        final SpectaDatabase db = SpectaDatabase(
          NativeDatabase(File(file.path)),
        );
        final DriftExtensionRegistry reg = DriftExtensionRegistry(db);
        try {
          final ExtensionLifecycleService svc = ExtensionLifecycleService(
            manager: ExtensionManager(
              registry: reg,
              fileRemover: AppPrivateSourceFileRemover(
                storage: FixedRootExtensionStorage(dir),
              ),
            ),
          );
          final DateTime now = DateTime.utc(2026, 1, 1);
          for (int i = 0; i < 3; i++) {
            await reg.install(
              ExtensionRecord(
                id: 'com.test.p$i',
                // Names in the OPPOSITE order to the nodes, again.
                name: '${String.fromCharCode(67 - i)} Source',
                version: '1.0.0',
                author: 'SPECTA Tests',
                apiVersion: 2,
                contentType: 'movies_series',
                trustLevel: TrustLevel.unverified,
                enabled: true,
                filePath: '${dir.path}\\p$i.js',
                installedAt: now.add(Duration(minutes: i)),
                updatedAt: now,
                node: SourceNode(space: SourceNodeSpace.user, index: i + 1),
                nodeOrder: i,
              ),
            );
          }
          expect(
            idsOf(await svc.installed()),
            <String>['com.test.p0', 'com.test.p1', 'com.test.p2'],
          );
          await svc.reorder('com.test.p0', 2);
          return idsOf(await svc.installed());
        } finally {
          await db.close();
        }
      }

      final List<String> arranged = await arrangeAndRead();
      expect(
        arranged,
        <String>['com.test.p1', 'com.test.p2', 'com.test.p0'],
        reason: 'the user moved the first node to the end',
      );

      // "Restart": a brand new database object over the same file on disk.
      final SpectaDatabase reopened = SpectaDatabase(
        NativeDatabase(File(file.path)),
      );
      addTearDown(reopened.close);
      final ExtensionLifecycleService afterRestart =
          ExtensionLifecycleService(
        manager: ExtensionManager(registry: DriftExtensionRegistry(reopened)),
      );
      expect(
        idsOf(await afterRestart.installed()),
        arranged,
        reason: 'the arrangement is persisted, not held in memory',
      );
    });
  });
}
