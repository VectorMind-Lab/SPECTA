import 'dart:async';
import 'dart:convert';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

import 'package:specta/core/extensions/contract/extension_capability.dart';
import 'package:specta/core/extensions/contract/extension_capabilities.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/extensions/contract/extension_contract.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

import 'runtime_api.dart';

/// Bootstrap JavaScript injected into every extension sandbox.
///
/// Defines the `SpectaExtension` base class that extension code extends.
/// Its only routes out of the sandbox are `request` (controlled host network
/// access) and `log`; there is no filesystem, database, contact, SMS or
/// device-identifier API for extension code to reach.
///
/// Contract note: [ExtensionRuntime.loadExtension] instantiates a class named
/// `Extension` (`new Extension()`), so an extension must declare that class.
/// Extending `SpectaExtension` is what gives it `request`/`log`, but the
/// runtime does not verify the base class — it verifies declared
/// capabilities, which is why they are declared explicitly rather than
/// inferred from the presence of a JavaScript method.
const String sandboxBootstrap = r'''
class SpectaExtension {
  async request(requestData) {
    const response = await sendMessage('specta_request', JSON.stringify(requestData));
    return JSON.parse(response);
  }
  log(level, message) {
    sendMessage('specta_log', JSON.stringify({level: level, message: message}));
  }
  async load() {}
  async capabilities() { return {}; }
  async healthCheck() { return true; }
  async shutdown() {}
}
''';

/// Manages a single extension's JavaScript sandbox lifecycle.
///
/// The [ExtensionRuntime] owns:
/// * sandbox initialisation with the bootstrap base class
/// * evaluation of extension code
/// * mapping contract operations to JS method calls
/// * failure isolation — a JS crash never crashes SPECTA
/// * controlled shutdown
///
/// Capability enforcement lives here. [capabilities] is the set the extension
/// declared in its manifest; the runtime grants nothing outside it. The host
/// channels are registered unconditionally but check the set on every call, so
/// an undeclared capability produces an immediate, structured refusal instead of
/// a message that silently disappears.
///
/// Extensions cannot access the sandbox directly; all calls go through the
/// typed operation methods which return [SpectaResult].
class ExtensionRuntime {
  ExtensionRuntime({
    required this._sandbox,
    required this._api,
    this._capabilities = const <ExtensionCapability>{},
  });

  final ExtensionJsSandbox _sandbox;
  final ExtensionRuntimeApi _api;
  final Set<ExtensionCapability> _capabilities;

  /// The capabilities this runtime will honour. Empty by default.
  Set<ExtensionCapability> get grantedCapabilities =>
      Set<ExtensionCapability>.unmodifiable(_capabilities);

  /// Whether the extension declared [capability].
  bool isGranted(ExtensionCapability capability) =>
      _capabilities.contains(capability);

  bool _loaded = false;
  String? _extensionId;
  bool get isLoaded => _loaded;

  /// Default timeout for individual JS operations.
  static const Duration defaultOperationTimeout = Duration(seconds: 30);

  /// Name of the extension instance inside the sandbox's global scope.
  static const String _instanceName = '_spectaInstance';

  /// Bootstraps the sandbox, injects the runtime API, loads the extension
  /// code, and calls `load()`.
  Future<SpectaResult<void>> loadExtension({
    required String extensionId,
    required String jsCode,
  }) async {
    _extensionId = extensionId;

    if (!_sandbox.isReady) {
      try {
        await _sandbox.init();
      } catch (e) {
        return Err<void>(
          _runtimeFailure(
            type: ExtensionFailureType.runtimeError,
            message: 'Failed to initialise JS sandbox',
            detail: e.toString(),
            operation: 'load',
          ),
        );
      }
    }

    _sandbox.onMessage('specta_request', _onRequest);
    _sandbox.onMessage('specta_log', _onLog);

    try {
      await _sandbox.evaluate(sandboxBootstrap);
    } catch (e) {
      return Err<void>(
        _runtimeFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Failed to inject sandbox bootstrap',
          detail: e.toString(),
          operation: 'load',
        ),
      );
    }

