// PHASE 1 — REAL DEVICE RUNTIME VERIFICATION
// ==========================================
// Closes the single gap recorded in docs/PHASE_1_CLOSURE_REPORT.txt section 18:
// the Phase 1 extension subsystem has never been executed on an Android device.
//
// This file is a verification vehicle only. It imports product code and changes
// none of it. `integration_test/` is not compiled into the shipping app (no
// lib/ file imports it); it exists so this suite can run inside the real
// application process on real hardware.
//
// What it proves, end to end, in the app process on the device:
//   1.  App startup — Riverpod graph builds, home screen renders, foundation
//       self-check reads the real on-device SQLite database.
//   2.  Drift/SQLite on the device filesystem — open, migrate to schema v2,
//       all three extension tables reachable, PRAGMA foreign_keys enforced,
//       settings round trip.
//   3.  QuickJS lifecycle on the real FFI bridge — evaluate, promise bridging,
//       no ambient host APIs, dispose, fresh engine afterwards.
//   4.  Extension load through ExtensionManager + ExtensionRuntime on the real
//       engine — bootstrap, instantiation, load(), capabilities, sources.
//   5.  Controlled network: extension request() -> capability gate -> request
//       policy -> dart:io HttpClient over the device's real network stack.
//   6.  Policy refusals on the real stack: file:// scheme and DELETE method,
//       with zero transport activity.
//   7.  Capability gate: undeclared network request refused before it reaches
//       the host API; declared log() forwarded to the host sink.
//   8.  Unregistered message channel: contained without crashing the host.
//   9.  Failure isolation: a JS exception becomes a controlled error; a
//       malformed extension fails its load; the failure is recorded in the
//       real Drift registry; the next load recovers cleanly.
//
// Run (from the project root):
//   flutter test integration_test/phase1_device_verification_test.dart -d <device_id>
//
// The device logcat is the second evidence trail:
//   adb logcat -s flutter | grep SPECTA-P1

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/contract/extension_capabilities.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/drift_extension_registry.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';
import 'package:specta/main.dart' show SpectaStartup;

/// logcat evidence marker: `adb logcat -s flutter | grep SPECTA-P1`
const String _tag = 'SPECTA-P1';

void _log(String step, String detail) {
  debugPrint('[$_tag] $step :: $detail');
}

/// A well-formed extension with no signature. Imports are never rejected on
/// trust, so this classifies as [TrustLevel.unverified] by design.
const String _extensionSource = '''
// ==SpectaExtension==
// @id device.verify.probe
// @name Device Verification Probe
// @version 1.0.0
// @author SPECTA Phase 1 device run
// @apiVersion 2
// @type movie
// @capabilities network,logging,search,details,sources
// ==/SpectaExtension==
class Extension extends SpectaExtension {
  async load() { this.log('info', 'probe extension loaded on device'); }
  async capabilities() {
    return {
      contentTypes: ['movie'],
      discovery: {search: true, latest: false},
      metadata: {details: true},
      sources: {mp4: true, hls: true},
    };
  }
  async healthCheck() { return true; }
  async search(query, page) {
    const r = await this.request({
      url: 'https://example.com/?src=specta-p1&q=' + encodeURIComponent(query),
      method: 'GET',
      timeout: 20000,
    });
    return [{title: 'DeviceProbe ' + query, url: 'https://probe.invalid/watch/' + r.status, type: 'movie', year: 2026}];
  }
  async details(url) {
    const r = await this.request({url: url, method: 'GET', timeout: 20000});
    return {id: 'probe-1', title: 'Device Probe Feature', type: 'movie', url: url, year: 2026, description: 'status ' + r.status};
  }
  async getSources(ref) {
    return [{url: 'https://probe.invalid/media.mp4', type: 'mp4', quality: '1080p'}];
  }
  async boom() { throw new Error('deliberate device failure'); }
}
''';

/// The same extension minus the `network` capability, for gate verification.
String _networklessSource() => _extensionSource.replaceFirst(
  '@capabilities network,logging,search,details,sources',
  '@capabilities logging,search,details,sources',
);

