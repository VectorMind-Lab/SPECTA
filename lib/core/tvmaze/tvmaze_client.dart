import 'dart:convert';

import 'package:specta/core/database/daos/metadata_cache_dao.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/tvmaze/tvmaze_dto.dart';
import 'package:specta/core/tvmaze/tvmaze_transport.dart';

/// Credential-free TVMaze show client.
///
/// TVMaze's public API needs no key, no account and no token, so this client
/// has no configuration object at all — that absence is the point, and it is
/// why a missing TMDB build-time define does not disable this source.
///
/// SCOPE — TVMAZE IS SERIES ONLY. TVMaze publishes no movie catalogue, so this
/// class deliberately exposes no movie endpoint. A caller wanting movie
/// metadata must go through TMDB; there is no TVMaze fallback for movies and
/// this client will not pretend to provide one.
///
/// Caching mirrors `TmdbClient`: a fresh cache row is returned without any
/// network call, and a successful 2xx body is stored verbatim so a cache hit is
/// indistinguishable from the original response.
class TvmazeClient {
  TvmazeClient({
    TvmazeTransport? transport,
    MetadataCacheDao? cache,
    MetadataCacheDao? Function()? cacheFactory,
  }) : _transport = transport ?? DartIoTvmazeTransport(),
       // ignore: prefer_initializing_formals
       _cache = cache,
       _cacheFactory = cacheFactory ?? (() => null);

  final TvmazeTransport _transport;

  /// Optional persistent read-through cache. When absent every request goes to
  /// the network, so behaviour is identical to an uncached build.
  final MetadataCacheDao? _cache;

  /// Lazily resolves the cache so constructing this client never opens the
  /// database; it is read on first use inside the guarded cache helpers.
  final MetadataCacheDao? Function() _cacheFactory;

  MetadataCacheDao? get _resolvedCache => _cache ?? _cacheFactory();

  /// Cache namespace. Shares the `metadata_cache` table with TMDB; the `source`
  /// column keeps the two catalogues from colliding.
  static const String cacheSource = 'tvmaze';

  /// TVMaze's public API root.
  static const String apiBaseUrl = 'https://api.tvmaze.com';

  /// Per-request deadline. No configuration knob: TVMaze has no key to
  /// misconfigure, so the deadline is a constant of the client.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Looks a show up by TVMaze's own numeric id.
  Future<SpectaResult<TvmazeShow>> getShow(int showId) async {
    if (showId <= 0) {
      return Err<TvmazeShow>(
        TvmazeFailure(
          type: TvmazeFailureType.parseError,
          detail: 'Show id must be positive, got $showId',
        ),
      );
    }
    final String endpoint = '/shows/$showId';
    final SpectaResult<Object?> jsonResult = await _getJson(endpoint);
    return jsonResult.fold(
      ok: (Object? decoded) {
        final TvmazeShow? show = decoded is Map<String, Object?>
            ? TvmazeShow.fromJson(decoded)
            : null;
        if (show == null) {
          return Err<TvmazeShow>(
            TvmazeFailure(
              type: TvmazeFailureType.parseError,
              endpoint: endpoint,
              detail: 'Failed to parse show payload',
            ),
          );
        }
        return Ok<TvmazeShow>(show);
      },
      err: (SpectaFailure failure) => Err<TvmazeShow>(failure),
    );
  }

