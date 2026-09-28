import 'dart:convert';

import 'package:specta/core/database/daos/metadata_cache_dao.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_transport.dart';

/// The Phase 3 TMDB API Client.
///
/// Features & boundaries:
/// 1. Strict credential hygiene: Never leaks API keys, raw query strings, or complete
///    URIs into failures, diagnostics, logs, or error text.
/// 2. Deterministic HTTP status handling:
///    - HTTP 401 => [TmdbFailureType.invalidKey]
///    - HTTP 404 => [TmdbFailureType.notFound]
///    - HTTP 429 => [TmdbFailureType.rateLimited]
///    - HTTP 5xx => [TmdbFailureType.serverError]
///    - Other non-2xx => [TmdbFailureType.httpError]
///    - JSON decode error / structure mismatch => [TmdbFailureType.parseError]
/// 3. Fully testable without network via [TmdbTransport] dependency injection.
class TmdbClient {
  TmdbClient({
    required this.config,
    TmdbTransport? transport,
    MetadataCacheDao? cache,
    MetadataCacheDao? Function()? cacheFactory,
  }) : _transport = transport ?? DartIoTmdbTransport(),
       // ignore: prefer_initializing_formals
       _cache = cache,
       _cacheFactory = cacheFactory ?? (() => null);

  final TmdbConfig config;
  final TmdbTransport _transport;

  /// Optional persistent read-through cache. When absent (tests, or any
  /// caller that does not wire a database) every request goes to the network,
  /// so behaviour is identical to an uncached build.
  final MetadataCacheDao? _cache;

  /// Lazily resolves the cache so constructing this client never opens the
  /// database; it is read on first use inside the guarded cache helpers.
  final MetadataCacheDao? Function() _cacheFactory;

  MetadataCacheDao? get _resolvedCache => _cache ?? _cacheFactory();

  /// Cache namespace. Shares the `metadata_cache` table with TVMaze; the
  /// `source` column keeps the two catalogues from colliding.
  static const String cacheSource = 'tmdb';

  /// Fetch popular movies.
  Future<SpectaResult<TmdbMediaPage>> getPopularMovies({int page = 1}) =>
      _getPage(
        endpoint: '/movie/popular',
        queryParams: <String, String>{'page': '$page'},
        forcedType: MediaType.movie,
      );

  /// Fetch popular TV series.
  Future<SpectaResult<TmdbMediaPage>> getPopularSeries({int page = 1}) =>
      _getPage(
        endpoint: '/tv/popular',
        queryParams: <String, String>{'page': '$page'},
        forcedType: MediaType.series,
      );