/// A valid manifest wrapped around a broken JavaScript body: import must
/// succeed (only the manifest is parsed at import), load must fail.
String _malformedBodySource() => _extensionSource.replaceFirst(
  'class Extension extends SpectaExtension {',
  'class Extension extends SpectaExtension { this is not javascript {',
);

/// App-private temp directory. Android sets TMPDIR for app processes, so this
/// lands inside the app's own cache directory on the device — the exact
/// condition the manager's file-reading import path runs under.
Future<File> _writeProbe(String source, String fileName) async {
  final Directory dir = Directory(
    '${Directory.systemTemp.path}/specta_p1_probe',
  ).absolute;
  await dir.create(recursive: true);
  final File file = File('${dir.path}/$fileName');
  await file.writeAsString(source, flush: true);
  return file;
}

/// Host API that counts activity, for gate/refusal probes that must observe
/// ZERO host-side calls.
final class CountingApi implements ExtensionRuntimeApi {
  int logCalls = 0;
  final List<String> logMessages = <String>[];

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    throw StateError(
      'the host API must never be reached in this probe '
      '(${request.method} ${request.url})',
    );
  }

  @override
  void log(ExtensionLogLevel level, String message) {
    logCalls++;
    logMessages.add('${level.code}:$message');
  }
}

/// Transport that counts dispatches, for policy probes.
final class CountingTransport implements ExtensionHttpTransport {
  int calls = 0;

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
    return const ExtensionHttpResult(statusCode: 200, body: '{}');
  }
}

/// A manager over the shipping Drift registry and the real sandbox factory.
/// The caller owns [db] and closes it.
ExtensionManager _deviceManager(SpectaDatabase db, ExtensionRuntimeApi api) {
  return ExtensionManager(
    registry: DriftExtensionRegistry(db),
    runtimeApi: api,
    sandboxFactory: FlutterJsSandbox.new,
  );
}

