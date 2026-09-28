@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/extension_capabilities.dart';
import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/runtime/controlled_runtime_api.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';
import 'package:specta/core/extensions/runtime/flutter_js_sandbox.dart';
import 'package:specta/core/extensions/runtime/request_policy.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

/// These tests execute REAL JavaScript through the shipped [FlutterJsSandbox]
/// (flutter_js → QuickJS). They exist because every other runtime test uses a
/// fake sandbox, which by construction cannot prove that the real bridge decodes
/// payloads the way the runtime expects.
///
/// Environment requirement:
///  * On Windows, flutter_js loads `quickjs_c_bridge.dll`. That DLL ships inside
///    the pub cache (`flutter_js-<version>/windows/shared`) but is only found if
///    it is on the process loader path, so these tests need
///    `tool/run_tests_real_js.sh` (or that directory on `PATH`).
///  * On a real device the plugin packages `libfastdev_quickjs_runtime.so` inside
///    the APK, so the engine is present without any extra setup.
///
/// When the bridge cannot be loaded the group is SKIPPED with the reason below.
/// Skipped is reported honestly as "not verified in this environment"; it is
/// never reported as passing.
String? _engineSkipReason() {
  if (!Platform.isWindows) {
    // macOS/Linux/Android resolve the bridge through the plugin build or
    // DynamicLibrary.process(); a failure there surfaces as a normal failure.
    return null;
  }
  try {
    final DynamicLibrary bridge = DynamicLibrary.open('quickjs_c_bridge.dll');
    if (!bridge.providesSymbol('jsNewRuntime')) {
      return 'quickjs_c_bridge.dll was found but does not export jsNewRuntime.';
    }
    return null;
  } on Object catch (e) {
    return 'The flutter_js QuickJS bridge is not loadable in this process '
        '($e). On Windows it must be on the loader path; run '
        'tool/run_tests_real_js.sh. On Android it is shipped inside the APK and '
        'needs a device or emulator. Real-engine sandbox verification is '
        'therefore PENDING here; the fake-sandbox tests still run.';
  }
}

/// A minimal, well-formed extension. `log()` and `request()` are inherited from
/// the injected `SpectaExtension` bootstrap.
const String _extensionSource = '''
class Extension extends SpectaExtension {
  async load() {}
  async capabilities() {
    return {
      contentTypes: ['movie'],
      discovery: {search: true, latest: false},
      metadata: {details: true},
      sources: {mp4: true, hls: true},
    };
  }
  async healthCheck() { return true; }
  async logFromJs() { this.log('info', 'hello from js'); return 'logged'; }
  async requestFromJs() {
    return await this.request({url: 'https://example.com/api'});
  }
  async boom() { throw new Error('kaboom'); }
  async badShape() { return 'not-an-object'; }
}
''';

class RecordingTransport implements ExtensionHttpTransport {
  int calls = 0;
  Uri? lastUri;
  String? lastMethod;
  Map<String, String> lastHeaders = <String, String>{};

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
    lastMethod = method;
    lastHeaders = headers;
    return const ExtensionHttpResult(
      statusCode: 200,
      headers: <String, String>{'content-type': 'application/json'},
      body: '{"ok":true,"value":7}',
    );
  }
}

class RecordingLogSink {
  final List<String> messages = <String>[];

  void call(ExtensionLogLevel level, String message) {
    messages.add('${level.code}:$message');
  }
}

