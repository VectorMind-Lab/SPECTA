import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_lifecycle_service.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import '../../../support/fake_js_sandbox.dart';

/// Phase 2H application-level lifecycle behaviour: installation through the
/// real manager, deterministic duplicate-ID handling, enable/disable enforced
/// by the manager (not by UI state), runtime retirement, and failure isolation.
///
/// The sandbox is a fake, but the manager, the registry, the manifest parser,
/// the API-compatibility gate and the file I/O are all the production code.

void main() {
  late Directory dir;
  late InMemoryExtensionRegistry registry;
  late FakeRuntimeApi api;
  late List<FakeJsSandbox> sandboxes;

  /// Builds a manager whose sandbox factory records each sandbox it hands out,
  /// so a test can inspect disposal. [failAt] marks sandbox index `i` (0-based,
  /// in creation order) as a JS engine that fails to evaluate.
  ExtensionManager buildManager({bool Function(int index)? failAt}) {
    int index = 0;
    return ExtensionManager(
      registry: registry,
      runtimeApi: api,
      sandboxFactory: () {
        final int i = index++;
        final FakeJsSandbox sandbox = FakeJsSandbox(
          shouldFailEval: failAt?.call(i) ?? false,
        );
        // The fake sandbox does not evaluate JavaScript: it serves canned
        // strings per expression. Give healthCheck a real answer so a loaded
        // runtime can actually be probed.
        sandbox.setAsyncResult(
          'JSON.stringify(await _spectaInstance.healthCheck())',
          'true',
        );
        sandboxes.add(sandbox);
        return sandbox;
      },
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_ext_lifecycle');
    registry = InMemoryExtensionRegistry();
    api = FakeRuntimeApi();
    sandboxes = <FakeJsSandbox>[];
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Windows may briefly hold a file handle; cleanup must not fail a test.
    }
  });

  Future<File> write(String name, String source) async {
    final File file = File('${dir.path}/$name');
    await file.writeAsString(source);
    return file;
  }

  group('installation boundary', () {
    test('a valid file installs, and manifest fields are persisted', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'valid.js',
        extensionSource(id: 'com.test.valid', name: 'Valid One'),
      );

      final SpectaResult<ExtensionRecord> result = await manager
          .importExtension(filePath: file.path);

      expect(result.isOk, isTrue, reason: result.failureOrNull?.message);
      final ExtensionRecord record = result.valueOrNull!;
      expect(record.id, 'com.test.valid');
      expect(record.name, 'Valid One');
      expect(record.apiVersion, 2);
      expect(record.contentType, 'movies_series');
      expect(record.trustLevel, TrustLevel.unverified);
      expect(record.enabled, isTrue);
      expect(await registry.getById('com.test.valid'), isNotNull);
    });

    test(
      'a malformed file is rejected and never reaches the registry',
      () async {
        final ExtensionManager manager = buildManager();
        final File file = await write('broken.js', 'function nope( {');

        final SpectaResult<ExtensionRecord> result = await manager
            .importExtension(filePath: file.path);

        expect(result.isErr, isTrue);
        expect(await registry.getAll(), isEmpty);
      },
    );

    test('a missing required field is rejected', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'missing.js',
        '// ==SpectaExtension==\n'
            '// @id com.test.missing\n'
            '// @name Only Two Fields\n'
            '// ==/SpectaExtension==\n'
            'class Extension extends SpectaExtension {}',
      );

      final SpectaResult<ExtensionRecord> result = await manager
          .importExtension(filePath: file.path);

      expect(result.isErr, isTrue);
      expect(await registry.getAll(), isEmpty);
    });

    test('an unsupported API version is rejected clearly', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'future.js',
        extensionSource(id: 'com.test.future', apiVersion: '99'),
      );

      final SpectaResult<ExtensionRecord> result = await manager
          .importExtension(filePath: file.path);

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.unsupported);
      expect(await registry.getAll(), isEmpty);
    });

    test('an unknown capability is rejected (fail-closed)', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'unknowncap.js',
        extensionSource(
          id: 'com.test.unknowncap',
          capabilities: 'search,teleportation',
        ),
      );

      final SpectaResult<ExtensionRecord> result = await manager
          .importExtension(filePath: file.path);

      expect(result.isErr, isTrue);
      expect(await registry.getAll(), isEmpty);
    });

    test('a missing file is a structured failure, not an exception', () async {
      final ExtensionManager manager = buildManager();

      final SpectaResult<ExtensionRecord> result = await manager
          .importExtension(filePath: '${dir.path}/absent.js');

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.extensionId, ExtensionManager.unidentifiedExtension);
    });
  });

  group('duplicate extension IDs', () {
    test(
      're-installing the same id replaces the record, never duplicates it',
      () async {
        final ExtensionManager manager = buildManager();
        final File first = await write(
          'v1.js',
          extensionSource(id: 'com.test.dup', name: 'Dup', version: '1.0.0'),
        );
        await manager.importExtension(filePath: first.path);

        final File second = await write(
          'v2.js',
          extensionSource(id: 'com.test.dup', name: 'Dup', version: '2.0.0'),
        );
        await manager.importExtension(filePath: second.path);

        final List<ExtensionRecord> all = await registry.getAll();
        expect(all.length, 1);
        expect(all.single.version, '2.0.0');
        expect(all.single.filePath, second.path);
      },
    );

    test(
      're-installing a DISABLED extension does not silently re-enable it',
      () async {
        final ExtensionManager manager = buildManager();
        final File file = await write(
          'toggle.js',
          extensionSource(id: 'com.test.toggle'),
        );
        await manager.importExtension(filePath: file.path);
        await manager.setEnabled('com.test.toggle', false);

        await manager.importExtension(filePath: file.path);

        final ExtensionRecord record = (await registry.getById(
          'com.test.toggle',
        ))!;
        expect(
          record.enabled,
          isFalse,
          reason: 'a re-import must not override the user\'s disable choice',
        );
      },
    );

    test('re-installing retires the running runtime for that id', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'live.js',
        extensionSource(id: 'com.test.live'),
      );
      await manager.importExtension(filePath: file.path);

      final SpectaResult<ExtensionRuntime> loaded = await manager.loadRuntime(
        'com.test.live',
      );
      expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);
      expect(sandboxes.single.isDisposed, isFalse);

      // Re-install the same id (a replacement): the old runtime must go.
      await manager.importExtension(filePath: file.path);

      expect(
        sandboxes.first.isDisposed,
        isTrue,
        reason: 'replacement must shut down the previous runtime',
      );
      final SpectaResult<bool> afterReplace = await manager.callOperation<bool>(
        'com.test.live',
        (ExtensionRuntime runtime) => runtime.healthCheck(),
      );
      expect(
        afterReplace.isErr,
        isTrue,
        reason: 'no runtime may remain loaded after a replacement',
      );
    });
  });

  group('enable / disable lifecycle', () {
    test('disabling retires the runtime and persists the flag', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'enable.js',
        extensionSource(id: 'com.test.enable'),
      );
      await manager.importExtension(filePath: file.path);
      await manager.loadRuntime('com.test.enable');

      await manager.setEnabled('com.test.enable', false);

      expect((await registry.getById('com.test.enable'))!.enabled, isFalse);
      expect(sandboxes.single.isDisposed, isTrue);
      final SpectaResult<bool> call = await manager.callOperation<bool>(
        'com.test.enable',
        (ExtensionRuntime runtime) => runtime.healthCheck(),
      );
      expect(call.isErr, isTrue);
    });

    test('a disabled extension cannot be loaded at all', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'off.js',
        extensionSource(id: 'com.test.off'),
      );
      await manager.importExtension(filePath: file.path);
      await manager.setEnabled('com.test.off', false);

      final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
        'com.test.off',
      );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.capabilityError);
      expect(
        sandboxes,
        isEmpty,
        reason: 'a disabled extension must not create a runtime',
      );
    });

    test('re-enabling makes the extension loadable again', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'again.js',
        extensionSource(id: 'com.test.again'),
      );
      await manager.importExtension(filePath: file.path);
      await manager.loadRuntime('com.test.again');
      await manager.setEnabled('com.test.again', false);

      await manager.setEnabled('com.test.again', true);
      final SpectaResult<ExtensionRuntime> reloaded = await manager.loadRuntime(
        'com.test.again',
      );

      expect(reloaded.isOk, isTrue, reason: reloaded.failureOrNull?.message);
      expect((await registry.getById('com.test.again'))!.enabled, isTrue);
    });

    test('getEnabledExtensions excludes disabled extensions', () async {
      final ExtensionManager manager = buildManager();
      final File on = await write('on.js', extensionSource(id: 'com.test.on'));
      final File off = await write(
        'off2.js',
        extensionSource(id: 'com.test.off2'),
      );
      await manager.importExtension(filePath: on.path);
      await manager.importExtension(filePath: off.path);
      await manager.setEnabled('com.test.off2', false);

      final List<ExtensionRecord> enabled = await manager
          .getEnabledExtensions();

      expect(enabled.length, 1);
      expect(enabled.single.id, 'com.test.on');
    });
  });

  group('runtime lifecycle and cleanup', () {
    test('uninstall retires the runtime and removes the record', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'gone.js',
        extensionSource(id: 'com.test.gone'),
      );
      await manager.importExtension(filePath: file.path);
      await manager.loadRuntime('com.test.gone');

      await manager.uninstall('com.test.gone');

      expect(sandboxes.single.isDisposed, isTrue);
      expect(await manager.getExtension('com.test.gone'), isNull);
      expect(await registry.getAll(), isEmpty);
    });

    test('shutdownAll disposes every live runtime', () async {
      final ExtensionManager manager = buildManager();
      final File a = await write('a.js', extensionSource(id: 'com.test.a'));
      final File b = await write('b.js', extensionSource(id: 'com.test.b'));
      await manager.importExtension(filePath: a.path);
      await manager.importExtension(filePath: b.path);
      await manager.loadRuntime('com.test.a');
      await manager.loadRuntime('com.test.b');

      await manager.shutdownAll();

      expect(sandboxes.length, 2);
      expect(sandboxes.every((FakeJsSandbox s) => s.isDisposed), isTrue);
      for (final String id in <String>['com.test.a', 'com.test.b']) {
        final SpectaResult<bool> call = await manager.callOperation<bool>(
          id,
          (ExtensionRuntime runtime) => runtime.healthCheck(),
        );
        expect(call.isErr, isTrue);
      }
    });

    test('a failed load disposes its sandbox and is never published', () async {
      final ExtensionManager manager = buildManager(
        failAt: (int index) => index == 0,
      );
      final File file = await write(
        'broken.js',
        extensionSource(id: 'com.test.brokenload'),
      );
      await manager.importExtension(filePath: file.path);

      final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
        'com.test.brokenload',
      );

      expect(result.isErr, isTrue);
      expect(sandboxes.single.isDisposed, isTrue);
      final SpectaResult<bool> call = await manager.callOperation<bool>(
        'com.test.brokenload',
        (ExtensionRuntime runtime) => runtime.healthCheck(),
      );
      expect(call.isErr, isTrue);
    });

    test(
      'one extension failing does not stop another from operating',
      () async {
        final ExtensionManager manager = buildManager(
          failAt: (int index) => index == 0,
        );
        final File bad = await write(
          'bad.js',
          extensionSource(id: 'com.test.bad'),
        );
        final File good = await write(
          'good.js',
          extensionSource(id: 'com.test.good'),
        );
        await manager.importExtension(filePath: bad.path);
        await manager.importExtension(filePath: good.path);

        final SpectaResult<ExtensionRuntime> badLoad = await manager
            .loadRuntime('com.test.bad');
        final SpectaResult<ExtensionRuntime> goodLoad = await manager
            .loadRuntime('com.test.good');

        expect(badLoad.isErr, isTrue);
        expect(goodLoad.isOk, isTrue, reason: goodLoad.failureOrNull?.message);
        final SpectaResult<bool> healthy = await manager.callOperation<bool>(
          'com.test.good',
          (ExtensionRuntime runtime) => runtime.healthCheck(),
        );
        expect(healthy.isOk, isTrue);
        expect(healthy.valueOrNull, isTrue);
      },
    );
  });

  group('capability enforcement survives the lifecycle', () {
    test('the runtime grants exactly the manifest capabilities', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'caps.js',
        extensionSource(id: 'com.test.caps', capabilities: 'search,details'),
      );
      await manager.importExtension(filePath: file.path);

      final SpectaResult<ExtensionRuntime> loaded = await manager.loadRuntime(
        'com.test.caps',
      );

      expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);
      final Set<ExtensionCapability> granted =
          loaded.valueOrNull!.grantedCapabilities;
      expect(granted, contains(ExtensionCapability.search));
      expect(granted, contains(ExtensionCapability.details));
      expect(
        granted.contains(ExtensionCapability.sources),
        isFalse,
        reason: 'an undeclared capability must never be granted',
      );
      expect(granted.contains(ExtensionCapability.network), isFalse);
    });

    test('an operation needing an undeclared capability is refused', () async {
      final ExtensionManager manager = buildManager();
      final File file = await write(
        'nocap.js',
        extensionSource(id: 'com.test.nocap', capabilities: 'search'),
      );
      await manager.importExtension(filePath: file.path);
      await manager.loadRuntime('com.test.nocap');

      final SpectaResult<Object> sources = await manager.callOperation<Object>(
        'com.test.nocap',
        (ExtensionRuntime runtime) =>
            runtime.getSources(reference: 'specta://x/1'),
      );

      expect(sources.isErr, isTrue);
      // The runtime reports a CapabilityFailure — a distinct refusal type, not
      // a generic runtime error — so the denial is unambiguous.
      final CapabilityFailure failure =
          sources.failureOrNull! as CapabilityFailure;
      expect(failure.capability, 'sources');
      expect(failure.extensionId, 'com.test.nocap');
    });
  });

  group('ExtensionLifecycleService', () {
    test(
      'installFromFile then installed() reports the extension + health',
      () async {
        final ExtensionManager manager = buildManager();
        final ExtensionLifecycleService service = ExtensionLifecycleService(
          manager: manager,
        );
        final File file = await write(
          'svc.js',
          extensionSource(id: 'com.test.svc', name: 'Service One'),
        );

        final SpectaResult<ExtensionRecord> install = await service
            .installFromFile(file.path);
        final List<ManagedExtension> installed = await service.installed();

        expect(install.isOk, isTrue);
        expect(installed.length, 1);
        expect(installed.single.id, 'com.test.svc');
        expect(installed.single.name, 'Service One');
        expect(installed.single.enabled, isTrue);
      },
    );

    test('installed() is ordered deterministically by name then id', () async {
      final ExtensionManager manager = buildManager();
      final ExtensionLifecycleService service = ExtensionLifecycleService(
        manager: manager,
      );
      final File b = await write(
        'bb.js',
        extensionSource(id: 'com.test.b', name: 'Beta'),
      );
      final File a = await write(
        'aa.js',
        extensionSource(id: 'com.test.a', name: 'alpha'),
      );
      await service.installFromFile(b.path);
      await service.installFromFile(a.path);

      final List<ManagedExtension> installed = await service.installed();

      expect(installed.map((ManagedExtension e) => e.id).toList(), <String>[
        'com.test.a',
        'com.test.b',
      ], reason: 'case-insensitive name order, then id');
    });

    test('setEnabled and uninstall flow through to persisted state', () async {
      final ExtensionManager manager = buildManager();
      final ExtensionLifecycleService service = ExtensionLifecycleService(
        manager: manager,
      );
      final File file = await write(
        'flow.js',
        extensionSource(id: 'com.test.flow'),
      );
      await service.installFromFile(file.path);

      await service.setEnabled('com.test.flow', false);
      expect((await service.installed()).single.enabled, isFalse);

      await service.uninstall('com.test.flow');
      expect(await service.installed(), isEmpty);
    });

    test('shutdownAll retires a runtime loaded through the service', () async {
      final ExtensionManager manager = buildManager();
      final ExtensionLifecycleService service = ExtensionLifecycleService(
        manager: manager,
      );
      final File file = await write(
        'shut.js',
        extensionSource(id: 'com.test.shut'),
      );
      await service.installFromFile(file.path);
      await manager.loadRuntime('com.test.shut');

      await service.shutdownAll();

      expect(sandboxes.single.isDisposed, isTrue);
    });
  });
}

/// Writes a valid `// ==SpectaExtension==` manifest over a trivial body.
String extensionSource({
  required String id,
  String name = 'Fixture',
  String version = '1.0.0',
  String apiVersion = '2',
  String type = 'movies_series',
  String capabilities = 'search,details,sources',
  String body = 'class Extension extends SpectaExtension {}',
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('// ==SpectaExtension==')
    ..writeln('// @id $id')
    ..writeln('// @name $name')
    ..writeln('// @version $version')
    ..writeln('// @author SPECTA Tests')
    ..writeln('// @apiVersion $apiVersion')
    ..writeln('// @type $type');
  if (capabilities.isNotEmpty) {
    buffer.writeln('// @capabilities $capabilities');
  }
  buffer
    ..writeln('// ==/SpectaExtension==')
    ..write(body);
  return buffer.toString();
}

/// Minimal host API. These tests load and probe runtimes; no network is used.
class FakeRuntimeApi implements ExtensionRuntimeApi {
  int requestCount = 0;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    requestCount++;
    return const ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {}
}
