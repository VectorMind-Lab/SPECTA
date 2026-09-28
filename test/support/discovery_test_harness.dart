import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specta/core/extensions/identity/trust_level.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/extensions/manager/extension_record.dart';
import 'package:specta/core/extensions/manager/in_memory_extension_registry.dart';
import 'package:specta/core/extensions/runtime/runtime_api.dart';

import 'fake_js_sandbox.dart';

export 'fake_js_sandbox.dart';

/// A [FakeJsSandbox] that serves a scripted sequence of outcomes for the
/// `search` operation — one entry per search call, in call order.
///
/// Needed because every extension's search call uses the same JS expression
/// (the query is embedded in it, but one round issues one call per extension),
/// and per-call scripting lets a single round contain mixed outcomes
/// (success, timeout, runtime error). Tests never assume WHICH extension got
/// WHICH script entry: runtimes load concurrently, so call order across
/// extensions is not deterministic — the pipeline's guarantees are aggregate
/// (results survive isolation), and tests assert on aggregates.
class ScriptedJsSandbox extends FakeJsSandbox {
  ScriptedJsSandbox();

  /// Entries consumed by successive search calls. A `String` is served as the
  /// call result; any other Object is THROWN (e.g. [TimeoutException],
  /// [JsEvalException]). Entries beyond the list fall through to the normal
  /// fake behavior. Mutable so tests can configure it after construction.
  List<Object> searchScripts = <Object>[];

  /// Entries consumed by successive `latest` calls (the Home feed round).
  /// Same contract as [searchScripts].
  List<Object> latestScripts = <Object>[];

  /// When non-zero, search calls delay this long before answering — a slow
  /// extension. Only applies to calls whose index is in [hangOnCallIndices].
  /// Combine with a short coordinator timeout override to exercise the
  /// coordinator's own timeout deterministically.
  Duration hangDuration = Duration.zero;

  /// Which search-call indices (0-based, in call arrival order) hang for
  /// [hangDuration] before answering. Other calls answer immediately.
  Set<int> hangOnCallIndices = <int>{};

  int _searchCalls = 0;
  int _latestCalls = 0;

  /// Number of search calls that reached the sandbox so far. Lets tests wait
  /// for a round to actually reach the extension layer before proceeding.
  int get searchCallCount => _searchCalls;

  /// Number of `latest` calls that reached the sandbox so far.
  int get latestCallCount => _latestCalls;

  @override
  Future<String> evaluateAsync(String expression) async {
    if (expression.contains('.search(')) {
      final int index = _searchCalls++;
      if (hangOnCallIndices.contains(index) && hangDuration > Duration.zero) {
        await Future<void>.delayed(hangDuration);
      }
      if (index < searchScripts.length) {
        final Object step = searchScripts[index];
        if (step is String) return step;
        throw step;
      }
    }
    if (expression.contains('.latest(')) {
      final int index = _latestCalls++;
      if (hangOnCallIndices.contains(index) && hangDuration > Duration.zero) {
        await Future<void>.delayed(hangDuration);
      }
      if (index < latestScripts.length) {
        final Object step = latestScripts[index];
        if (step is String) return step;
        throw step;
      }
    }
    return super.evaluateAsync(expression);
  }
}

/// The exact JS expression the runtime issues for a search call.
String searchExpression(String query, int page) =>
    'JSON.stringify(await _spectaInstance.search("$query", $page))';

/// The exact JS expression the runtime issues for a `latest` call.
String latestExpression(int page) =>
    'JSON.stringify(await _spectaInstance.latest($page))';

/// Builds a JSON search-result payload. Elements are untyped so tests can
/// include malformed rows (bare strings, wrong shapes) for robustness cases.
String searchPayload(List<Object?> items) => jsonEncode(items);

/// Writes a valid Phase 1 extension file declaring [capabilities].
Future<File> writeTestExtension(
  Directory dir, {
  required String id,
  String capabilities = 'search,latest',
}) async {
  final File file = File('${dir.path}/$id.js');
  await file.writeAsString('''
// ==SpectaExtension==
// @id $id
// @name Test Ext $id
// @version 1.0.0
// @author SPECTA Tests
// @apiVersion 2
// @type movie
// @capabilities $capabilities
// ==/SpectaExtension==
class Extension extends SpectaExtension {}
''');
  return file;
}

/// A registry record for a test extension.
ExtensionRecord testRecord(String id, {String? filePath, bool enabled = true}) {
  final DateTime now = DateTime.now().toUtc();
  return ExtensionRecord(
    id: id,
    name: 'Test Ext $id',
    version: '1.0.0',
    author: 'SPECTA Tests',
    apiVersion: 2,
    contentType: 'movie',
    signature: null,
    trustLevel: TrustLevel.unverified,
    enabled: enabled,
    filePath: filePath ?? '/fake/path.js',
    installedAt: now,
    updatedAt: now,
  );
}

/// Minimal host API: discovery rounds make no network requests, so the API
/// only needs to exist.
class HarnessRuntimeApi implements ExtensionRuntimeApi {
  int requestCount = 0;
  int logCount = 0;

  @override
  Future<ExtensionResponse> request(ExtensionRequest request) async {
    requestCount++;
    return ExtensionResponse(status: 200, ok: true, body: '{}');
  }

  @override
  void log(ExtensionLogLevel level, String message) {
    logCount++;
  }
}

/// Assembles a REAL [ExtensionManager] over an in-memory registry and a fake
/// sandbox — the same construction the Phase 1 manager tests use — so
/// discovery tests exercise the actual load/capability/operation path.
class DiscoveryTestHarness {
  DiscoveryTestHarness({FakeJsSandbox? sandbox})
    : sandbox = sandbox ?? FakeJsSandbox() {
    manager = ExtensionManager(
      registry: registry,
      runtimeApi: HarnessRuntimeApi(),
      sandboxFactory: () => this.sandbox,
    );
  }

  final InMemoryExtensionRegistry registry = InMemoryExtensionRegistry();
  final FakeJsSandbox sandbox;

  late final ExtensionManager manager;

  /// Installs an extension backed by a real file in [dir].
  Future<void> installExtension(
    Directory dir,
    String id, {
    String capabilities = 'search,latest',
    bool enabled = true,
  }) async {
    final File file = await writeTestExtension(
      dir,
      id: id,
      capabilities: capabilities,
    );
    await registry.install(
      testRecord(id, filePath: file.path, enabled: enabled),
    );
  }
}
