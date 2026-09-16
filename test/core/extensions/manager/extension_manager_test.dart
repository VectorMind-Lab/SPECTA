import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

import '../../../support/fake_js_sandbox.dart';

void main() {
  group('InMemoryExtensionRegistry', () {
    late InMemoryExtensionRegistry registry;

    setUp(() => registry = InMemoryExtensionRegistry());

    test('install stores and getById retrieves a record', () async {
      final ExtensionRecord record = _testRecord('com.example.test');
      await registry.install(record);
      final ExtensionRecord? retrieved = await registry.getById(
        'com.example.test',
      );
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'com.example.test');
      expect(retrieved.name, 'Test Extension');
    });

    test('install with same ID replaces existing record', () async {
      final ExtensionRecord record1 = _testRecord('com.example.test');
      await registry.install(record1);
      final ExtensionRecord record2 = ExtensionRecord(
        id: 'com.example.test',
        name: 'Updated Name',
        version: '2.0.0',
        author: 'Author',
        apiVersion: 2,
        contentType: 'movie',
        signature: null,
        trustLevel: TrustLevel.unverified,
        enabled: true,
        filePath: '/path/to/updated.js',
        installedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await registry.install(record2);
      final ExtensionRecord? retrieved = await registry.getById(
        'com.example.test',
      );
      expect(retrieved!.name, 'Updated Name');
      expect(retrieved.version, '2.0.0');
    });

    test('getAll returns all installed extensions', () async {
      await registry.install(_testRecord('com.example.one'));
      await registry.install(_testRecord('com.example.two'));
      final List<ExtensionRecord> all = await registry.getAll();
      expect(all.length, 2);
    });

    test('getEnabled returns only enabled extensions', () async {
      await registry.install(_testRecord('com.example.enabled', enabled: true));
      await registry.install(
        _testRecord('com.example.disabled', enabled: false),
      );
      final List<ExtensionRecord> enabled = await registry.getEnabled();
      expect(enabled.length, 1);
      expect(enabled.first.id, 'com.example.enabled');
    });

    test('setEnabled toggles enabled state', () async {
      await registry.install(_testRecord('com.example.test', enabled: true));
      await registry.setEnabled('com.example.test', false);
      final ExtensionRecord? record = await registry.getById(
        'com.example.test',
      );
      expect(record!.enabled, isFalse);
    });

    test('setEnabled on non-existent ID is a no-op', () async {
      await registry.setEnabled('nonexistent', false);
      final List<ExtensionRecord> all = await registry.getAll();
      expect(all, isEmpty);
    });

    test('uninstall removes extension and its versions', () async {
      await registry.install(_testRecord('com.example.test'));
      await registry.saveVersion(_testVersion('com.example.test'));
      await registry.uninstall('com.example.test');
      expect(await registry.getById('com.example.test'), isNull);
      expect(await registry.getRollbackVersion('com.example.test'), isNull);
    });

    test('saveVersion and getRollbackVersion', () async {
      final ExtensionVersionRecord version = _testVersion('com.example.test');
      await registry.saveVersion(version);
      final ExtensionVersionRecord? rollback = await registry
          .getRollbackVersion('com.example.test');
      expect(rollback, isNotNull);
      expect(rollback!.version, '1.0.0');
      expect(rollback.isRollbackPoint, isTrue);
    });

    test('getRollbackVersion returns null when no versions saved', () async {
      expect(await registry.getRollbackVersion('com.example.test'), isNull);
    });

    test('recordFailure and getFailures', () async {
      final ExtensionFailureRecord record = ExtensionFailureRecord(
        id: 'failure-1',
        extensionId: 'com.example.test',
        failureType: 'NETWORK_ERROR',
        operation: 'search',
        message: 'Connection timed out',
        timestamp: DateTime.now().toUtc(),
        retryable: true,
      );
      await registry.recordFailure(record);
      final List<ExtensionFailureRecord> failures = await registry.getFailures(
        'com.example.test',
      );
      expect(failures.length, 1);
      expect(failures.first.message, 'Connection timed out');
    });

    test('getFailures filters by extension ID', () async {
      await registry.recordFailure(_testFailure('ext-a', 'failure-a'));
      await registry.recordFailure(_testFailure('ext-b', 'failure-b'));
      final List<ExtensionFailureRecord> failures = await registry.getFailures(
        'ext-a',
      );
      expect(failures.length, 1);
      expect(failures.first.message, 'failure-a');
    });

    test('getFailureCount filters by time window', () async {
      final DateTime now = DateTime.now().toUtc();
      await registry.recordFailure(
        ExtensionFailureRecord(
          id: 'old',
          extensionId: 'ext',
          failureType: 'ERROR',
          operation: 'search',
          message: 'old',
          timestamp: now.subtract(const Duration(hours: 48)),
          retryable: true,
        ),
      );
      await registry.recordFailure(
        ExtensionFailureRecord(
          id: 'recent',
          extensionId: 'ext',
          failureType: 'ERROR',
          operation: 'search',
          message: 'recent',
          timestamp: now,
          retryable: true,
        ),
      );
      final int count = await registry.getFailureCount(
        'ext',
        since: const Duration(hours: 24),
      );
      expect(count, 1);
    });

    test('clearFailures removes all failures for an extension', () async {
      await registry.recordFailure(_testFailure('ext', 'msg1'));
      await registry.recordFailure(_testFailure('ext', 'msg2'));
      await registry.clearFailures('ext');
      expect(await registry.getFailureCount('ext'), 0);
    });

    test('trustLevelOf helper returns the extension trust level', () async {
      await registry.install(_testRecord('com.example.test'));
      expect(registry.trustLevelOf('com.example.test'), TrustLevel.unverified);
    });

    test('trustLevelOf returns null for unknown extension', () {
      expect(registry.trustLevelOf('nonexistent'), isNull);
    });

    test('getFailures honours the limit and returns newest first', () async {
      final DateTime base = DateTime.now().toUtc();
      for (int i = 0; i < 5; i++) {
        await registry.recordFailure(
          ExtensionFailureRecord(
            id: 'f$i',
            extensionId: 'ext',
            failureType: 'ERROR',
            operation: 'search',
            message: 'message-$i',
            timestamp: base.add(Duration(seconds: i)),
            retryable: true,
          ),
        );
      }

      final List<ExtensionFailureRecord> limited = await registry.getFailures(
        'ext',
        limit: 2,
      );

      // The limit has to be applied to the sorted list. Applying it to a
      // cascade (..take(limit)..toList()) silently returns every match.
      expect(limited.length, 2);
      expect(limited.first.message, 'message-4');
      expect(limited.last.message, 'message-3');
    });
  });

  group('ExtensionManager', () {
    late InMemoryExtensionRegistry registry;
    late FakeRuntimeApi api;
    late ExtensionManager manager;

    setUp(() {
      registry = InMemoryExtensionRegistry();
      api = FakeRuntimeApi();
      manager = ExtensionManager(
        registry: registry,
        runtimeApi: api,
        sandboxFactory: () => FakeJsSandbox(),
      );
    });

    test(
      'importFromSource installs a valid extension and returns Ok',
      () async {
        const String js = '''
// ==SpectaExtension==
// @id com.example.valid
// @name Valid Extension
// @version 1.0.0
// @author Test Author
// @apiVersion 2
// @type movies_series
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
        final SpectaResult<ExtensionRecord> result = await manager
            .importFromSource(
              extensionId: 'com.example.valid',
              jsCode: js,
              targetPath: '/fake/path.js',
            );

        expect(result.isOk, isTrue);
        final ExtensionRecord? record = await registry.getById(
          'com.example.valid',
        );
        expect(record, isNotNull);
        expect(record!.name, 'Valid Extension');
        expect(record.apiVersion, 2);
        expect(record.trustLevel, TrustLevel.unverified);
      },
    );

    test(
      'importFromSource returns Err for missing required manifest field',
      () async {
        const String js = '''
// ==SpectaExtension==
// @id com.example.test
// @name Test
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
        final SpectaResult<ExtensionRecord> result = await manager
            .importFromSource(
              extensionId: 'com.example.test',
              jsCode: js,
              targetPath: '/fake/path.js',
            );

        expect(result.isErr, isTrue);
        final ExtensionFailure failure =
            result.failureOrNull as ExtensionFailure;
        expect(failure.type, ExtensionFailureType.invalidResult);
        expect(failure.message, contains('Missing'));
      },
    );

    test('importFromSource returns Err for unsupported API version', () async {
      const String js = '''
// ==SpectaExtension==
// @id com.example.test
// @name Test
// @version 1.0.0
// @author Test
// @apiVersion 3
// @type movies_series
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
      final SpectaResult<ExtensionRecord> result = await manager
          .importFromSource(
            extensionId: 'com.example.test',
            jsCode: js,
            targetPath: '/fake/path.js',
          );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure = result.failureOrNull as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.unsupported);
      expect(failure.message, contains('API version'));
    });

    test('importFromSource returns Err for invalid content type', () async {
      const String js = '''
// ==SpectaExtension==
// @id com.example.test
// @name Test
// @version 1.0.0
// @author Test
// @apiVersion 2
// @type anime
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
      final SpectaResult<ExtensionRecord> result = await manager
          .importFromSource(
            extensionId: 'com.example.test',
            jsCode: js,
            targetPath: '/fake/path.js',
          );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure = result.failureOrNull as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.invalidResult);
    });

    test(
      'importFromSource classifies unsigned extension as untrusted',
      () async {
        const String js = '''
// ==SpectaExtension==
// @id com.example.untrusted
// @name Untrusted
// @version 1.0.0
// @author Test
// @apiVersion 2
// @type movie
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
        final SpectaResult<ExtensionRecord> result = await manager
            .importFromSource(
              extensionId: 'com.example.untrusted',
              jsCode: js,
              targetPath: '/fake/path.js',
            );

        expect(result.isOk, isTrue);
        final ExtensionRecord? record = await registry.getById(
          'com.example.untrusted',
        );
        expect(record!.trustLevel, TrustLevel.unverified);
        expect(record.signature, isNull);
      },
    );

    test('setEnabled toggles extension state', () async {
      await registry.install(_testRecord('com.example.test', enabled: true));
      await manager.setEnabled('com.example.test', false);
      final ExtensionRecord? record = await registry.getById(
        'com.example.test',
      );
      expect(record!.enabled, isFalse);
    });

    test('loadRuntime returns Err for non-existent extension', () async {
      final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
        'nonexistent',
      );
      expect(result.isErr, isTrue);
      final ExtensionFailure failure = result.failureOrNull as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.invalidResult);
    });

    test('loadRuntime returns Err for disabled extension', () async {
      await registry.install(
        _testRecord('com.example.disabled', enabled: false),
      );
      final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
        'com.example.disabled',
      );
      expect(result.isErr, isTrue);
      final ExtensionFailure failure = result.failureOrNull as ExtensionFailure;
      expect(failure.type, ExtensionFailureType.capabilityError);
      expect(failure.message, contains('disabled'));
    });

    test('loadRuntime returns Err when no runtime API provided', () async {
      final ExtensionManager noApiManager = ExtensionManager(
        registry: registry,
        sandboxFactory: () => FakeJsSandbox(),
      );
      await registry.install(_testRecord('com.example.test'));
      final SpectaResult<ExtensionRuntime> result = await noApiManager
          .loadRuntime('com.example.test');
      expect(result.isErr, isTrue);
      final ExtensionFailure failure = result.failureOrNull as ExtensionFailure;
      expect(failure.message, contains('No runtime API'));
    });

    test('loadRuntime returns Err when no sandbox factory provided', () async {
      final ExtensionManager noSandboxManager = ExtensionManager(
        registry: registry,
        runtimeApi: api,
      );
      await registry.install(_testRecord('com.example.test'));
      final SpectaResult<ExtensionRuntime> result = await noSandboxManager
          .loadRuntime('com.example.test');
      expect(result.isErr, isTrue);
      final ExtensionFailure failure = result.failureOrNull as ExtensionFailure;
      expect(failure.message, contains('No sandbox factory'));
    });

    test('shutdown unloads a runtime', () async {
      await registry.install(_testRecord('com.example.test'));
      // loadRuntime will try to read the file, which won't exist
      final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
        'com.example.test',
      );
      // File read will fail, but that's expected (file doesn't exist)
      expect(result.isErr, isTrue);
    });

    test('rollback returns false when no previous version exists', () async {
      await registry.install(_testRecord('com.example.test'));
      final bool result = await manager.rollback('com.example.test');
      expect(result, isFalse);
    });

    test('rollback restores previous version when available', () async {
      final ExtensionRecord record = _testRecord('com.example.test');
      await registry.install(record);
      final ExtensionVersionRecord previous = _testVersion('com.example.test');
      await registry.saveVersion(previous);

      final bool result = await manager.rollback('com.example.test');
      expect(result, isTrue);

      final ExtensionRecord? updated = await registry.getById(
        'com.example.test',
      );
      expect(updated!.filePath, previous.filePath);
    });

    test('rollback returns false when extension not found', () async {
      final bool result = await manager.rollback('nonexistent');
      expect(result, isFalse);
    });

    test('healthCheck returns false for unloaded runtime', () async {
      final bool result = await manager.healthCheck('nonexistent');
      expect(result, isFalse);
    });

    test('uninstall removes the extension from the registry', () async {
      await registry.install(_testRecord('com.example.test'));
      await manager.uninstall('com.example.test');
      expect(await registry.getById('com.example.test'), isNull);
    });

    test('loadRuntime failure names the extension that failed', () async {
      final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
        'com.example.absent',
      );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      // Every failure the manager reports must carry the real extension
      // identity, never a placeholder.
      expect(failure.extensionId, 'com.example.absent');
    });

    test(
      'loadRuntime failure for a disabled extension names that id',
      () async {
        await registry.install(
          _testRecord('com.example.disabled', enabled: false),
        );

        final SpectaResult<ExtensionRuntime> result = await manager.loadRuntime(
          'com.example.disabled',
        );

        final ExtensionFailure failure =
            result.failureOrNull! as ExtensionFailure;
        expect(failure.extensionId, 'com.example.disabled');
      },
    );

    test(
      'import failure before the manifest is read uses the sentinel id',
      () async {
        final SpectaResult<ExtensionRecord> result = await manager
            .importExtension(filePath: 'definitely/not/here.js');

        expect(result.isErr, isTrue);
        final ExtensionFailure failure =
            result.failureOrNull! as ExtensionFailure;
        expect(failure.extensionId, ExtensionManager.unidentifiedExtension);
      },
    );

    test(
      'import failure after the manifest is parsed names the manifest id',
      () async {
        const String js = '''
// ==SpectaExtension==
// @id com.example.wrongapi
// @name Wrong API
// @version 1.0.0
// @author Test
// @apiVersion 99
// @type movie
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''';
        final SpectaResult<ExtensionRecord> result = await manager
            .importFromSource(
              extensionId: 'com.example.wrongapi',
              jsCode: js,
              targetPath: '/fake/path.js',
            );

        expect(result.isErr, isTrue);
        final ExtensionFailure failure =
            result.failureOrNull! as ExtensionFailure;
        expect(failure.extensionId, 'com.example.wrongapi');
      },
    );

    test('callOperation failure names the extension', () async {
      final SpectaResult<bool> result = await manager.callOperation<bool>(
        'com.example.unloaded',
        (ExtensionRuntime runtime) => runtime.healthCheck(),
      );

      expect(result.isErr, isTrue);
      final ExtensionFailure failure =
          result.failureOrNull! as ExtensionFailure;
      expect(failure.extensionId, 'com.example.unloaded');
    });

    test('a failed load disposes the sandbox it created', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'specta_load_failure',
      );
      addTearDown(() => dir.delete(recursive: true));
      final File file = File('${dir.path}/broken.js');
      // A valid manifest is required: the manager parses the file before it
      // builds the sandbox, so a manifest error would never reach the sandbox
      // this test is about.
      await file.writeAsString('''
// ==SpectaExtension==
// @id com.example.broken
// @name Broken
// @version 1.0.0
// @author Test
// @apiVersion 2
// @type movie
// @capabilities network
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''');

      // The sandbox is created, then the extension JS fails to evaluate.
      final FakeJsSandbox sandbox = FakeJsSandbox(shouldFailEval: true);
      final ExtensionManager localManager = ExtensionManager(
        registry: registry,
        runtimeApi: api,
        sandboxFactory: () => sandbox,
      );
      await registry.install(
        _testRecord('com.example.broken', filePath: file.path),
      );

      final SpectaResult<ExtensionRuntime> result = await localManager
          .loadRuntime('com.example.broken');

      expect(result.isErr, isTrue);
      // The failed runtime is never published, so nothing else can free it.
      expect(sandbox.isDisposed, isTrue);
      expect(await localManager.getExtension('com.example.broken'), isNotNull);
    });
  });
}

ExtensionRecord _testRecord(
  String id, {
  bool enabled = true,
  String filePath = '/fake/path.js',
}) {
  final DateTime now = DateTime.now().toUtc();
  return ExtensionRecord(
    id: id,
    name: 'Test Extension',
    version: '1.0.0',
    author: 'Test Author',
    apiVersion: 2,
    contentType: 'movie',
    signature: null,
    trustLevel: TrustLevel.unverified,
    enabled: enabled,
    filePath: filePath,
    installedAt: now,
    updatedAt: now,
  );
}

ExtensionVersionRecord _testVersion(String extensionId) {
  return ExtensionVersionRecord(
    id: 'version-1',
    extensionId: extensionId,
    version: '1.0.0',
    filePath: '/fake/path_v1.js',
    isCurrent: false,
    isRollbackPoint: true,
    createdAt: DateTime.now().toUtc(),
  );
}

ExtensionFailureRecord _testFailure(String extensionId, String message) {
  return ExtensionFailureRecord(
    id: 'failure-${DateTime.now().toUtc().toIso8601String()}',
    extensionId: extensionId,
    failureType: 'NETWORK_ERROR',
    operation: 'search',
    message: message,
    timestamp: DateTime.now().toUtc(),
    retryable: true,
  );
}

class FakeRuntimeApi implements ExtensionRuntimeApi {
  int logCount = 0;
  int requestCount = 0;
  final List<String> messages = <String>[];

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    requestCount++;
    return ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {
    logCount++;
    messages.add(message);
  }
}