  /// Multi-search across movies and TV series by query string.
  Future<SpectaResult<TmdbMediaPage>> searchMulti({
    required String query,
    int page = 1,
  }) {
    final String cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return Future<SpectaResult<TmdbMediaPage>>.value(
        const Ok<TmdbMediaPage>(
          TmdbMediaPage(
            page: 1,
            totalPages: 1,
            totalResults: 0,
            results: <TmdbMediaSummary>[],
          ),
        ),
      );
    }
    return _getPage(
      endpoint: '/search/multi',
      queryParams: <String, String>{
        'query': cleanQuery,
        'page': '$page',
        'include_adult': '${config.includeAdult}',
      },
    );
  }

  /// Movie details by TMDB movie ID.
  Future<SpectaResult<TmdbMediaDetails>> getMovieDetails(int tmdbId) =>
      _getDetails(endpoint: '/movie/$tmdbId', type: MediaType.movie);

  /// TV Series details by TMDB TV ID.
  Future<SpectaResult<TmdbMediaDetails>> getSeriesDetails(int tmdbId) =>
      _getDetails(endpoint: '/tv/$tmdbId', type: MediaType.series);

  /// TV Season details (including full episode list) by TV ID and season number.
  Future<SpectaResult<TmdbSeasonDetails>> getSeasonDetails({
    required int tmdbId,
    required int seasonNumber,
  }) async {
    final String endpoint = '/tv/$tmdbId/season/$seasonNumber';
    final SpectaResult<Map<String, Object?>> jsonResult = await _getJson(
      endpoint,
    );
    return jsonResult.fold(
      ok: (Map<String, Object?> json) {
        final TmdbSeasonDetails? details = TmdbSeasonDetails.fromJson(json);
        if (details == null) {
          return Err<TmdbSeasonDetails>(
            TmdbFailure(
              type: TmdbFailureType.parseError,
              endpoint: endpoint,
              detail: 'Failed to parse season details payload',
            ),
          );
        }
        return Ok<TmdbSeasonDetails>(details);
      },
      err: (SpectaFailure failure) => Err<TmdbSeasonDetails>(failure),
    );
  }

  // --- Internal Request Machinery ---

  Future<SpectaResult<TmdbMediaPage>> _getPage({
    required String endpoint,
    required Map<String, String> queryParams,
    MediaType? forcedType,
  }) async {
    final SpectaResult<Map<String, Object?>> jsonResult = await _getJson(
      endpoint,
      additionalParams: queryParams,
    );
    return jsonResult.fold(
      ok: (Map<String, Object?> json) {
        try {
          final TmdbMediaPage page = TmdbMediaPage.fromJson(
            json,
            forcedType: forcedType,
          );
          return Ok<TmdbMediaPage>(page);
        } on Object catch (e) {
          return Err<TmdbMediaPage>(
            TmdbFailure(
              type: TmdbFailureType.parseError,
              endpoint: endpoint,
              detail: 'Failed to parse media page: $e',
            ),
          );
        }
      },
      err: (SpectaFailure failure) => Err<TmdbMediaPage>(failure),
    );
  }

  Future<SpectaResult<TmdbMediaDetails>> _getDetails({
    required String endpoint,
    required MediaType type,
  }) async {
    final SpectaResult<Map<String, Object?>> jsonResult = await _getJson(
      endpoint,
    );
    return jsonResult.fold(
      ok: (Map<String, Object?> json) {
        final TmdbMediaDetails? details = TmdbMediaDetails.fromJson(
          json,
          type: type,
        );
        if (details == null) {
          return Err<TmdbMediaDetails>(
            TmdbFailure(
              type: TmdbFailureType.parseError,
              endpoint: endpoint,
              detail: 'Failed to parse media details payload',
            ),
          );
        }
        return Ok<TmdbMediaDetails>(details);
      },
      err: (SpectaFailure failure) => Err<TmdbMediaDetails>(failure),
    );
  }

  Future<SpectaResult<Map<String, Object?>>> _getJson(
    String endpoint, {
    Map<String, String>? additionalParams,
  }) async {
    final String? key = config.normalizedKey;
    if (key == null) {
      return Err<Map<String, Object?>>(
        TmdbFailure(type: TmdbFailureType.notConfigured, endpoint: endpoint),
      );
    }

    final bool isBearer = key.startsWith('eyJ');
    final Map<String, String> query = <String, String>{
      'language': config.language,
      if (!isBearer) 'api_key': key,
      ...?additionalParams,
    };

    // Read-through cache: a fresh row is returned without building a URI or
    // touching the network. The cache key deliberately excludes `api_key` so a
    // rotated build-time credential can never miss (or leak into) the store.
    final String cacheKey = _cacheKey(endpoint, additionalParams);
    final String? cached = await _readCache(cacheKey);
    if (cached != null) {
      final Object? decoded = jsonDecode(cached);
      if (decoded is Map<String, Object?>) {
        return Ok<Map<String, Object?>>(decoded);
      }
      // A structurally wrong payload is treated as a miss; the fresh response
      // below overwrites it.
    }

    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      if (isBearer) 'Authorization': 'Bearer $key',
    };

    final Uri base = Uri.parse(config.apiBaseUrl);
    final String path = base.path.endsWith('/')
        ? '${base.path.substring(0, base.path.length - 1)}$endpoint'
        : '${base.path}$endpoint';

    final Uri uri = base.replace(path: path, queryParameters: query);

    final TmdbHttpResponse response = await _transport.get(
      uri: uri,
      endpoint: endpoint,
      headers: headers,
      timeout: config.requestTimeout,
    );

    if (response.failure != null) {
      return Err<Map<String, Object?>>(response.failure!);
    }

    final int status = response.statusCode ?? 500;
    if (status == 401) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.invalidKey,
          endpoint: endpoint,
          statusCode: 401,
        ),
      );
    }
    if (status == 404) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.notFound,
          endpoint: endpoint,
          statusCode: 404,
        ),
      );
    }
    if (status == 429) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.rateLimited,
          endpoint: endpoint,
          statusCode: 429,
        ),
      );
    }
    if (status >= 500 && status < 600) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.serverError,
          endpoint: endpoint,
          statusCode: status,
        ),
      );
    }
    if (status < 200 || status >= 300) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.httpError,
          endpoint: endpoint,
          statusCode: status,
        ),
      );
    }

    final String? body = response.body;
    if (body == null || body.trim().isEmpty) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.parseError,
          endpoint: endpoint,
          statusCode: status,
          detail: 'Empty response body from TMDB',
        ),
      );
    }

    // A 2xx body is stored verbatim (image paths and every field included) so a
    // cache hit is indistinguishable from the original response. Only after a
    // confirmed JSON object, so a malformed payload is never persisted.
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        return Err<Map<String, Object?>>(
          TmdbFailure(
            type: TmdbFailureType.parseError,
            endpoint: endpoint,
            statusCode: status,
            detail: 'Expected JSON object in root response',
          ),
        );
      }
      await _writeCache(cacheKey, body);
      return Ok<Map<String, Object?>>(decoded);
    } on FormatException catch (e) {
      return Err<Map<String, Object?>>(
        TmdbFailure(
          type: TmdbFailureType.parseError,
          endpoint: endpoint,
          statusCode: status,
          detail: 'Malformed JSON: ${e.message}',
        ),
      );
    }
  }

  /// Stable cache identity for one request: endpoint plus its non-credential
  /// query parameters, sorted so parameter order cannot split one logical
  /// request into two rows.
  static String _cacheKey(String endpoint, Map<String, String>? params) {
    if (params == null || params.isEmpty) return endpoint;
    final List<String> names =
        params.keys.where((String name) => name != 'api_key').toList()..sort();
    final String suffix = names
        .map((String name) => '$name=${params[name]}')
        .join('&');
    return suffix.isEmpty ? endpoint : '$endpoint?$suffix';
  }

  Future<String?> _readCache(String cacheKey) async {
    try {
      return await _resolvedCache?.read(
        source: cacheSource,
        mediaKey: cacheKey,
      );
    } on Object {
      // A cache is an optimization, never a hard dependency: any database
      // problem degrades to a normal network request.
      return null;
    }
  }

  Future<void> _writeCache(String cacheKey, String body) async {
    try {
      await _resolvedCache?.write(
        source: cacheSource,
        mediaKey: cacheKey,
        payloadJson: body,
      );
    } on Object {
      // Same rule as reads: a failed write must not fail the request.
    }
  }
}