void main() {
  final String? skip = _engineSkipReason();

  group('FlutterJsSandbox — real QuickJS engine', () {
    test('initialises and evaluates JavaScript', () async {
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      await sandbox.init();

      expect(await sandbox.evaluate('1+1'), '2');
      expect(await sandbox.evaluate('"a"+"b"'), 'ab');
      expect(await sandbox.evaluateAsync('await Promise.resolve(40+2)'), '42');

      await sandbox.dispose();
      expect(sandbox.isReady, isFalse);
    });

    test('exposes no ambient host APIs to extension code', () async {
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      await sandbox.init();

      // The engine, as SPECTA configures it, must not provide the usual escape
      // hatches. This is the actual evidence for that claim.
      final String types = await sandbox.evaluate(
        '[typeof fetch, typeof XMLHttpRequest, typeof require, typeof process, '
        'typeof Dart, typeof window, typeof document].join(",")',
      );
      expect(
        types,
        'undefined,undefined,undefined,undefined,undefined,'
        'undefined,undefined',
      );

      // The one bridge that does exist is the registered message channel.
      expect(await sandbox.evaluate('typeof sendMessage'), 'function');

      await sandbox.dispose();
    });

    test('loads an extension and reports its capabilities', () async {
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: _hostApi().api,
        capabilities: ExtensionCapability.values.toSet(),
      );

      final SpectaResult<void> load = await runtime.loadExtension(
        extensionId: 'real-engine',
        jsCode: _extensionSource,
      );
      expect(load.isOk, isTrue, reason: 'load failed: ${load.failureOrNull}');

      final SpectaResult<ExtensionCapabilities> capabilities = await runtime
          .capabilities();
      expect(capabilities.isOk, isTrue);
      expect(capabilities.valueOrNull!.search, isTrue);
      expect(capabilities.valueOrNull!.details, isTrue);
      expect(capabilities.valueOrNull!.hlsSources, isTrue);

      await runtime.shutdown();
    });

    test('log() from JavaScript reaches the host sink', () async {
      final _HostApi host = _hostApi();
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: host.api,
        capabilities: ExtensionCapability.values.toSet(),
      );
      await runtime.loadExtension(
        extensionId: 'real-engine',
        jsCode: _extensionSource,
      );

      await sandbox.evaluateAsync('await _spectaInstance.logFromJs()');

      expect(host.logs.messages, contains('info:hello from js'));

      await runtime.shutdown();
    });

    test('request() round-trips through the controlled API', () async {
      final RecordingTransport transport = RecordingTransport();
      // §37.5 (2G-C pre-flight): test-only policy — example.com is never
      // resolved here and no host rules run; production keeps blocking ON.
      final ControlledExtensionRuntimeApi controller =
          ControlledExtensionRuntimeApi(
            transport: transport,
            policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
          );
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: controller,
        capabilities: ExtensionCapability.values.toSet(),
      );
      await runtime.loadExtension(
        extensionId: 'real-engine',
        jsCode: _extensionSource,
      );

      final String raw = await sandbox.evaluateAsync(
        'JSON.stringify(await _spectaInstance.requestFromJs())',
      );
      final Map<String, dynamic> received =
          jsonDecode(raw) as Map<String, dynamic>;

      expect(transport.calls, 1);
      expect(transport.lastUri.toString(), 'https://example.com/api');
      expect(transport.lastMethod, 'GET');
      expect(received['status'], 200);
      expect(received['ok'], isTrue);
      expect((received['json'] as Map<String, dynamic>)['value'], 7);

      await runtime.shutdown();
    });

    test(
      'an undeclared network capability is refused without a request',
      () async {
        final RecordingTransport transport = RecordingTransport();
        // §37.5 (2G-C pre-flight): test-only policy (see the request test).
        final ControlledExtensionRuntimeApi controller =
            ControlledExtensionRuntimeApi(
              transport: transport,
              policy: const ExtensionRequestPolicy(blockPrivateHosts: false),
            );
        final FlutterJsSandbox sandbox = FlutterJsSandbox();
        final ExtensionRuntime runtime = ExtensionRuntime(
          sandbox: sandbox,
          api: controller,
          // logging only: network is not declared.
          capabilities: const <ExtensionCapability>{
            ExtensionCapability.logging,
          },
        );
        await runtime.loadExtension(
          extensionId: 'real-engine',
          jsCode: _extensionSource,
        );

        final String raw = await sandbox.evaluateAsync(
          'JSON.stringify(await _spectaInstance.requestFromJs())',
        );
        final Map<String, dynamic> received =
            jsonDecode(raw) as Map<String, dynamic>;

        expect(received['ok'], isFalse);
        expect(received['errorType'], 'CAPABILITY_ERROR');
        expect(transport.calls, 0, reason: 'no network activity may happen');

        await runtime.shutdown();
      },
    );

    test('a JavaScript exception becomes a controlled failure', () async {
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: _hostApi().api,
        capabilities: ExtensionCapability.values.toSet(),
      );
      await runtime.loadExtension(
        extensionId: 'real-engine',
        jsCode: _extensionSource,
      );

      Object? escaped;
      try {
        await sandbox.evaluateAsync('await _spectaInstance.boom()');
      } catch (e) {
        escaped = e;
      }
      expect(escaped, isA<JsEvalException>());

      await runtime.shutdown();
    });

    test(
      'malformed JavaScript fails the load as a controlled failure',
      () async {
        final FlutterJsSandbox sandbox = FlutterJsSandbox();
        final ExtensionRuntime runtime = ExtensionRuntime(
          sandbox: sandbox,
          api: _hostApi().api,
          capabilities: ExtensionCapability.values.toSet(),
        );

        final SpectaResult<void> load = await runtime.loadExtension(
          extensionId: 'real-engine',
          jsCode: 'class Extension extends SpectaExtension { this is not js }',
        );

        expect(load.isErr, isTrue);
        expect(load.failureOrNull, isA<ExtensionFailure>());
        expect(runtime.isLoaded, isFalse);

        await runtime.shutdown();
        expect(sandbox.isDisposed, isTrue);
      },
    );

    test('shutdown disposes and the same runtime reloads cleanly', () async {
      final FlutterJsSandbox sandbox = FlutterJsSandbox();
      final ExtensionRuntime runtime = ExtensionRuntime(
        sandbox: sandbox,
        api: _hostApi().api,
        capabilities: ExtensionCapability.values.toSet(),
      );

      for (int i = 0; i < 3; i++) {
        final SpectaResult<void> load = await runtime.loadExtension(
          extensionId: 'real-engine',
          jsCode: _extensionSource,
        );
        expect(load.isOk, isTrue, reason: 'load $i failed');
        expect(runtime.isLoaded, isTrue);

        final SpectaResult<bool> healthy = await runtime.healthCheck();
        expect(healthy.valueOrNull, isTrue);

        await runtime.shutdown();
        expect(runtime.isLoaded, isFalse);
      }
    });
  }, skip: skip);
}

_HostApi _hostApi() {
  final RecordingLogSink logs = RecordingLogSink();
  return _HostApi(RecordingHostApi(logs), logs);
}

final class _HostApi {
  _HostApi(this.api, this.logs);

  final ExtensionRuntimeApi api;
  final RecordingLogSink logs;
}

/// Minimal host API for the tests that only need log/request to exist.
class RecordingHostApi implements ExtensionRuntimeApi {
  RecordingHostApi(this.logs);

  final RecordingLogSink logs;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    return const ExtensionResponse(status: 200, ok: true, body: '{"ok":true}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {
    logs.call(level, message);
  }
}
