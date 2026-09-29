import 'dart:async';
import 'dart:convert';

import 'package:specta/core/extensions/runtime/runtime_api.dart';

/// Fake [ExtensionJsSandbox] for unit tests.
///
/// Does NOT execute JavaScript.  Instead, it returns pre-configured responses
/// for specific expressions, records all evaluations, and simulates errors.
///
/// This lets the [ExtensionRuntime] lifecycle, error-isolation and contract
/// logic be exercised deterministically without a native JS engine.
class FakeJsSandbox extends ExtensionJsSandbox {
  FakeJsSandbox({
    this.initialEvalResult = '',
    this.shouldFailEval = false,
    this.evalErrorMessage = 'Fake JS error',
  });

  bool _isReady = true;

  /// When false, [init] will be called before evaluation.
  set isReady(bool value) => _isReady = value;

  /// Response returned by [evaluate] (non-async expressions).
  final String initialEvalResult;

  /// When true, [evaluate] throws [JsEvalException] with [evalErrorMessage].
  final bool shouldFailEval;

  /// Message for the simulated eval error.
  final String evalErrorMessage;

  /// When true, [init] throws an exception.
  bool shouldFailInit = false;

  /// Configures a non-[JsEvalException] failure for one sync expression.
  ///
  /// Real engines can surface failures that are not modelled as
  /// [JsEvalException] (Dart errors from the FFI binding, for example).  The
  /// runtime must isolate those too, so tests need a way to raise them.
  void setEvalThrow(String expression, Object error) {
    _evalThrows[expression] = error;
  }

  /// Artificial delay applied to [evaluateAsync] to simulate slow JS.
  Duration? delay;

  /// When true, [evaluateAsync] throws [TimeoutException] to simulate a
  /// JS operation that never resolves.
  bool forceTimeout = false;

  /// Whether [dispose] has been called.
  @override
  bool isDisposed = false;

  final Map<String, String> _evalResults = <String, String>{};
  final Map<String, String> _asyncResults = <String, String>{};
  final Map<String, dynamic> _evalErrors = <String, dynamic>{};
  final Map<String, dynamic> _asyncErrors = <String, dynamic>{};
  final Map<String, Object> _evalThrows = <String, Object>{};

  /// All expressions passed to [evaluate], in order.
  final List<String> evalCalls = <String>[];

  /// All expressions passed to [evaluateAsync], in order.
  final List<String> asyncEvalCalls = <String>[];

  /// Calls to [evaluate] that supplied an explicit [evalFlags], in order.
  ///
  /// Deliberately SEPARATE from [evalCalls] rather than replacing it. Every
  /// evaluation is still recorded in [evalCalls]; most call sites pass no flags
  /// at all, so folding the two together would silently break the existing
  /// `.evaluate(...)` assertions this fake already supports.
  final List<(String, int)> evalCallsWithFlags = <(String, int)>[];

  /// Registered message handlers keyed by channel.
  final Map<String, JsMessageHandler> handlers = <String, JsMessageHandler>{};

  /// Configures a canned response for a specific async expression.
  void setAsyncResult(String expression, String result) {
    _asyncResults[expression] = result;
  }

  /// Configures an error response for a specific async expression.
  void setAsyncError(String expression, String message, {String? detail}) {
    _asyncErrors[expression] = <String, dynamic>{
      'message': message,
      'detail': detail,
    };
  }

  /// Configures a canned response for a specific sync expression.
  void setEvalResult(String expression, String result) {
    _evalResults[expression] = result;
  }

  /// Configures an error response for a specific sync expression.
  void setEvalError(String expression, String message, {String? detail}) {
    _evalErrors[expression] = <String, dynamic>{
      'message': message,
      'detail': detail,
    };
  }

  @override
  bool get isReady => _isReady;

  @override
  Future<void> init() async {
    if (shouldFailInit) {
      throw Exception('Failed to initialise JS sandbox');
    }
    _isReady = true;
  }

  @override
  void onMessage(String channel, JsMessageHandler handler) {
    handlers[channel] = handler;
  }

  @override
  Future<String> evaluate(String code, {int? evalFlags}) async {
    // Recorded on every call, flags or not: evalCalls keeps its existing
    // meaning so the assertions already written against it stay valid.
    evalCalls.add(code);
    if (evalFlags != null) {
      evalCallsWithFlags.add((code, evalFlags));
    }
    if (shouldFailEval) {
      throw JsEvalException(evalErrorMessage);
    }
    if (_evalThrows.containsKey(code)) {
      throw _evalThrows[code]!;
    }
    if (_evalErrors.containsKey(code)) {
      final dynamic error = _evalErrors[code]!;
      throw JsEvalException(
        error['message'] as String,
        detail: error['detail'] as String?,
      );
    }
    if (_evalResults.containsKey(code)) {
      return _evalResults[code]!;
    }
    return initialEvalResult;
  }

  @override
  Future<String> evaluateAsync(String expression) async {
    asyncEvalCalls.add(expression);

    if (forceTimeout) {
      await Future<void>.delayed(delay ?? const Duration(seconds: 60));
      throw TimeoutException('Simulated JS timeout', null);
    }

    if (delay != null) {
      await Future<void>.delayed(delay!);
    }

    if (_asyncErrors.containsKey(expression)) {
      final dynamic error = _asyncErrors[expression]!;
      throw JsEvalException(
        error['message'] as String,
        detail: error['detail'] as String?,
      );
    }

    if (_asyncResults.containsKey(expression)) {
      return _asyncResults[expression]!;
    }

    return initialEvalResult;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  /// Simulates a JS extension calling `sendMessage(channel, payload)`.
  ///
  /// The payload is json-decoded before the handler runs, because that is what
  /// flutter_js's real bridge does: it decodes the message and invokes the
  /// handler with the decoded value. A payload that is not JSON is passed
  /// through unchanged so the runtime's own defensive decoding is still
  /// exercised.
  dynamic triggerMessage(String channel, String payload) {
    final JsMessageHandler? handler = handlers[channel];
    if (handler == null) return null;

    dynamic args;
    try {
      args = jsonDecode(payload);
    } on FormatException {
      args = payload;
    }
    return handler(args);
  }

  /// Generates a JSON search result list for [count] items.
  static String searchTextResults(int count) {
    final List<Map<String, dynamic>> items =
        List<Map<String, dynamic>>.generate(
          count,
          (int i) => <String, dynamic>{
            'title': 'Test Movie $i',
            'url': 'https://example.com/movie/$i',
            'type': 'movie',
            'cover': 'https://example.com/cover/$i.jpg',
            'year': 2020 + i,
          },
        );
    return jsonEncode(items);
  }

  /// Generates a JSON capabilities response.
  static String textCapabilities() {
    return jsonEncode(<String, dynamic>{
      'contentTypes': ['movie', 'series'],
      'discovery': {'search': true, 'latest': true},
      'metadata': {'details': true, 'seasons': true, 'episodes': true},
      'sources': {
        'mp4': true,
        'hls': true,
        'dash': false,
        'multipleSources': true,
        'multipleQualities': true,
        'headers': true,
        'subtitles': true,
        'audioTracks': true,
      },
      'downloads': {'supported': false},
      'pagination': {'search': true, 'latest': true},
    });
  }
}
