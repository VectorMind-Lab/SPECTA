import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import '../../../support/fake_js_sandbox.dart';

const String _validSource = '''
// ==SpectaExtension==
// @id com.example.health
// @name Health Extension
// @version 1.0.0
// @author Test Author
// @apiVersion 2
// @type movies_series
// @capabilities network
// ==/SpectaExtension==
class Extension extends SpectaExtension {
  async load() {}
}
''';

/// Minimal host API. Health tests never reach the network, so every response is
/// a canned success.
class _FakeRuntimeApi implements ExtensionRuntimeApi {
  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async =>
      const ExtensionResponse(status: 200, ok: true, body: '{}');

  @override
  void log(ExtensionLogLevel level, String message) {}
}

void main() {
  late InMemoryExtensionRegistry registry;
  late ExtensionManager manager;

  setUp(() {
    registry = InMemoryExtensionRegistry();
    manager = ExtensionManager(registry: registry);
  });

  Future<void> install({
    String id = 'com.example.health',
    int apiVersion = 2,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    await registry.install(
      ExtensionRecord(
        id: id,
        name: 'Health Extension',
        version: '1.0.0',
        author: 'Test Author',
        apiVersion: apiVersion,
        contentType: 'movies_series',
        signature: null,
        trustLevel: TrustLevel.unverified,
        enabled: true,
        filePath: 'unused.js',
        installedAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> recordFailures(String id, int count, {Duration? age}) async {
    for (int i = 0; i < count; i++) {
      await manager.recordFailure(
        ExtensionFailureRecord(
          id: '$id-$i',
          extensionId: id,
          failureType: ExtensionFailureType.networkError.code,
          operation: 'search',
          message: 'failure $i',
          timestamp: DateTime.now().toUtc().subtract(age ?? Duration.zero),
          retryable: true,
        ),
      );
    }
  }

  group('ExtensionManager.healthOf', () {
    test('a freshly installed extension is healthy', () async {
      await install();

      final SpectaResult<ExtensionHealthState> result = await manager.healthOf(
        'com.example.health',
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.health, ExtensionHealth.healthy);
      expect(result.valueOrNull!.recentFailureCount, 0);
      expect(result.valueOrNull!.apiVersion, 2);
    });

    test('one or two recent failures degrade it', () async {
      await install();

      await recordFailures('com.example.health', 1);
      expect(
        (await manager.healthOf('com.example.health')).valueOrNull!.health,
        ExtensionHealth.degraded,
      );

      await recordFailures('com.example.health', 1);
      expect(
        (await manager.healthOf('com.example.health')).valueOrNull!.health,
        ExtensionHealth.degraded,
      );
    });

    test('three recent failures report temporarily unavailable', () async {
      await install();
      await recordFailures('com.example.health', 3);

      final SpectaResult<ExtensionHealthState> result = await manager.healthOf(
        'com.example.health',
      );

      expect(
        result.valueOrNull!.health,
        ExtensionHealth.temporarilyUnavailable,
      );
      expect(result.valueOrNull!.recentFailureCount, 3);
    });

    test('failures older than the window do not count', () async {
      await install();
      await recordFailures(
        'com.example.health',
        5,
        age: const Duration(hours: 30),
      );

      final SpectaResult<ExtensionHealthState> result = await manager.healthOf(
        'com.example.health',
      );

      expect(result.valueOrNull!.recentFailureCount, 0);
      expect(result.valueOrNull!.health, ExtensionHealth.healthy);
    });

    test('a disabled extension reports disabled', () async {
      await install();
      await manager.setEnabled('com.example.health', false);

      final SpectaResult<ExtensionHealthState> result = await manager.healthOf(
        'com.example.health',
      );

      expect(result.valueOrNull!.health, ExtensionHealth.disabled);
    });

    test('an unsupported API version reports incompatible', () async {
      await install(apiVersion: 99);

      final SpectaResult<ExtensionHealthState> result = await manager.healthOf(
        'com.example.health',
      );

      expect(result.valueOrNull!.health, ExtensionHealth.incompatible);
      expect(result.valueOrNull!.apiVersion, 99);
    });

    test('an unknown extension is an Err, not an exception', () async {
      final SpectaResult<ExtensionHealthState> result = await manager.healthOf(
        'com.example.missing',
      );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.invalidResult);
      expect(failure.extensionId, 'com.example.missing');
    });
  });

  group('health classification never mutates extension state', () {
    test('a heavily failing extension stays enabled and installed', () async {
      // There is deliberately no "disable after N failures" rule.
      await install();
      await recordFailures('com.example.health', 10);

      final SpectaResult<ExtensionHealthState> health = await manager.healthOf(
        'com.example.health',
      );
      expect(
        health.valueOrNull!.health,
        ExtensionHealth.temporarilyUnavailable,
      );

      final ExtensionRecord? record = await manager.getExtension(
        'com.example.health',
      );
      expect(record, isNotNull);
      expect(record!.enabled, isTrue);
      expect(
        (await manager.getEnabledExtensions()).map((ExtensionRecord r) => r.id),
        contains('com.example.health'),
      );
    });

    test('healthOf can be called repeatedly with the same result', () async {
      await install();
      await recordFailures('com.example.health', 4);

      for (int i = 0; i < 3; i++) {
        expect(
          (await manager.healthOf('com.example.health')).valueOrNull!.health,
          ExtensionHealth.temporarilyUnavailable,
        );
      }
      expect(await manager.getFailureCount('com.example.health'), 4);
    });

    test('failures can be cleared after a successful rollback', () async {
      await install();
      await recordFailures('com.example.health', 3);
      await registry.clearFailures('com.example.health');

      expect(
        (await manager.healthOf('com.example.health')).valueOrNull!.health,
        ExtensionHealth.healthy,
      );
    });
  });

  group('failure tracking passthrough', () {
    test('getFailures returns what was recorded', () async {
      await install();
      await recordFailures('com.example.health', 2);

      final List<ExtensionFailureRecord> failures = await manager.getFailures(
        'com.example.health',
      );

      expect(failures, hasLength(2));
      expect(
        failures.map((ExtensionFailureRecord f) => f.extensionId).toSet(),
        <String>{'com.example.health'},
      );
    });

    test('getFailureCount honours an explicit window', () async {
      await install();
      await recordFailures('com.example.health', 2);
      await recordFailures(
        'com.example.health',
        3,
        age: const Duration(hours: 2),
      );

      expect(
        await manager.getFailureCount(
          'com.example.health',
          since: const Duration(hours: 1),
        ),
        2,
      );
      expect(
        await manager.getFailureCount(
          'com.example.health',
          since: const Duration(hours: 24),
        ),
        5,
      );
    });
  });

  group('a failed load is attributed to the extension that failed', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('specta_health_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('the recorded failure carries the real extension id', () async {
      // Regression guard: load/call failures used to be attributed to the
      // literal id 'import', which made diagnostics point at nothing.
      final File file = File('${tempDir.path}/ext.js');
      await file.writeAsString(_validSource);

      final FakeJsSandbox sandbox = FakeJsSandbox();
      final ExtensionManager loadingManager = ExtensionManager(
        registry: registry,
        runtimeApi: _FakeRuntimeApi(),
        sandboxFactory: () => sandbox,
      );

      final SpectaResult<ExtensionRecord> imported = await loadingManager
          .importExtension(filePath: file.path);
      expect(imported.isOk, isTrue, reason: imported.failureOrNull?.message);
      final String id = imported.valueOrNull!.id;

      // Make the extension's own load() fail.
      sandbox.setAsyncError(
        'await _spectaInstance.load();',
        'extension load() blew up',
      );

      final SpectaResult<ExtensionRuntime> loaded = await loadingManager
          .loadRuntime(id);
      expect(loaded.isErr, isTrue);

      final List<ExtensionFailureRecord> failures = await loadingManager
          .getFailures(id);
      expect(failures, hasLength(1));
      expect(failures.single.extensionId, id);
      expect(failures.single.extensionId, isNot('import'));
      expect(
        failures.single.extensionId,
        isNot(ExtensionManager.unidentifiedExtension),
      );
      expect(failures.single.operation, 'load');
      expect(failures.single.message, contains('load() failed'));
    });

    test('a pre-manifest failure uses the documented sentinel', () async {
      final SpectaResult<ExtensionRecord> imported = await manager
          .importExtension(filePath: '${tempDir.path}/does-not-exist.js');

      expect(imported.isErr, isTrue);
      final ExtensionFailure failure =
          imported.failureOrNull! as ExtensionFailure;
      expect(failure.extensionId, ExtensionManager.unidentifiedExtension);
    });
  });
}