    // Every step below catches Object, not just JsEvalException: the sandbox
    // contract permits any Dart exception to escape a native JS engine, and an
    // uncaught one would propagate out of the manager into the UI layer. That
    // would break the invariant that a failing extension never takes SPECTA
    // down with it.
    try {
      await _sandbox.evaluate(jsCode);
    } catch (e) {
      return Err<void>(
        _runtimeFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Extension failed to load',
          detail: _describe(e),
          operation: 'load',
        ),
      );
    }

    // Creating the instance and calling load() are two calls on purpose. The
    // declaration is a statement, so it goes through the synchronous evaluator
    // and lands in the sandbox's global scope where the operation expressions
    // below can reach it. load() must be awaited, and an awaited call is an
    // expression, which the async evaluator requires.
    try {
      await _sandbox.evaluate('var $_instanceName = new Extension();');
    } catch (e) {
      return Err<void>(
        _runtimeFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Extension failed to instantiate',
          detail: _describe(e),
          operation: 'load',
        ),
      );
    }

    try {
      await _sandbox
          .evaluateAsync('await $_instanceName.load();')
          .timeout(defaultOperationTimeout);
    } catch (e) {
      return Err<void>(
        _runtimeFailure(
          type: e is TimeoutException
              ? ExtensionFailureType.timeout
              : ExtensionFailureType.runtimeError,
          message: 'Extension load() failed',
          detail: _describe(e),
          operation: 'load',
        ),
      );
    }

    _loaded = true;
    return const Ok<void>(null);
  }

  /// Calls the extension's `capabilities()` operation.
  ///
  /// Never capability-gated: a required contract operation that reports what
  /// the extension offers is how a caller discovers what to ask for, so gating
  /// it would make the rest unreachable.
  Future<SpectaResult<ExtensionCapabilities>> capabilities() async {
    return _callOperation<ExtensionCapabilities>(
      operation: ExtensionOperation.capabilities,
      jsExpression: 'JSON.stringify(await _spectaInstance.capabilities())',
      parse: (String result) => ExtensionCapabilities.fromJson(
        jsonDecode(result) as Map<String, dynamic>,
      ),
    );
  }

  /// Calls the extension's `search(query, page)` operation.
  Future<SpectaResult<List<SearchResult>>> search({
    required String query,
    required int page,
  }) async {
    final String escapedQuery = jsonEncode(query);
    return _callOperation<List<SearchResult>>(
      operation: ExtensionOperation.search,
      requiredCapability: ExtensionCapability.search,
      jsExpression:
          'JSON.stringify(await _spectaInstance.search($escapedQuery, $page))',
      parse: (String result) {
        final List<dynamic> json = jsonDecode(result) as List<dynamic>;
        return json
            .map(
              (dynamic item) => SearchResult(
                title: (item as Map<String, dynamic>)['title'] as String,
                url: item['url'] as String,
                type:
                    MediaType.fromCode(item['type'] as String?) ??
                    MediaType.movie,
                cover: item['cover'] as String?,
                year: item['year'] as int?,
              ),
            )
            .toList();
      },
    );
  }

  /// Calls the extension's `latest(page)` operation.
  Future<SpectaResult<List<SearchResult>>> latest({required int page}) async {
    return _callOperation<List<SearchResult>>(
      operation: ExtensionOperation.latest,
      requiredCapability: ExtensionCapability.latest,
      jsExpression: 'JSON.stringify(await _spectaInstance.latest($page))',
      parse: (String result) {
        final List<dynamic> json = jsonDecode(result) as List<dynamic>;
        return json
            .map(
              (dynamic item) => SearchResult(
                title: (item as Map<String, dynamic>)['title'] as String,
                url: item['url'] as String,
                type:
                    MediaType.fromCode(item['type'] as String?) ??
                    MediaType.movie,
                cover: item['cover'] as String?,
                year: item['year'] as int?,
              ),
            )
            .toList();
      },
    );
  }

  /// Calls the extension's `details(url)` operation.
  Future<SpectaResult<MediaDetails>> details({required String url}) async {
    final String escapedUrl = jsonEncode(url);
    return _callOperation<MediaDetails>(
      operation: ExtensionOperation.details,
      requiredCapability: ExtensionCapability.details,
      jsExpression:
          'JSON.stringify(await _spectaInstance.details($escapedUrl))',
      parse: (String result) {
        final Map<String, dynamic> json =
            jsonDecode(result) as Map<String, dynamic>;
        return MediaDetails(
          id: json['id'] as String,
          title: json['title'] as String,
          type: MediaType.fromCode(json['type'] as String?) ?? MediaType.movie,
          url: json['url'] as String,
          originalTitle: json['originalTitle'] as String?,
          cover: json['cover'] as String?,
          backdrop: json['backdrop'] as String?,
          year: json['year'] as int?,
          description: json['description'] as String?,
          genres:
              (json['genres'] as List<dynamic>?)?.cast<String>() ?? <String>[],
          durationSeconds: json['duration'] as int?,
          rating: json['rating'] as double?,
          status: json['status'] != null
              ? SeriesStatus.fromCode(json['status'] as String)
              : null,
          seasons:
              (json['seasons'] as List<dynamic>?)
                  ?.map(
                    (dynamic s) => MediaSeason(
                      seasonNumber:
                          (s as Map<String, dynamic>)['seasonNumber'] as int,
                      title: s['title'] as String?,
                      episodes: (s['episodes'] as List<dynamic>? ?? <dynamic>[])
                          .map(
                            (dynamic e) => MediaEpisode(
                              episodeNumber:
                                  (e as Map<String, dynamic>)['episodeNumber']
                                      as int,
                              title: e['title'] as String?,
                              url: e['url'] as String,
                              description: e['description'] as String?,
                              cover: e['cover'] as String?,
                              durationSeconds: e['duration'] as int?,
                            ),
                          )
                          .toList(),
                    ),
                  )
                  .toList() ??
              <MediaSeason>[],
        );
      },
    );
  }

  /// Calls the extension's `getSources(reference)` operation.
  Future<SpectaResult<List<ExtensionSource>>> getSources({
    required String reference,
  }) async {
    final String escapedRef = jsonEncode(reference);
    return _callOperation<List<ExtensionSource>>(
      operation: ExtensionOperation.getSources,
      requiredCapability: ExtensionCapability.sources,
      jsExpression:
          'JSON.stringify(await _spectaInstance.getSources($escapedRef))',
      parse: (String result) {
        final List<dynamic> json = jsonDecode(result) as List<dynamic>;
        return json
            .map(
              (dynamic item) =>
                  ExtensionSource.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      },
    );
  }

  /// Calls the extension's `refreshSource(reference)` operation.
  Future<SpectaResult<ExtensionSource>> refreshSource({
    required String reference,
  }) async {
    final String escapedRef = jsonEncode(reference);
    return _callOperation<ExtensionSource>(
      operation: ExtensionOperation.refreshSource,
      requiredCapability: ExtensionCapability.sources,
      jsExpression:
          'JSON.stringify(await _spectaInstance.refreshSource($escapedRef))',
      parse: (String result) =>
          ExtensionSource.fromJson(jsonDecode(result) as Map<String, dynamic>),
    );
  }

  /// Calls the extension's `healthCheck()` operation.
  ///
  /// Never capability-gated: liveness probing must stay available so a caller
  /// can distinguish a failing extension from one that was not permitted to
  /// answer.
  Future<SpectaResult<bool>> healthCheck() async {
    return _callOperation<bool>(
      operation: ExtensionOperation.healthCheck,
      jsExpression: 'JSON.stringify(await _spectaInstance.healthCheck())',
      parse: (String result) => jsonDecode(result) as bool,
    );
  }

  /// Calls the extension's `shutdown()` operation and disposes the sandbox.
  ///
  /// Dispose always runs, even when the extension code never loaded: a runtime
  /// whose load failed still holds a live JS engine, and only [dispose] frees
  /// it.
  Future<void> shutdown() async {
    if (_loaded) {
      try {
        await _sandbox
            .evaluateAsync('await _spectaInstance.shutdown();')
            .timeout(defaultOperationTimeout);
      } catch (_) {}
      _loaded = false;
    }

    await _sandbox.dispose();
  }

  /// Generic operation caller with capability gating and failure isolation.
  Future<SpectaResult<T>> _callOperation<T>({
    required ExtensionOperation operation,
    required String jsExpression,
    required T Function(String result) parse,
    ExtensionCapability? requiredCapability,
  }) async {
    if (!_loaded) {
      return Err<T>(
        _runtimeFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Extension runtime is not loaded',
          operation: operation.name,
        ),
      );
    }

    if (requiredCapability != null && !isGranted(requiredCapability)) {
      // A declared capability is the only way to reach this operation.
      return Err<T>(
        capabilityDeniedFailure(
          extensionId: _extensionId ?? 'unknown',
          capability: requiredCapability,
          operation: operation.name,
        ),
      );
    }

    try {
      final String result = await _sandbox
          .evaluateAsync(jsExpression)
          .timeout(defaultOperationTimeout);
      return Ok<T>(parse(result));
    } on JsEvalException catch (e) {
      return Err<T>(
        _runtimeFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'JS evaluation failed for ${operation.name}',
          detail: e.detail ?? e.message,
          operation: operation.name,
        ),
      );
    } on TimeoutException {
      return Err<T>(
        _runtimeFailure(
          type: ExtensionFailureType.timeout,
          message: 'Operation timed out: ${operation.name}',
          operation: operation.name,
        ),
      );
    } catch (e) {
      return Err<T>(
        _runtimeFailure(
          type: ExtensionFailureType.runtimeError,
          message: 'Unexpected error in ${operation.name}',
          detail: e.toString(),
          operation: operation.name,
        ),
      );
    }
  }

  /// Handler for JS `sendMessage('specta_request', ...)`.
  ///
  /// Never throws. A malformed request from the extension and a failure inside
  /// the host's [ExtensionRuntimeApi.request] both degrade to the same
  /// structured error payload, so a host network error cannot escape as an
  /// unhandled Dart exception or as an unhelpful promise rejection in JS.
  Future<String> _onRequest(dynamic args) async {
    if (!isGranted(ExtensionCapability.network)) {
      // Refused before the payload is even parsed: a capability that was never
      // declared must not be reachable, malformed payload or not.
      return jsonEncode(
        ExtensionResponse(
          status: null,
          ok: false,
          errorType: ExtensionFailureType.capabilityError.code,
          error:
              'CAPABILITY_ERROR: this extension did not declare the "network" '
              'capability, so request() is unavailable.',
        ).toMap(),
      );
    }

    try {
      final Map<String, dynamic> data = _decodePayload(args);
      final ExtensionRequest request = ExtensionRequest(
        url: data['url'] as String,
        method: (data['method'] as String?)?.toUpperCase() ?? 'GET',
        headers: Map<String, String>.from(
          data['headers'] ?? <String, String>{},
        ),
        queryParameters: Map<String, String>.from(
          data['query'] ?? <String, String>{},
        ),
        body: data['body'] as String?,
        timeout: Duration(milliseconds: data['timeout'] as int? ?? 15000),
      );
      final ExtensionResponse response = await _api.request(request);
      return jsonEncode(response.toMap());
    } catch (e) {
      return jsonEncode(
        ExtensionResponse(
          status: null,
          ok: false,
          errorType: ExtensionFailureType.runtimeError.code,
          error: 'Request failed: $e',
        ).toMap(),
      );
    }
  }

  /// Handler for JS `sendMessage('specta_log', ...)`.
  ///
  /// Dropped, not refused, when `logging` was not declared: logging has no host
  /// side effect, so a silent no-op is the correct refusal. The message never
  /// reaches the host sink.
  void _onLog(dynamic args) {
    if (!isGranted(ExtensionCapability.logging)) return;

    try {
      final Map<String, dynamic> data = _decodePayload(args);
      final String levelStr = data['level'] as String? ?? 'info';
      final ExtensionLogLevel level = ExtensionLogLevel.values.firstWhere(
        (ExtensionLogLevel e) => e.code == levelStr,
        orElse: () => ExtensionLogLevel.info,
      );
      _api.log(level, data['message'] as String? ?? '');
    } catch (_) {}
  }

  /// Normalises a host-channel payload.
  ///
  /// flutter_js json-decodes the message *before* it invokes the registered
  /// handler, so the real engine delivers a `Map`. A `String` is accepted too so
  /// the same handler stays drivable directly. This is not a nicety: assuming a
  /// String here meant every `request()` and `log()` call from real JavaScript
  /// failed before it reached the host API, which no fake-sandbox test could
  /// reveal.
  static Map<String, dynamic> _decodePayload(dynamic args) {
    if (args is Map) return Map<String, dynamic>.from(args);
    if (args is String) {
      final dynamic decoded = jsonDecode(args);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('Channel payload is not a JSON object');
    }
    throw FormatException(
      'Unsupported channel payload type: ${args.runtimeType}',
    );
  }

  /// Formats an arbitrary sandbox exception for developer-only diagnostics.
  static String _describe(Object error) => error is JsEvalException
      ? (error.detail ?? error.message)
      : error.toString();

  ExtensionFailure _runtimeFailure({
    required ExtensionFailureType type,
    required String message,
    String? detail,
    required String operation,
  }) {
    final String extId = _extensionId ?? 'unknown';
    return ExtensionFailure(
      extensionId: extId,
      operation: operation,
      type: type,
      message: message,
      timestamp: DateTime.now().toUtc(),
      detail: detail,
    );
  }
}
