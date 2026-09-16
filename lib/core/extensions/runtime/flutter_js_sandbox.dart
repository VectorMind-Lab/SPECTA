import 'dart:async';

import 'package:flutter_js/flutter_js.dart';

import 'runtime_api.dart';

/// Real [ExtensionJsSandbox] backed by flutter_js (QuickJS on Android,
/// JavaScriptCore on iOS).
///
/// Boundary — what this actually enforces (verified against flutter_js 0.8.7):
/// * The engine is created as a bare `QuickJsRuntime2`. No native API bindings
///   are registered, so JavaScript sees no DOM, no filesystem, no `process` and
///   no platform objects.
/// * `enableFetch()` is never called (flutter_js only wires `fetch`/`XHR` when
///   the host asks for it), so extension code cannot reach the network except
///   through the controlled `request()` channel.
/// * The only bridge into Dart is the registered `sendMessage` channels, and
///   [ExtensionRuntime] registers exactly two: `specta_request` and `specta_log`.
///   Messages on any other channel have no handler and are dropped.
/// * Every evaluation is wrapped in try/catch; JS exceptions become
///   [JsEvalException] so the host application never crashes.
///
/// What this does NOT provide:
/// * It is not an OS-level sandbox. Extension JavaScript runs inside the SPECTA
///   process; the boundary is the absence of bindings, not process isolation.
/// * **No CPU-time or memory ceiling is enforced.** This is a measured finding,
///   not an assumption; it was probed directly against the shipped engine
///   (flutter_js 0.8.7, QuickJS bridge):
///   - `QuickJsRuntime2(memoryLimit: n)` does not apply a limit: the bundled
///     bridge does not export `jsSetMemoryLimit`, so the option is accepted and
///     ignored.
///   - `QuickJsRuntime2(timeout: n)` does not interrupt a synchronous runaway
///     loop (`while (true) {}` ran past the timeout and had to be killed), and
///     it also mis-fires on `await`-driven code, aborting promises that were
///     still progressing. This build therefore sets neither option.
///
///   The only limit that exists is the Dart-side `Future.timeout` in
///   [ExtensionRuntime], which bounds *awaited* operations but cannot interrupt
///   a synchronous CPU-bound JS loop. A malicious or buggy extension can
///   therefore still occupy the Dart isolate until it finishes. Budgeting CPU
///   time would need either platform-level isolation or a bridge that supports
///   interrupting evaluation, and is out of scope for Phase 1.
class FlutterJsSandbox extends ExtensionJsSandbox {
  FlutterJsSandbox([JavascriptRuntime? runtime])
    : _provided = runtime,
      _runtime = runtime ?? _createDefaultRuntime();

  /// An engine supplied by the caller, if any. Rebuilt from the default factory
  /// when absent, so a sandbox can be re-initialised after disposal.
  final JavascriptRuntime? _provided;

  JavascriptRuntime _runtime;
  bool _disposed = false;

  static JavascriptRuntime _createDefaultRuntime() {
    final JavascriptRuntime runtime = QuickJsRuntime2(stackSize: 1024 * 1024);
    runtime.enableHandlePromises();
    return runtime;
  }

  @override
  bool get isReady => !_disposed;

  @override
  bool get isDisposed => _disposed;

  /// Prepares the engine, rebuilding it if a previous [dispose] closed it.
  ///
  /// A closed QuickJS runtime cannot be reopened, so re-initialisation means
  /// creating a fresh one. Without this, a second `loadExtension` on the same
  /// runtime silently failed on the real engine — something the fake sandbox
  /// could not show, because its `init` just flips a flag.
  @override
  Future<void> init() async {
    if (_disposed) {
      _runtime = _provided ?? _createDefaultRuntime();
      _disposed = false;
    }
    _runtime.enableHandlePromises();
  }

  @override
  void onMessage(String channel, JsMessageHandler handler) {
    if (_disposed) return;
    _runtime.onMessage(channel, handler);
  }

  @override
  Future<String> evaluate(String code) async {
    final JsEvalResult result = _runtime.evaluate(code);
    if (result.isError) {
      throw JsEvalException('JS evaluation error', detail: result.stringResult);
    }
    return result.stringResult;
  }

  /// Evaluates [expression], which may use `await`.
  ///
  /// The expression is wrapped in an async IIFE before it reaches the engine.
  /// This is required, not cosmetic: QuickJS evaluates in *script* mode, where a
  /// top-level `await` is a syntax error, so the natural expression form the
  /// runtime uses (`JSON.stringify(await _spectaInstance.search(...))`) would
  /// never run. Inside an async function it is valid, and the IIFE's return
  /// value is the promise that [handlePromise] then resolves.
  ///
  /// [expression] must therefore be an expression, not a statement list.
  @override
  Future<String> evaluateAsync(String expression) async {
    final JsEvalResult result = await _runtime.evaluateAsync(
      '(async () => { return $expression; })()',
    );

    JsEvalResult resolved = result;
    if (!resolved.isError && _isBridgedPromise(resolved)) {
      resolved = await _resolveBridgedPromise(resolved);
    }

    if (resolved.isError) {
      throw JsEvalException(
        'JS evaluation error',
        detail: resolved.stringResult,
      );
    }
    return resolved.stringResult;
  }

  /// Whether flutter_js handed back a Dart [Future] standing in for a JS promise.
  ///
  /// flutter_js's `handlePromise` identifies this case by exactly this placeholder
  /// text, so the check is the package's own, not a guess. Note that
  /// [JsEvalResult.isPromise] is **never** set by the QuickJS runtime
  /// (`evaluate` does not pass it through), which is why it cannot be used.
  static bool _isBridgedPromise(JsEvalResult result) =>
      result.stringResult.contains("Instance of 'Future");

  /// Resolves a promise-bridged result, propagating rejection as a
  /// [JsEvalException].
  ///
  /// `handlePromise` is deliberately not used for the resolution itself: it
  /// attaches only a success callback, so a rejected extension promise never
  /// completes it and the await would never return. Its `executePendingJob`
  /// pump is still started, because that is what drains the engine's job queue
  /// while the promise settles.
  Future<JsEvalResult> _resolveBridgedPromise(JsEvalResult result) async {
    final dynamic raw = result.rawResult;
    if (raw is! Future<dynamic>) {
      // The engine reported the placeholder text without a bridged future. Ask
      // flutter_js to handle it, and fail loudly if it cannot.
      final JsEvalResult handled = await _runtime.handlePromise(result);
      if (handled.isError) return handled;
      return JsEvalResult(handled.stringResult, handled.rawResult);
    }

    final Future<JsEvalResult> pump = _runtime.handlePromise(result);
    // The pump only ever completes on success; stop it being an unhandled error
    // when it never completes at all.
    unawaited(
      pump.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      ),
    );

    final dynamic value;
    try {
      value = await raw;
    } catch (e) {
      throw JsEvalException('JS promise rejected', detail: e.toString());
    }
    return JsEvalResult(value?.toString() ?? 'null', value);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _runtime.dispose();
  }
}
