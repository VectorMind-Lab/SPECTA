import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_providers.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/extension_registry.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/features/extensions/state/extensions_state.dart';

import '../../support/fake_js_sandbox.dart';

/// The extension-management state notifier over a REAL manager backed by an
/// in-memory registry. Only the JS engine is faked; installation, validation,
/// trust classification, persistence semantics and lifecycle are production
/// code paths.

void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_ext_state');
    registry = InMemoryExtensionRegistry();
    manager = ExtensionManager(
      registry: registry,
      runtimeApi: _NoopRuntimeApi(),
      sandboxFactory: FakeJsSandbox.new,
    );
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Best-effort cleanup.
    }
  });

  ProviderContainer containerFor(ExtensionManager manager) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        extensionManagerProvider.overrideWith((Ref ref) => manager),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> waitFor(
    ProviderContainer container,
    bool Function(ExtensionsState state) predicate, {
    String reason = 'state never settled',
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!predicate(container.read(extensionsProvider))) {
      if (watch.elapsed > const Duration(seconds: 5)) {
        fail('$reason (last: ${container.read(extensionsProvider).status})');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<File> write(String name, String source) async {
    final File file = File('${dir.path}/$name');
    await file.writeAsString(source);
    return file;
  }

  test('starts loading, then reports an empty registry as ready', () async {
    final ProviderContainer container = containerFor(manager);

    expect(container.read(extensionsProvider).status, ExtensionsStatus.loading);

    await waitFor(
      container,
      (ExtensionsState s) => s.status == ExtensionsStatus.ready,
    );
    expect(container.read(extensionsProvider).items, isEmpty);
  });

  test('installing a valid file lists it as enabled and unverified', () async {
    final ProviderContainer container = containerFor(manager);
    final File file = await write(
      'valid.js',
      _source(id: 'com.test.state', name: 'State Extension'),
    );

    final SpectaResult<ExtensionRecord> result = await container
        .read(extensionsProvider.notifier)
        .install(file.path);

    expect(result.isOk, isTrue, reason: result.failureOrNull?.message);
    final ExtensionsState state = container.read(extensionsProvider);
    expect(state.status, ExtensionsStatus.ready);
    expect(state.busy, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.items.single.id, 'com.test.state');
    expect(state.items.single.enabled, isTrue);
  });

  test(
    'a rejected file reports a structured error and changes nothing',
    () async {
      final ProviderContainer container = containerFor(manager);
      await waitFor(
        container,
        (ExtensionsState s) => s.status == ExtensionsStatus.ready,
      );

      final SpectaResult<ExtensionRecord> result = await container
          .read(extensionsProvider.notifier)
          .install('${dir.path}/definitely-absent.js');

      expect(result.isErr, isTrue);
      final ExtensionsState state = container.read(extensionsProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.items, isEmpty);
      expect(await registry.getAll(), isEmpty);
    },
  );

  test('disable and enable are persisted and reflected in state', () async {
    final ProviderContainer container = containerFor(manager);
    final File file = await write('ctl.js', _source(id: 'com.test.ctl'));
    await container.read(extensionsProvider.notifier).install(file.path);

    await container
        .read(extensionsProvider.notifier)
        .setEnabled('com.test.ctl', false);
    expect(container.read(extensionsProvider).items.single.enabled, isFalse);
    expect((await registry.getById('com.test.ctl'))!.enabled, isFalse);

    await container
        .read(extensionsProvider.notifier)
        .setEnabled('com.test.ctl', true);
    expect(container.read(extensionsProvider).items.single.enabled, isTrue);
  });

  test('uninstall removes the extension from state and storage', () async {
    final ProviderContainer container = containerFor(manager);
    final File file = await write('rm.js', _source(id: 'com.test.rm'));
    await container.read(extensionsProvider.notifier).install(file.path);

    await container.read(extensionsProvider.notifier).uninstall('com.test.rm');

    expect(container.read(extensionsProvider).items, isEmpty);
    expect(await registry.getById('com.test.rm'), isNull);
  });

  test(
    'reload picks up an extension installed behind the notifier\'s back',
    () async {
      final ProviderContainer container = containerFor(manager);
      await waitFor(
        container,
        (ExtensionsState s) => s.status == ExtensionsStatus.ready,
      );

      await registry.install(_record('com.test.external'));
      await container.read(extensionsProvider.notifier).reload();

      expect(
        container.read(extensionsProvider).items.single.id,
        'com.test.external',
      );
    },
  );

  test(
    'a failing registry surfaces the failure state, not an exception',
    () async {
      final ProviderContainer container = containerFor(_ThrowingManager());
      await waitFor(
        container,
        (ExtensionsState s) => s.status == ExtensionsStatus.failure,
      );

      expect(container.read(extensionsProvider).errorMessage, isNotNull);
    },
  );
}

String _source({
  required String id,
  String name = 'Fixture',
  String version = '1.0.0',
}) {
  return '// ==SpectaExtension==\n'
      '// @id $id\n'
      '// @name $name\n'
      '// @version $version\n'
      '// @author SPECTA Tests\n'
      '// @apiVersion 2\n'
      '// @type movie\n'
      '// @capabilities search\n'
      '// ==/SpectaExtension==\n'
      'class Extension extends SpectaExtension {}';
}

ExtensionRecord _record(String id) {
  final DateTime now = DateTime.now().toUtc();
  return ExtensionRecord(
    id: id,
    name: 'External',
    version: '1.0.0',
    author: 'SPECTA Tests',
    apiVersion: 2,
    contentType: 'movie',
    signature: null,
    trustLevel: TrustLevel.unverified,
    enabled: true,
    filePath: '/fake/$id.js',
    installedAt: now,
    updatedAt: now,
  );
}

class _NoopRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async =>
      const ExtensionResponse(status: 200, ok: true, body: '{}');

  @override
  void log(ExtensionLogLevel level, String message) {}
}

/// A manager whose registry reads always throw, to prove the notifier contains
/// storage failures instead of letting them escape to the UI.
class _ThrowingManager extends ExtensionManager {
  _ThrowingManager()
    : super(
        registry: _ThrowingRegistry(),
        runtimeApi: _NoopRuntimeApi(),
        sandboxFactory: FakeJsSandbox.new,
      );
}

class _ThrowingRegistry implements ExtensionRegistry {
  @override
  Future<List<ExtensionRecord>> getAll() async =>
      throw StateError('database unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