  /// Searches shows by name. An empty query short-circuits to an empty result
  /// without a network call.
  Future<SpectaResult<TvmazeShowList>> searchShows(
    String query, {
    int page = 1,
  }) {
    final String cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return Future<SpectaResult<TvmazeShowList>>.value(
        const Ok<TvmazeShowList>(TvmazeShowList(results: <TvmazeShow>[])),
      );
    }
    return _getList(
      endpoint: '/search/shows',
      params: <String, String>{'q': cleanQuery, 'page': '$page'},
    );
  }

  // --- Internal Request Machinery ---

  Future<SpectaResult<TvmazeShowList>> _getList({
    required String endpoint,
    required Map<String, String> params,
  }) async {
    final SpectaResult<Object?> jsonResult = await _getJson(
      endpoint,
      additionalParams: params,
      expectList: true,
    );
    return jsonResult.fold(
      ok: (Object? decoded) {
        final List<TvmazeShow> shows = <TvmazeShow>[];
        if (decoded is List) {
          for (final Object? element in decoded) {
            if (element is Map<String, Object?>) {
              final TvmazeShow? show = TvmazeShow.fromJson(element);
              // One unparseable element is skipped rather than failing the whole
              // search: TVMaze results are heterogeneous by nature.
              if (show != null) shows.add(show);
            }
          }
        }
        return Ok<TvmazeShowList>(TvmazeShowList(results: shows));
      },
      err: (SpectaFailure failure) => Err<TvmazeShowList>(failure),
    );
  }

  /// Fetches and decodes one endpoint, consulting and updating the cache.
  ///
  /// [expectList] selects the expected root shape: TVMaze returns a bare array
  /// for list endpoints and an object for single-show endpoints.
  Future<SpectaResult<Object?>> _getJson(
    String endpoint, {
    Map<String, String>? additionalParams,
    bool expectList = false,
  }) async {
    // Read-through cache: a fresh row is returned without building a URI or
    // touching the network.
    final String cacheKey = _cacheKey(endpoint, additionalParams);
    final String? cached = await _readCache(cacheKey);
    if (cached != null) {
      try {
        return Ok<Object?>(jsonDecode(cached));
      } on FormatException {
        // A structurally wrong payload is treated as a miss; the fresh
        // response below overwrites it.
      }
    }

    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };

    final Uri base = Uri.parse(apiBaseUrl);
    final String path = base.path.endsWith('/')
        ? '${base.path.substring(0, base.path.length - 1)}$endpoint'
        : '${base.path}$endpoint';

    final Uri uri = base.replace(
      path: path,
      queryParameters: additionalParams?.isEmpty ?? true
          ? null
          : additionalParams,
    );

    final TvmazeHttpResponse response = await _transport.get(
      uri: uri,
      endpoint: endpoint,
      headers: headers,
      timeout: requestTimeout,
    );

    if (response.failure != null) {
      return Err<Object?>(response.failure!);
    }

    final int status = response.statusCode ?? 500;
    if (status == 404) {
      return Err<Object?>(
        TvmazeFailure(
          type: TvmazeFailureType.notFound,
          endpoint: endpoint,
          statusCode: 404,
        ),
      );
    }
    if (status == 429) {
      return Err<Object?>(
        TvmazeFailure(
          type: TvmazeFailureType.rateLimited,
          endpoint: endpoint,
          statusCode: 429,
        ),
      );
    }
    if (status >= 500 && status < 600) {
      return Err<Object?>(
        TvmazeFailure(
          type: TvmazeFailureType.serverError,
          endpoint: endpoint,
          statusCode: status,
        ),
      );
    }
    if (status < 200 || status >= 300) {
      return Err<Object?>(
        TvmazeFailure(
          type: TvmazeFailureType.httpError,
          endpoint: endpoint,
          statusCode: status,
        ),
      );
    }

    final String? body = response.body;
    if (body == null || body.trim().isEmpty) {
      return Err<Object?>(
        TvmazeFailure(
          type: TvmazeFailureType.parseError,
          endpoint: endpoint,
          statusCode: status,
          detail: 'Empty response body from TVMaze',
        ),
      );
    }

    // A 2xx body is stored verbatim (artwork URLs and every field included) so a
    // cache hit is indistinguishable from the original response. Only after a
    // confirmed decode, so a malformed payload is never persisted.
    try {
      final Object? decoded = jsonDecode(body);
      final bool shapeOk = expectList
          ? decoded is List
          : decoded is Map<String, Object?>;
      if (!shapeOk) {
        return Err<Object?>(
          TvmazeFailure(
            type: TvmazeFailureType.parseError,
            endpoint: endpoint,
            statusCode: status,
            detail: expectList
                ? 'Expected JSON array in root response'
                : 'Expected JSON object in root response',
          ),
        );
      }
      await _writeCache(cacheKey, body);
      return Ok<Object?>(decoded);
    } on FormatException catch (e) {
      return Err<Object?>(
        TvmazeFailure(
          type: TvmazeFailureType.parseError,
          endpoint: endpoint,
          statusCode: status,
          detail: 'Malformed JSON: ${e.message}',
        ),
      );
    }
  }

  /// Stable cache identity for one request: endpoint plus its query parameters,
  /// sorted so parameter order cannot split one logical request into two rows.
  static String _cacheKey(String endpoint, Map<String, String>? params) {
    if (params == null || params.isEmpty) return endpoint;
    final List<String> names = params.keys.toList()..sort();
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
