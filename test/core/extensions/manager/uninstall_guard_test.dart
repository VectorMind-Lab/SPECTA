import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/distribution/extension_storage.dart';
import 'package:specta/core/extensions/identity/source_node.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';

import '../../../support/extension_storage_harness.dart';

/// Slice 4: Node 0 is undeletable, and a real delete removes the file too.
///
/// Every assertion here runs against a REAL file on a REAL temp filesystem
/// rooted as app-private storage. A mocked remover would pass even if the
/// production guard were wrong, which is the one thing this slice must prove.
void main() {
  late Directory root;
  late Directory outside;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  /// The production remover, rooted at [root] instead of the platform channel.
  AppPrivateSourceFileRemover realRemover() =>
      AppPrivateSourceFileRemover(storage: FixedRootExtensionStorage(root));

  ExtensionManager buildManager({SourceFileRemover? remover}) => ExtensionManager(
        registry: registry,
        fileRemover: remover ?? realRemover(),
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('specta_delete_root');
    outside = await Directory.systemTemp.createTemp('specta_delete_outside');
    registry = InMemoryExtensionRegistry();
    manager = buildManager();
  });

  tearDown(() async {
    for (final Directory d in <Directory>[root, outside]) {
      try {
        await d.delete(recursive: true);
      } on Object catch (_) {
        // Windows may briefly hold a handle; cleanup must not fail a test.
      }
    }
  });

  /// Writes a minimal valid extension into [dir] and imports it.
  Future<ExtensionRecord> install(
    String id, {
    SourceNodeSpace space = SourceNodeSpace.user,
    Directory? dir,
  }) async {
    final File file =
        File('${(dir ?? root).path}${Platform.pathSeparator}$id.js');
    await file.writeAsString(_sourceFor(id), flush: true);
    final SpectaResult<ExtensionRecord> result =
        await manager.importExtension(filePath: file.path, space: space);
    expect(result.isOk, isTrue, reason: 'install of $id should succeed');
    return result.valueOrNull!;
  }

  group('other nodes delete normally (Q4)', () {
    test('an official Node A is deletable', () async {
      final ExtensionRecord node0 = await install(
        'com.test.official',
        space: SourceNodeSpace.official,
      );
      // The first official source takes index 0, so install a second to get A.
      final ExtensionRecord second = await install(
        'com.test.official2',
        space: SourceNodeSpace.official,
      );
      expect(node0.nodeLabel, 'Node 0');
      expect(second.nodeLabel, 'Node A');
      expect(second.nodeLocked, isFalse);

      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.official2');

      expect(result.isOk, isTrue, reason: 'an unlocked official node deletes');
      expect(await manager.getExtension('com.test.official2'), isNull);
    });

    test('a user node is deletable', () async {
      await install('com.test.user');
      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.user');
      expect(result.isOk, isTrue);
      expect(await registry.getAll(), isEmpty);
    });

    test('deleting Node A does not renumber Node 0', () async {
      await install('com.test.core', space: SourceNodeSpace.official);
      final ExtensionRecord nodeA = await install(
        'com.test.official2',
        space: SourceNodeSpace.official,
      );
      expect(nodeA.nodeLabel, 'Node A');

      await manager.uninstall('com.test.official2');

      final ExtensionRecord? core = await manager.getExtension('com.test.core');
      expect(core!.nodeLabel, 'Node 0', reason: 'Node 0 must keep its label');
    });
  });

  group('the file really goes (A7)', () {
    test('the .js is deleted from app-private storage', () async {
      await install('com.test.wiped');
      final File file =
          File('${root.path}${Platform.pathSeparator}com.test.wiped.js');
      expect(await file.exists(), isTrue);

      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.wiped');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.fileRemoved, isTrue);
      expect(await file.exists(), isFalse, reason: 'no orphan .js may remain');
    });

    test('a path outside app-private storage is never unlinked', () async {
      // A file the user picked from their own device, in a directory SPECTA
      // does not own. Deleting it would destroy a user file.
      final File foreign = File(
        '${outside.path}${Platform.pathSeparator}com.test.foreign.js',
      );
      await foreign.writeAsString(_sourceFor('com.test.foreign'), flush: true);
      final SpectaResult<ExtensionRecord> imported =
          await manager.importExtension(filePath: foreign.path);
      expect(imported.isOk, isTrue);

      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.foreign');

      // The row is gone...
      expect(result.isOk, isTrue);
      expect(await registry.getAll(), isEmpty);
      // ...but the user's own file is NOT deleted.
      expect(result.valueOrNull!.fileRemoved, isFalse);
      expect(
        await foreign.exists(),
        isTrue,
        reason: 'a path outside app storage must never be unlinked',
      );
    });

    test('uninstall succeeds when the file is already gone', () async {
      final ExtensionRecord record = await install('com.test.ghost');
      // Simulate an external cleanup of the file before the user deletes.
      final File file = File(record.filePath);
      if (await file.exists()) await file.delete();
      expect(await file.exists(), isFalse);

      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.ghost');

      expect(
        result.isOk,
        isTrue,
        reason: 'an absent file is the desired end state, not a failure',
      );
      expect(await registry.getAll(), isEmpty);
    });

    test('the root directory itself is never unlinked', () async {
      expect(SourceFileContainment.isInside(root.path, root.path), isFalse);
      expect(await realRemover().remove(root.path), isFalse);
      expect(await root.exists(), isTrue);
    });
  });

  group('Node 0 cannot be deleted', () {
    test('uninstall is refused and the node stays installed', () async {
      final ExtensionRecord node0 = await install(
        'com.test.core',
        space: SourceNodeSpace.official,
      );
      expect(node0.nodeLabel, 'Node 0');
      expect(node0.nodeLocked, isTrue);

      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.core');

      expect(result.isErr, isTrue, reason: 'Node 0 must be undeletable');
      final SpectaFailure failure = result.failureOrNull!;
      expect(failure, isA<ExtensionFailure>());
      expect(
        (failure as ExtensionFailure).type,
        ExtensionFailureType.capabilityError,
      );
      expect(
        failure.message,
        contains('Node 0'),
        reason: 'the refusal must name the node the user sees',
      );

      // Still installed, still enabled — a refusal is not a partial delete.
      final ExtensionRecord? after = await manager.getExtension('com.test.core');
      expect(after, isNotNull);
      expect(after!.nodeLabel, 'Node 0');
      expect(after.enabled, isTrue);
      expect(await registry.getAll(), hasLength(1));
    });

    test('a refused delete leaves the file on disk untouched', () async {
      await install('com.test.core', space: SourceNodeSpace.official);
      final File file =
          File('${root.path}${Platform.pathSeparator}com.test.core.js');
      expect(await file.exists(), isTrue);

      await manager.uninstall('com.test.core');

      expect(
        await file.exists(),
        isTrue,
        reason: 'a refused delete must not touch the file',
      );
    });
  });

  group('the containment guard itself', () {
    test('sees through .. segments that would escape the root', () async {
      final File victim =
          File('${outside.path}${Platform.pathSeparator}victim.js');
      await victim.writeAsString('// not ours', flush: true);
      final String escaping = '${root.path}${Platform.pathSeparator}'
          '..${Platform.pathSeparator}${outside.uri.pathSegments.last}'
          '${Platform.pathSeparator}victim.js';

      expect(
        SourceFileContainment.isInside(root.path, escaping),
        isFalse,
        reason: 'the guard must see through .. segments',
      );

      expect(await realRemover().remove(escaping), isFalse);
      expect(await victim.exists(), isTrue);
    });

    test('a sibling directory sharing a prefix is not inside', () {
      // ".../extensions-evil" must not pass as ".../extensions".
      expect(
        SourceFileContainment.isInside(
          '${root.path}${Platform.pathSeparator}extensions',
          '${root.path}${Platform.pathSeparator}extensions-evil'
              '${Platform.pathSeparator}a.js',
        ),
        isFalse,
      );
    });

    test('a genuinely nested file is inside', () {
      final String nested = '${root.path}${Platform.pathSeparator}sub'
          '${Platform.pathSeparator}a.js';
      expect(SourceFileContainment.isInside(root.path, nested), isTrue);
    });

    test('empty paths are never inside', () {
      expect(SourceFileContainment.isInside('', 'a.js'), isFalse);
      expect(SourceFileContainment.isInside(root.path, ''), isFalse);
    });
  });

  group('disable is not delete', () {
    test('turning a node off keeps it installed and keeps its file', () async {
      final ExtensionRecord record = await install('com.test.off');
      final File file = File(record.filePath);

      await manager.setEnabled('com.test.off', false);

      final ExtensionRecord? after = await manager.getExtension('com.test.off');
      expect(after, isNotNull, reason: 'OFF must not remove the node');
      expect(after!.enabled, isFalse);
      expect(after.nodeLabel, record.nodeLabel);
      expect(await file.exists(), isTrue);
    });

    test('Node 0 can be turned off even though it cannot be deleted', () async {
      await install('com.test.core', space: SourceNodeSpace.official);

      await manager.setEnabled('com.test.core', false);

      final ExtensionRecord? after = await manager.getExtension('com.test.core');
      expect(after, isNotNull);
      expect(after!.enabled, isFalse, reason: 'OFF is always permitted');
    });
  });

  group('uninstall of an unknown id', () {
    test('is a controlled failure, not a throw or a silent no-op', () async {
      final SpectaResult<UninstallOutcome> result =
          await manager.uninstall('com.test.never-existed');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ExtensionFailure>());
    });
  });
}

/// A minimal, valid, unsigned extension source with the given id.
///
/// The manifest is a `// @field` comment header, exactly as the production
/// `ManifestParser` expects — not a JS object.
String _sourceFor(String id) => '''
// ==SpectaExtension==
// @id $id
// @name Test Source
// @version 1.0.0
// @author SPECTA Tests
// @apiVersion 2
// @type movies_series
// @capabilities search,details,sources
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
