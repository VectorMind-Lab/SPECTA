@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/contract/extension_capabilities.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/identity/extension_health.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_lifecycle_service.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';
import 'package:specta/core/extensions/runtime/request_policy.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

/// The Phase 2H end-to-end lifecycle test: a REAL `.js` fixture installed
/// through the real manager, executed by the REAL QuickJS engine, driven
/// through every contract operation, then disabled, re-enabled, shut down and
/// removed.
///
/// This is NOT a movie-site extension: it is a deterministic, network-free
/// local fixture (test/support/fixtures/lifecycle_extension.js). The one
/// network call it can make is routed through a recording transport, so no
/// external host is ever contacted.
///
/// Environment requirement: on Windows the flutter_js QuickJS bridge must be
/// on the loader path (run `tool/run_tests_real_js.sh`). On Android it ships
/// inside the APK. When the bridge is unavailable the group is SKIPPED and
/// reported honestly as unverified — never as passing.
String? _engineSkipReason() {
  if (!Platform.isWindows) return null;
  try {
    final DynamicLibrary bridge = DynamicLibrary.open('quickjs_c_bridge.dll');
    if (!bridge.providesSymbol('jsNewRuntime')) {
      return 'quickjs_c_bridge.dll was found but does not export jsNewRuntime.';
    }
    return null;
  } on Object catch (e) {
    return 'The flutter_js QuickJS bridge is not loadable in this process '
        '($e). Run tool/run_tests_real_js.sh. Real-engine lifecycle '
        'verification is PENDING here.';
  }
}

/// Records the single HTTP exchange the fixture's `ping()` can make.
class _RecordingTransport implements ExtensionHttpTransport {
  int calls = 0;
  Uri? lastUri;

  @override
  Future<ExtensionHttpResult> send({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
    required int maxBytes,
    required int maxRedirects,
  }) async {
    calls++;
    lastUri = uri;
    return const ExtensionHttpResult(
      statusCode: 200,
      headers: <String, String>{'content-type': 'application/json'},
      body: '{"ok":true}',
    );
  }
}

const String _fixturePath = 'test/support/fixtures/lifecycle_extension.js';
const String _fixtureId = 'com.specta.test.lifecycle';

