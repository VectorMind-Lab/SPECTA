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
      parse: (String result) => _parseSearchResults(result),
    );
  }

  /// Calls the extension's `latest(page)` operation.
  Future<SpectaResult<List<SearchResult>>> latest({required int page}) async {
    return _callOperation<List<SearchResult>>(
      operation: ExtensionOperation.latest,
      requiredCapability: ExtensionCapability.latest,
      jsExpression: 'JSON.stringify(await _spectaInstance.latest($page))',
      parse: (String result) => _parseSearchResults(result),
    );
  }

  /// Parses a search/latest result list.
  ///
  /// Robustness rules (Phase 2B, hardened 2G-C pre-flight §36.4): an entry
  /// whose `type` is not movie/series is SKIPPED, not silently converted to
  /// movie; entries missing title or URL are skipped; entries that are not
  /// JSON objects are skipped. Field reads are defensive (`is String` checks
  /// instead of casts) so a malformed OPTIONAL field — a numeric `type` or
  /// `cover` — skips that one entry instead of throwing past the skip logic
  /// and failing the whole operation. A list made entirely of invalid entries
  /// parses to an empty list rather than failing the operation — an extension
  /// that decorates its results with one malformed row must not lose the rest.
  static List<SearchResult> _parseSearchResults(String result) {
    final List<dynamic> json = jsonDecode(result) as List<dynamic>;
    final List<SearchResult> parsed = <SearchResult>[];
    for (final dynamic item in json) {
      if (item is! Map<String, dynamic>) continue;
      final dynamic typeCode = item['type'];
      final MediaType? type =
          typeCode is String ? MediaType.fromCode(typeCode) : null;
      if (type == null) continue; // unsupported type — safely ignored
      final dynamic title = item['title'];
      final dynamic url = item['url'];
      if (title is! String || title.isEmpty) continue;
      if (url is! String || url.isEmpty) continue;
      final dynamic cover = item['cover'];
      parsed.add(
        SearchResult(
          title: title,
          url: url,
          type: type,
          cover: cover is String ? cover : null,
          year: item['year'] is int ? item['year'] as int : null,
        ),
      );
    }
    return parsed;
  }

  /// Parses a `details()` result.
  ///
  /// Robustness rules (Phase 2C, mirroring the Phase 2B search rules):
  /// - `type` is REQUIRED and must be movie/series. A missing or unsupported
  ///   type is never silently converted to movie — the parse fails and the
  ///   runtime reports a controlled PARSE_ERROR (SPECTA is movies+series
  ///   only, and must not mislabel a work it cannot classify).
  /// - Required scalar fields (`id`, `title`, `url`) must be non-empty
  ///   strings; a malformed one fails the parse rather than fabricating a
  ///   value (SPECTA never invents metadata).
  /// - Tolerated: missing optional fields; rating outside 0..10 is dropped
  ///   (kept as null, not clamped — out-of-range ratings are bad data, not
  ///   data to repair); non-string genre entries are skipped; a season or
  ///   episode row that is malformed is skipped individually so one bad row
  ///   cannot destroy an otherwise valid payload.
  static MediaDetails parseMediaDetails(String result) {
    final dynamic decoded = jsonDecode(result);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('details payload is not a JSON object');
    }
    final Map<String, dynamic> json = decoded;

    final dynamic id = json['id'];
    final dynamic title = json['title'];
    final dynamic url = json['url'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('details payload has no valid id');
    }
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('details payload has no valid title');
    }
    if (url is! String || url.isEmpty) {
      throw const FormatException('details payload has no valid url');
    }

    final MediaType? type = MediaType.fromCode(json['type'] as String?);
    if (type == null) {
      throw const FormatException(
        'details payload type is missing or unsupported',
      );
    }

    final dynamic rating = json['rating'];
    final double? validRating = rating is num && rating >= 0 && rating <= 10
        ? rating.toDouble()
        : null;

    final dynamic rawStatus = json['status'];
    return MediaDetails(
      id: id,
      title: title.trim(),
      type: type,
      url: url,
      originalTitle: json['originalTitle'] is String
          ? json['originalTitle'] as String
          : null,
      cover: json['cover'] is String ? json['cover'] as String : null,
      backdrop: json['backdrop'] is String ? json['backdrop'] as String : null,
      year: json['year'] is int ? json['year'] as int : null,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      genres: _parseGenres(json['genres']),
      durationSeconds: json['duration'] is int ? json['duration'] as int : null,
      rating: validRating,
      // A non-string status degrades to unknown instead of throwing the
      // whole details payload away (2G-C pre-flight §36.4).
      status: rawStatus is String ? SeriesStatus.fromCode(rawStatus) : null,
      seasons: _parseSeasons(json['seasons']),
    );
  }

  /// Genre list: non-string entries are skipped, blanks dropped.
  static List<String> _parseGenres(dynamic raw) {
    if (raw is! List<dynamic>) return const <String>[];
    return raw
        .whereType<String>()
        .map((String g) => g.trim())
        .where((String g) => g.isNotEmpty)
        .toList(growable: false);
  }

  /// Season list: malformed season rows are skipped individually.
  static List<MediaSeason> _parseSeasons(dynamic raw) {
    if (raw is! List<dynamic>) return const <MediaSeason>[];
    final List<MediaSeason> seasons = <MediaSeason>[];
    for (final dynamic entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final dynamic seasonNumber = entry['seasonNumber'];
      if (seasonNumber is! int) continue;
      seasons.add(
        MediaSeason(
          seasonNumber: seasonNumber,
          title: entry['title'] as String?,
          episodes: _parseEpisodes(entry['episodes']),
        ),
      );
    }
    return seasons;
  }

  /// Episode list: malformed episode rows are skipped individually.
  static List<MediaEpisode> _parseEpisodes(dynamic raw) {
    if (raw is! List<dynamic>) return const <MediaEpisode>[];
    final List<MediaEpisode> episodes = <MediaEpisode>[];
    for (final dynamic entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final dynamic episodeNumber = entry['episodeNumber'];
      final dynamic url = entry['url'];
      if (episodeNumber is! int) continue;
      if (url is! String || url.isEmpty) continue;
      episodes.add(
        MediaEpisode(
          episodeNumber: episodeNumber,
          url: url,
          title: entry['title'] as String?,
          description: entry['description'] as String?,
          cover: entry['cover'] as String?,
          durationSeconds:
              entry['duration'] is int ? entry['duration'] as int : null,
        ),
      );
    }
    return episodes;
  }

  /// Calls the extension's `details(url)` operation.
  Future<SpectaResult<MediaDetails>> details({required String url}) async {
    final String escapedUrl = jsonEncode(url);
    return _callOperation<MediaDetails>(
      operation: ExtensionOperation.details,
      requiredCapability: ExtensionCapability.details,
      jsExpression:
          'JSON.stringify(await _spectaInstance.details($escapedUrl))',
      parse: parseMediaDetails,
    );
  }

  /// Parses a `getSources()` result.
  ///
  /// Robustness (2G-C pre-flight §36.4): one malformed source row is SKIPPED
  /// — the rest of the list survives — mirroring the search parser's rule
  /// that a single bad source must not lose the others.
  static List<ExtensionSource> parseSourceList(String result) {
    final List<dynamic> json = jsonDecode(result) as List<dynamic>;
    final List<ExtensionSource> parsed = <ExtensionSource>[];
    for (final dynamic item in json) {
      if (item is! Map<String, dynamic>) continue;
      try {
        parsed.add(ExtensionSource.fromJson(item));
      } on Object {
        continue; // skip the malformed row, keep the rest
      }
    }
    return parsed;
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
      parse: parseSourceList,
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
        // §36.4: a JS number arrives as num; a fractional timeout (2.5) must
        // become a rounded duration, not a failed request. The API clamps
        // over-budget values; zero/negative falls back to the default there.
        timeout: data['timeout'] is num
            ? Duration(milliseconds: (data['timeout'] as num).round())
            : const Duration(milliseconds: 15000),
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