/// Removes any rows a previous run may have left behind.
Future<void> _cleanSlate(ExtensionManager manager, String id) async {
  try {
    await manager.uninstall(id);
  } on Object {
    // Nothing installed yet; nothing to clean.
  }
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real time and real frames: this is a hardware run, not a widget simulation.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('PHASE 1 — real device runtime verification', () {
    testWidgets(
      'app startup renders and the foundation self-check reads SQLite',
      (WidgetTester tester) async {
        _log('startup', 'building SpectaStartup (Riverpod graph + manager)');
        await tester.pumpWidget(const ProviderScope(child: SpectaStartup()));

        // The foundation card opens the real on-device database and does
        // platform I/O, so wait in real time for the provider to resolve.
        await tester.runAsync(() async {
          final DateTime deadline = DateTime.now().add(
            const Duration(seconds: 25),
          );
          while (DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if (find.text('v2').evaluate().isNotEmpty) break;
          }
        });
        await tester.pump();

        expect(find.text('SPECTA'), findsOneWidget);
        _log('startup', 'SPECTA home rendered');

        expect(
          find.text('v2'),
          findsOneWidget,
          reason: 'foundation self-check must report SQLite schema v2 read '
              'back from the on-device database',
        );
        expect(find.text('Settings round trip'), findsOneWidget);
        expect(find.text('OK'), findsOneWidget);
        _log(
          'startup',
          'foundation self-check: schema v2, settings round trip OK',
        );

        try {
          await binding.takeScreenshot('p1_startup_home');
          _log('startup', 'screenshot p1_startup_home captured');
        } on Object catch (e) {
          _log('startup', 'screenshot unavailable in this harness: $e');
        }
      },
    );

    testWidgets('SpectaDatabase opens, migrates and round-trips on device',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final SpectaDatabase db = SpectaDatabase();
        try {
          expect(db.schemaVersion, 2);

          // Every extension table must be reachable at schema v2.
          await db.customSelect('SELECT count(*) AS c FROM extensions').get();
          await db
              .customSelect('SELECT count(*) AS c FROM extension_versions')
              .get();
          await db
              .customSelect('SELECT count(*) AS c FROM extension_failure_logs')
              .get();
          _log('db', 'extensions, extension_versions, extension_failure_logs OK');

          final dynamic fk =
              (await db.customSelect('PRAGMA foreign_keys').getSingle())
                  .data['foreign_keys'];
          expect(fk, 1, reason: 'PRAGMA foreign_keys must be ON per connection');
          _log('db', 'PRAGMA foreign_keys = 1');

          await db.customStatement(
            'INSERT OR REPLACE INTO settings_entries (key, value) VALUES '
            "('p1_device_probe', 'written-on-device')",
          );
          final dynamic roundTrip =
              (await db.customSelect(
                "SELECT value FROM settings_entries WHERE key = 'p1_device_probe'",
              ).getSingle()).data['value'];
          expect(roundTrip, 'written-on-device');
          _log('db', 'settings round trip OK on the device filesystem');
          await db.customStatement(
            "DELETE FROM settings_entries WHERE key = 'p1_device_probe'",
          );
        } finally {
          await db.close();
        }
      });
    });

    testWidgets('QuickJS lifecycle on the real FFI bridge',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final FlutterJsSandbox sandbox = FlutterJsSandbox();
        await sandbox.init();

        expect(await sandbox.evaluate('1+1'), '2');
        expect(await sandbox.evaluateAsync('await Promise.resolve(6*7)'), '42');
        _log('engine', 'evaluate + async promise bridging OK');

        final String types = await sandbox.evaluate(
          '[typeof fetch, typeof XMLHttpRequest, typeof require, '
          'typeof process, typeof Dart, typeof window, typeof document].join(",")',
        );
        expect(
          types,
          'undefined,undefined,undefined,undefined,undefined,undefined,undefined',
          reason: 'the engine must expose no ambient host APIs',
        );
        expect(await sandbox.evaluate('typeof sendMessage'), 'function');
        _log('engine', 'no ambient host APIs; only the message bridge exists');

        await sandbox.dispose();
        expect(sandbox.isDisposed, isTrue);
        _log('engine', 'dispose OK');

        // A closed QuickJS runtime cannot be reopened; the sandbox must build
        // a fresh engine instead of silently failing.
        final FlutterJsSandbox reborn = FlutterJsSandbox();
        await reborn.init();
        expect(await reborn.evaluate('40+2'), '42');
        await reborn.dispose();
        _log('engine', 'fresh engine after dispose OK');
      });
    });

    testWidgets(
      'ExtensionManager installs, loads and calls operations on the real engine',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          final ControlledExtensionRuntimeApi api =
              ControlledExtensionRuntimeApi(
            logSink: (ExtensionLogLevel level, String message) =>
                _log('ext-log', '${level.code}: $message'),
          );
          final SpectaDatabase db = SpectaDatabase();
          addTearDown(db.close);
          final ExtensionManager manager = _deviceManager(db, api);
          await _cleanSlate(manager, 'device.verify.probe');

          final File extFile = await _writeProbe(
            _extensionSource,
            'probe_lifecycle.js',
          );
          _log('manager', 'probe written to ${extFile.path}');

          final SpectaResult<ExtensionRecord> imported =
              await manager.importExtension(filePath: extFile.path);
          expect(imported.isOk, isTrue,
              reason: 'import failed: ${imported.failureOrNull}');
          expect(imported.valueOrNull!.trustLevel, TrustLevel.unverified);
          expect(imported.valueOrNull!.enabled, isTrue);
          _log('manager', 'import OK — trust unverified (unsigned, by design)');

          final SpectaResult<ExtensionRuntime> load =
              await manager.loadRuntime('device.verify.probe');
          expect(load.isOk, isTrue,
              reason: 'load failed: ${load.failureOrNull}');
          _log('manager', 'loadRuntime OK on the real QuickJS FFI bridge');

          final SpectaResult<ExtensionCapabilities> caps =
              await manager.callOperation<ExtensionCapabilities>(
            'device.verify.probe',
            (ExtensionRuntime r) => r.capabilities(),
          );
          expect(caps.isOk, isTrue,
              reason: 'capabilities failed: ${caps.failureOrNull}');
          expect(caps.valueOrNull!.search, isTrue);
          expect(caps.valueOrNull!.details, isTrue);
          expect(caps.valueOrNull!.hlsSources, isTrue);
          _log('manager', 'capabilities() parsed from real JS OK');

          final SpectaResult<List<ExtensionSource>> sources =
              await manager.callOperation<List<ExtensionSource>>(
            'device.verify.probe',
            (ExtensionRuntime r) => r.getSources(reference: 'probe-1'),
          );
          expect(sources.isOk, isTrue,
              reason: 'getSources failed: ${sources.failureOrNull}');
          expect(sources.valueOrNull!.single.type, SourceType.mp4);
          _log('manager', 'getSources() OK (mp4)');

          final SpectaResult<bool> health = await manager.callOperation<bool>(
            'device.verify.probe',
            (ExtensionRuntime r) => r.healthCheck(),
          );
          expect(health.valueOrNull, isTrue);
          _log('manager', 'healthCheck OK');

          await manager.shutdown('device.verify.probe');
          _log('manager', 'shutdown OK');
          await manager.uninstall('device.verify.probe');
          _log('manager', 'uninstall OK');
          api.dispose();
        });
      },
    );

    testWidgets(
      'controlled network path over the device network stack',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          // Connectivity pre-check: an offline device cannot exercise this
          // path, and that must be reported as an environment fact, not
          // silently passed or faked.
          try {
            final Socket probe = await Socket.connect(
              'example.com',
              443,
              timeout: const Duration(seconds: 10),
            );
            probe.destroy();
          } on Object catch (e) {
            fail(
              'DEVICE OFFLINE — the controlled-network verification cannot run '
              'without device internet access ($e)',
            );
          }
          _log('network', 'device has connectivity to example.com:443');

          final ControlledExtensionRuntimeApi api =
              ControlledExtensionRuntimeApi(
            logSink: (ExtensionLogLevel level, String message) =>
                _log('ext-log', '${level.code}: $message'),
          );
          final SpectaDatabase db = SpectaDatabase();
          addTearDown(db.close);
          final ExtensionManager manager = _deviceManager(db, api);
          await _cleanSlate(manager, 'device.verify.probe');

          final File extFile = await _writeProbe(
            _extensionSource,
            'probe_network.js',
          );
          await manager.importExtension(filePath: extFile.path);
          final SpectaResult<ExtensionRuntime> load =
              await manager.loadRuntime('device.verify.probe');
          expect(load.isOk, isTrue, reason: 'load failed: ${load.failureOrNull}');

          // Real HTTP over the device stack:
          // extension request() -> capability gate -> request policy ->
          // ControlledExtensionRuntimeApi -> dart:io HttpClient.
          final SpectaResult<List<SearchResult>> search =
              await manager.callOperation<List<SearchResult>>(
            'device.verify.probe',
            (ExtensionRuntime r) => r.search(query: 'specta', page: 1),
          );
          expect(search.isOk, isTrue,
              reason: 'search failed: ${search.failureOrNull}');
          expect(search.valueOrNull!.first.title, 'DeviceProbe specta');
          expect(api.requestCount, 1,
              reason: 'exactly one request must reach the transport');
          expect(api.deniedCount, 0);
          _log('network',
              'extension request() over https OK — response carried back to JS');

          await manager.shutdown('device.verify.probe');
          await manager.uninstall('device.verify.probe');
          api.dispose();
        });
      },
    );

    testWidgets(
      'request policy refuses file:// and DELETE before any transport activity',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          final CountingTransport transport = CountingTransport();
          final ControlledExtensionRuntimeApi api =
              ControlledExtensionRuntimeApi(transport: transport);
          // The policy lives in the controlled API, so it is exercised with the
          // real ControlledExtensionRuntimeApi over a counting transport.
          final FlutterJsSandbox sandbox = FlutterJsSandbox();
          final ExtensionRuntime runtime = ExtensionRuntime(
            sandbox: sandbox,
            api: api,
            capabilities: const <ExtensionCapability>{
              ExtensionCapability.network,
              ExtensionCapability.logging,
            },
          );
          addTearDown(runtime.shutdown);

          final SpectaResult<void> load = await runtime.loadExtension(
            extensionId: 'device.verify.probe',
            jsCode: _extensionSource,
          );
          expect(load.isOk, isTrue, reason: 'load failed: ${load.failureOrNull}');

          // file:// — refused by scheme, evaluated before the host.
          final String rawFile = await sandbox.evaluateAsync(
            r'JSON.stringify(await _spectaInstance.request('
            r'{url: "file:///etc/passwd"}))',
          );
          final Map<String, dynamic> fileResp =
              jsonDecode(rawFile) as Map<String, dynamic>;
          expect(fileResp['ok'], isFalse);
          expect(fileResp['errorType'], 'UNSUPPORTED',
              reason: 'a non-allowed scheme is an UNSUPPORTED refusal');
          _log('policy', 'file:// refused: ${fileResp['error']}');

          // DELETE — not on the method allow-list.
          final String rawDelete = await sandbox.evaluateAsync(
            r'JSON.stringify(await _spectaInstance.request('
            r'{url: "https://example.com/", method: "DELETE"}))',
          );
          final Map<String, dynamic> deleteResp =
              jsonDecode(rawDelete) as Map<String, dynamic>;
          expect(deleteResp['ok'], isFalse);
          expect(deleteResp['errorType'], 'UNSUPPORTED');
          _log('policy', 'DELETE refused: ${deleteResp['error']}');

          expect(transport.calls, 0,
              reason: 'policy refusals must happen before any network activity');
          expect(api.deniedCount, 2);
          _log('policy', 'zero transport activity across both refusals');
        });
      },
    );

    testWidgets(
      'capability gate: undeclared network refused before the host API',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          final CountingApi hostSpy = CountingApi();
          final FlutterJsSandbox sandbox = FlutterJsSandbox();
          final ExtensionRuntime runtime = ExtensionRuntime(
            sandbox: sandbox,
            api: hostSpy,
            // Declares logging, search, details, sources — but NOT network.
            capabilities: const <ExtensionCapability>{
              ExtensionCapability.logging,
              ExtensionCapability.search,
              ExtensionCapability.details,
              ExtensionCapability.sources,
            },
          );
          addTearDown(runtime.shutdown);

          final SpectaResult<void> load = await runtime.loadExtension(
            extensionId: 'device.verify.probe',
            jsCode: _networklessSource(),
          );
          expect(load.isOk, isTrue, reason: 'load failed: ${load.failureOrNull}');

          // request() without the network capability: refused before the
          // payload is even parsed, and before anything reaches the host API.
          // (CountingApi.request throws, so a gate bypass would surface as a
          // RUNTIME_ERROR structured error rather than CAPABILITY_ERROR.)
          final String raw = await sandbox.evaluateAsync(
            r'JSON.stringify(await _spectaInstance.request('
            r'{url: "https://example.com/"}))',
          );
          final Map<String, dynamic> resp =
              jsonDecode(raw) as Map<String, dynamic>;
          expect(resp['ok'], isFalse);
          expect(resp['errorType'], 'CAPABILITY_ERROR');
          _log('gate', 'network refusal: ${resp['error']}');
        });
      },
    );

    testWidgets(
      'declared logging reaches the host sink through the real channel',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          final CountingApi hostSpy = CountingApi();
          final FlutterJsSandbox sandbox = FlutterJsSandbox();
          final ExtensionRuntime runtime = ExtensionRuntime(
            sandbox: sandbox,
            api: hostSpy,
            capabilities: const <ExtensionCapability>{
              ExtensionCapability.logging,
              ExtensionCapability.network,
              ExtensionCapability.search,
              ExtensionCapability.details,
              ExtensionCapability.sources,
            },
          );
          addTearDown(runtime.shutdown);

          final SpectaResult<void> load = await runtime.loadExtension(
            extensionId: 'device.verify.probe',
            jsCode: _extensionSource,
          );
          expect(load.isOk, isTrue, reason: 'load failed: ${load.failureOrNull}');

          expect(hostSpy.logCalls, greaterThanOrEqualTo(1));
          expect(
            hostSpy.logMessages,
            contains('info:probe extension loaded on device'),
          );
          _log('gate', 'declared log() reached the host sink on device');
        });
      },
    );

    testWidgets('an unregistered message channel does not crash the host',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final FlutterJsSandbox sandbox = FlutterJsSandbox();
        await sandbox.init();
        addTearDown(sandbox.dispose);

        // Only specta_request and specta_log have handlers. Any other channel
        // must be contained — whatever the bridge does with it, the host
        // process survives and the engine stays usable.
        final String outcome = await sandbox.evaluate(
          r'(function(){ try { const r = sendMessage("specta_unknown_channel", "{}");'
          r'return "returned:" + String(r); } catch (e) { return "threw:" + String(e); } })()',
        );
        _log('channels', 'unregistered channel outcome: $outcome');
        expect(outcome, anyOf(startsWith('returned:'), startsWith('threw:')));
        expect(
          await sandbox.evaluate('1+1'),
          '2',
          reason: 'the engine must still be alive and usable',
        );
        _log('channels', 'engine healthy after the unregistered-channel probe');
      });
    });

    testWidgets(
      'failure isolation: JS exception, malformed load, registry failure '
      'record, recovery',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          // 1. A JS exception surfaces as a controlled JsEvalException at the
          //    sandbox boundary — never as a process crash.
          final CountingApi hostSpy = CountingApi();
          final FlutterJsSandbox sandbox = FlutterJsSandbox();
          final ExtensionRuntime runtime = ExtensionRuntime(
            sandbox: sandbox,
            api: hostSpy,
            capabilities: ExtensionCapability.values.toSet(),
          );
          addTearDown(runtime.shutdown);
          await runtime.loadExtension(
            extensionId: 'device.verify.probe',
            jsCode: _extensionSource,
          );

          Object? escaped;
          try {
            await sandbox.evaluateAsync('await _spectaInstance.boom()');
          } on Object catch (e) {
            escaped = e;
          }
          expect(escaped, isA<JsEvalException>());
          _log('isolation',
              'JS exception contained as ${escaped.runtimeType} — host alive');

          // 2. A malformed extension body fails its load as a controlled
          //    failure, and the manager records it in the Drift registry.
          final ControlledExtensionRuntimeApi hostApi =
              ControlledExtensionRuntimeApi();
          final SpectaDatabase db = SpectaDatabase();
          addTearDown(db.close);
          final ExtensionManager manager = _deviceManager(db, hostApi);
          await _cleanSlate(manager, 'device.verify.probe');

          final File badFile = await _writeProbe(
            _malformedBodySource(),
            'probe_broken.js',
          );
          final SpectaResult<ExtensionRecord> importedBad =
              await manager.importExtension(filePath: badFile.path);
          expect(importedBad.isOk, isTrue,
              reason: 'import parses the manifest only, so it must succeed');

          final SpectaResult<ExtensionRuntime> badLoad =
              await manager.loadRuntime('device.verify.probe');
          expect(badLoad.isErr, isTrue);
          expect(badLoad.failureOrNull!.message, 'Extension failed to load');
          _log('isolation',
              'malformed load contained: ${badLoad.failureOrNull.toString()}');

          final List<dynamic> failures =
              await manager.getFailures('device.verify.probe');
          expect(failures, isNotEmpty,
              reason: 'the failed load must be recorded in '
                  'extension_failure_logs on device');
          _log('isolation',
              'failure recorded in the Drift registry (${failures.length} row(s))');

          // 3. After the failure, a good extension loads cleanly again.
          final File goodFile = await _writeProbe(
            _extensionSource,
            'probe_recovery.js',
          );
          await manager.uninstall('device.verify.probe');
          await manager.importExtension(filePath: goodFile.path);
          final SpectaResult<ExtensionRuntime> recovery =
              await manager.loadRuntime('device.verify.probe');
          expect(recovery.isOk, isTrue,
              reason: 'recovery load failed: ${recovery.failureOrNull}');
          _log('isolation', 'fresh sandbox loads cleanly after a failed load');

          await manager.shutdown('device.verify.probe');
          await manager.uninstall('device.verify.probe');
          hostApi.dispose();
        });
      },
    );
  });
}