void main() {
  final String? skip = _engineSkipReason();
  late Directory dir;
  late String fixtureSource;
  late _RecordingTransport transport;
  late List<String> logs;

  ExtensionManager buildManager(InMemoryExtensionRegistry registry) {
    return ExtensionManager(
      registry: registry,
      runtimeApi: ControlledExtensionRuntimeApi(
        transport: transport,
        logSink: (ExtensionLogLevel level, String message) =>
            logs.add('${level.code}:$message'),
        // Test-only policy: the fixture's single host is never resolved and no
        // external site is contacted. Production keeps private-host blocking ON.
        policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
      ),
      sandboxFactory: FlutterJsSandbox.new,
    );
  }

  setUpAll(() async {
    fixtureSource = await File(_fixturePath).readAsString();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('specta_real_lifecycle');
    transport = _RecordingTransport();
    logs = <String>[];
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Windows may briefly hold a file handle; cleanup must not fail a test.
    }
  });

  Future<File> install(Directory target, String source, String name) async {
    final File file = File('${target.path}/$name');
    await file.writeAsString(source);
    return file;
  }

  group('Phase 2H real engine lifecycle — QuickJS', () {
    test('installs, loads, runs search/details/getSources and shuts down', () async {
      final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
      final ExtensionManager manager = buildManager(registry);
      final File file = await install(dir, fixtureSource, 'fixture.js');

      // --- installation boundary ---
      final SpectaResult<ExtensionRecord> installResult = await manager
          .importExtension(filePath: file.path);
      expect(
        installResult.isOk,
        isTrue,
        reason: installResult.failureOrNull?.message,
      );
      final ExtensionRecord record = installResult.valueOrNull!;
      expect(record.id, _fixtureId);
      expect(record.name, 'Lifecycle Fixture');
      expect(record.apiVersion, 2);
      expect(record.contentType, 'movies_series');
      expect(
        record.trustLevel,
        TrustLevel.unverified,
        reason: 'the fixture is unsigned and must never be Official',
      );

      // --- load through the real engine ---
      final SpectaResult<ExtensionRuntime> loaded = await manager.loadRuntime(
        record.id,
      );
      expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);
      final ExtensionRuntime runtime = loaded.valueOrNull!;

      // Manifest capabilities are what the runtime granted — nothing extra.
      expect(
        runtime.grantedCapabilities,
        containsAll(<ExtensionCapability>[
          ExtensionCapability.search,
          ExtensionCapability.latest,
          ExtensionCapability.details,
          ExtensionCapability.sources,
          ExtensionCapability.network,
          ExtensionCapability.logging,
        ]),
      );

      // load() ran and its log() reached the host sink through the real bridge.
      expect(logs, contains('info:lifecycle fixture loaded'));

      // --- capabilities() ---
      final SpectaResult<ExtensionCapabilities> caps = await runtime
          .capabilities();
      expect(caps.isOk, isTrue);
      expect(caps.valueOrNull!.search, isTrue);
      expect(caps.valueOrNull!.details, isTrue);
      expect(caps.valueOrNull!.mp4Sources, isTrue);

      // --- search() ---
      final SpectaResult<List<SearchResult>> search = await manager
          .callOperation<List<SearchResult>>(
            record.id,
            (ExtensionRuntime r) => r.search(query: 'matrix', page: 1),
          );
      expect(search.isOk, isTrue, reason: search.failureOrNull?.message);
      expect(search.valueOrNull!.length, 2);
      expect(
        search.valueOrNull!.map((SearchResult s) => s.type),
        containsAll(<MediaType>[MediaType.movie, MediaType.series]),
      );

      // --- latest() ---
      final SpectaResult<List<SearchResult>> latest = await manager
          .callOperation<List<SearchResult>>(
            record.id,
            (ExtensionRuntime r) => r.latest(page: 1),
          );
      expect(latest.isOk, isTrue);
      expect(latest.valueOrNull!.single.title, 'Fixture Latest');

      // --- details(): movie ---
      final SpectaResult<MediaDetails> movie = await manager
          .callOperation<MediaDetails>(
            record.id,
            (ExtensionRuntime r) => r.details(url: 'specta://fixture/movie/1'),
          );
      expect(movie.isOk, isTrue, reason: movie.failureOrNull?.message);
      expect(movie.valueOrNull!.type, MediaType.movie);
      expect(movie.valueOrNull!.seasons, isEmpty);

      // --- details(): series with seasons and episodes ---
      final SpectaResult<MediaDetails> series = await manager
          .callOperation<MediaDetails>(
            record.id,
            (ExtensionRuntime r) => r.details(url: 'specta://fixture/series/1'),
          );
      expect(series.isOk, isTrue, reason: series.failureOrNull?.message);
      expect(series.valueOrNull!.type, MediaType.series);
      expect(series.valueOrNull!.seasons.single.seasonNumber, 1);
      expect(series.valueOrNull!.seasons.single.episodes.length, 2);
      expect(
        series.valueOrNull!.seasons.single.episodes.first.url,
        'specta://fixture/series/1/s1e1',
      );

      // --- getSources() ---
      final SpectaResult<List<ExtensionSource>> sources = await manager
          .callOperation<List<ExtensionSource>>(
            record.id,
            (ExtensionRuntime r) =>
                r.getSources(reference: 'specta://fixture/movie/1'),
          );
      expect(sources.isOk, isTrue, reason: sources.failureOrNull?.message);
      expect(sources.valueOrNull!.single.type, SourceType.mp4);
      expect(
        sources.valueOrNull!.single.url,
        'https://media.example.com/fixture.mp4',
      );
      expect(sources.valueOrNull!.single.quality, '1080p');

      // --- healthCheck() ---
      expect(await manager.healthCheck(record.id), isTrue);

      // --- shutdown() ---
      await manager.shutdown(record.id);
      final SpectaResult<bool> afterShutdown = await manager
          .callOperation<bool>(
            record.id,
            (ExtensionRuntime r) => r.healthCheck(),
          );
      expect(afterShutdown.isErr, isTrue);
    });

    test('disable retires the runtime; re-enable recreates it', () async {
      final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
      final ExtensionManager manager = buildManager(registry);
      final File file = await install(dir, fixtureSource, 'fixture.js');
      await manager.importExtension(filePath: file.path);
      await manager.loadRuntime(_fixtureId);

      await manager.setEnabled(_fixtureId, false);
      expect((await manager.getExtension(_fixtureId))!.enabled, isFalse);
      expect(
        (await manager.callOperation<bool>(
          _fixtureId,
          (ExtensionRuntime r) => r.healthCheck(),
        )).isErr,
        isTrue,
        reason: 'a disabled extension must not keep a live runtime',
      );
      expect(
        (await manager.loadRuntime(_fixtureId)).isErr,
        isTrue,
        reason: 'a disabled extension must not be loadable',
      );

      await manager.setEnabled(_fixtureId, true);
      final SpectaResult<ExtensionRuntime> reloaded = await manager.loadRuntime(
        _fixtureId,
      );
      expect(reloaded.isOk, isTrue, reason: reloaded.failureOrNull?.message);
      expect(
        (await reloaded.valueOrNull!.search(query: 'again', page: 1)).isOk,
        isTrue,
      );
    });

    test(
      'one broken extension never stops a working one (real engine isolation)',
      () async {
        final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
        final ExtensionManager manager = buildManager(registry);

        // Valid manifest, invalid JavaScript body.
        const String brokenSource = '''
// ==SpectaExtension==
// @id com.specta.test.broken
// @name Broken Fixture
// @version 1.0.0
// @author SPECTA Tests
// @apiVersion 2
// @type movie
// @capabilities search
// ==/SpectaExtension==
class Extension extends SpectaExtension { this is not valid js }
''';

        final File broken = await install(dir, brokenSource, 'broken.js');
        final File good = await install(dir, fixtureSource, 'good.js');
        await manager.importExtension(filePath: broken.path);
        await manager.importExtension(filePath: good.path);

        final SpectaResult<ExtensionRuntime> brokenLoad = await manager
            .loadRuntime('com.specta.test.broken');
        final SpectaResult<ExtensionRuntime> goodLoad = await manager
            .loadRuntime(_fixtureId);

        expect(brokenLoad.isErr, isTrue);
        expect(goodLoad.isOk, isTrue, reason: goodLoad.failureOrNull?.message);
        expect(
          (await manager.callOperation<List<SearchResult>>(
            _fixtureId,
            (ExtensionRuntime r) => r.search(query: 'still here', page: 1),
          )).isOk,
          isTrue,
          reason: 'the working extension must keep working',
        );
      },
    );

    test('request() from the fixture round-trips through the controlled API', () async {
      final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
      final ExtensionManager manager = buildManager(registry);
      final File file = await install(dir, fixtureSource, 'fixture.js');
      await manager.importExtension(filePath: file.path);

      // Drive the fixture's own ping() through a directly-held sandbox, so the
      // request path is exercised by real JavaScript from the fixture.
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: ControlledExtensionRuntimeApi(
          transport: transport,
          policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
        ),
        capabilities: <ExtensionCapability>{
          ExtensionCapability.network,
          ExtensionCapability.logging,
        },
      );
      final SpectaResult<void> loaded = await runtime.loadExtension(
        extensionId: _fixtureId,
        jsCode: fixtureSource,
      );
      expect(loaded.isOk, isTrue, reason: loaded.failureOrNull?.message);

      final String raw = await sandbox.evaluateAsync(
        'JSON.stringify(await _spectaInstance.ping())',
      );
      final Map<String, dynamic> received =
          jsonDecode(raw) as Map<String, dynamic>;

      expect(transport.calls, 1);
      expect(transport.lastUri.toString(), 'https://api.example.com/ping');
      expect(received['ok'], isTrue);

      await runtime.shutdown();
    });

    test(
      'the lifecycle service reports the installed fixture with its health',
      () async {
        final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
        final ExtensionManager manager = buildManager(registry);
        final ExtensionLifecycleService service = ExtensionLifecycleService(
          manager: manager,
        );
        final File file = await install(dir, fixtureSource, 'fixture.js');

        await service.installFromFile(file.path);
        final List<ManagedExtension> installed = await service.installed();

        expect(installed.single.id, _fixtureId);
        expect(installed.single.enabled, isTrue);
        expect(installed.single.healthState, ExtensionHealth.healthy);

        await service.setEnabled(_fixtureId, false);
        expect(
          (await service.installed()).single.healthState,
          ExtensionHealth.disabled,
        );

        await service.uninstall(_fixtureId);
        expect(await service.installed(), isEmpty);
      },
    );
  }, skip: skip);
}
