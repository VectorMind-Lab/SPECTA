import 'dart:convert';

import 'package:specta/core/anilist/anilist_dto.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/database/daos/metadata_cache_dao.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

/// Credential-free AniList GraphQL client with SPECTA read-through caching.
class AniListClient {
  AniListClient({
    AniListTransport? transport,
    MetadataCacheDao? cache,
    MetadataCacheDao? Function()? cacheFactory,
  }) : _transport = transport ?? DartIoAniListTransport(),
       // ignore: prefer_initializing_formals
       _cache = cache,
       _cacheFactory = cacheFactory ?? (() => null);

  final AniListTransport _transport;
  final MetadataCacheDao? _cache;

  /// Lazily resolves the cache. A factory, not an instance, so that merely
  /// CONSTRUCTING this client never touches the database: the cache is opened
  /// on first use inside the existing read/write guards, where any failure
  /// degrades to a normal network request.
  final MetadataCacheDao? Function() _cacheFactory;

  MetadataCacheDao? get _resolvedCache => _cache ?? _cacheFactory();

  static const String cacheSource = 'anilist';
  static const String apiEndpoint = 'https://graphql.anilist.co';
  static const Duration requestTimeout = Duration(seconds: 15);

  /// The field set SPECTA actually reads, validated against the live AniList
  /// schema.
  ///
  /// Schema rules this encodes, each one learned from a live 400:
  /// - `coverImage` is an OBJECT (`MediaCoverImage`) and MUST have a sub
  ///   selection. Requesting the bare field makes the whole query fail.
  /// - `bannerImage` is a plain `String`, so it takes no sub-selection.
  /// - `startDate` is a fuzzy date object; only `year` is wanted.
  static const String _mediaFields =
      'id title { romaji english native } description '
      'startDate { year month day } format status episodes duration '
      'averageScore genres bannerImage '
      'coverImage { extraLarge large color } '
      'studios { nodes { name isAnimationStudio } }';

  Future<SpectaResult<AniListMedia>> getMedia(int id) {
    if (id <= 0) {
      return Future<SpectaResult<AniListMedia>>.value(
        Err<AniListMedia>(
          AniListFailure(
            type: AniListFailureType.parseError,
            detail: 'AniList media id must be positive',
          ),
        ),
      );
    }
    return _media(
      operation: 'media',
      cacheKey: 'media:$id',
      query:
          'query (\$id: Int) { Media(id: \$id, type: ANIME) { $_mediaFields } }',
      variables: <String, Object?>{'id': id},
    );
  }

  Future<SpectaResult<List<AniListMedia>>> searchMedia(
    String query, {
    int page = 1,
  }) {
    final String clean = query.trim();
    if (clean.isEmpty) {
      return Future<SpectaResult<List<AniListMedia>>>.value(
        const Ok<List<AniListMedia>>(<AniListMedia>[]),
      );
    }
    return _search(
      cacheKey: 'search:$page:${clean.toLowerCase()}',
      query: clean,
      page: page,
    );
  }

  Future<SpectaResult<AniListMedia>> _media({
    required String operation,
    required String cacheKey,
    required String query,
    required Map<String, Object?> variables,
  }) async {
    final SpectaResult<Object?> raw = await _post(
      operation: operation,
      cacheKey: cacheKey,
      query: query,
      variables: variables,
    );
    return raw.fold(
      ok: (Object? data) {
        final AniListMedia? media = data is Map<String, Object?>
            ? AniListMedia.fromJson(data['Media'])
            : null;
        return media == null
            ? Err<AniListMedia>(_parseFailure(operation))
            : Ok<AniListMedia>(media);
      },
      err: (SpectaFailure failure) => Err<AniListMedia>(failure),
    );
  }

  Future<SpectaResult<List<AniListMedia>>> _search({
    required String cacheKey,
    required String query,
    required int page,
  }) async {
    final SpectaResult<Object?> raw = await _post(
      operation: 'search',
      cacheKey: cacheKey,
      query:
          'query (\$search: String, \$page: Int) { Page(page: \$page, perPage: 20) { media(search: \$search, type: ANIME) { $_mediaFields } } }',
      variables: <String, Object?>{'search': query, 'page': page},
    );
    return raw.fold(
      ok: (Object? data) {
        if (data is! Map<String, Object?> || data['Page'] is! Map) {
          return Err<List<AniListMedia>>(_parseFailure('search'));
        }
        final Object? rows = (data['Page'] as Map<String, Object?>)['media'];
        if (rows is! List) {
          return Err<List<AniListMedia>>(_parseFailure('search'));
        }
        final List<AniListMedia> results = <AniListMedia>[];
        for (final Object? row in rows) {
          final AniListMedia? media = AniListMedia.fromJson(row);
          if (media != null) results.add(media);
        }
        return Ok<List<AniListMedia>>(results);
      },
      err: (SpectaFailure failure) => Err<List<AniListMedia>>(failure),
    );
  }

  Future<SpectaResult<Object?>> _post({
    required String operation,
    required String cacheKey,
    required String query,
    required Map<String, Object?> variables,
  }) async {
    final String? cached = await _readCache(cacheKey);
    if (cached != null) {
      try {
        final Object? decoded = jsonDecode(cached);
        if (decoded is Map<String, Object?>) {
          final Object? data = decoded['data'];
          if (data is Map<String, Object?>) return Ok<Object?>(data);
        }
      } on FormatException {
        // A malformed cache row is a miss; never fail the request over it.
      }
    }

    final AniListHttpResponse response = await _transport.post(
      uri: Uri.parse(apiEndpoint),
      body: jsonEncode(<String, Object?>{
        'query': query,
        'variables': variables,
      }),
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      timeout: requestTimeout,
    );
    if (response.failure != null) return Err<Object?>(response.failure!);

    final int status = response.statusCode ?? 500;
    if (status == 404) {
      return Err<Object?>(
        AniListFailure(
          type: AniListFailureType.notFound,
          operation: operation,
          statusCode: status,
        ),
      );
    }
    if (status == 429) {
      return Err<Object?>(
        AniListFailure(
          type: AniListFailureType.rateLimited,
          operation: operation,
          statusCode: status,
        ),
      );
    }
    if (status >= 500) {
      return Err<Object?>(
        AniListFailure(
          type: AniListFailureType.serverError,
          operation: operation,
          statusCode: status,
        ),
      );
    }
    if (status < 200 || status >= 300) {
      return Err<Object?>(
        AniListFailure(
          type: AniListFailureType.httpError,
          operation: operation,
          statusCode: status,
        ),
      );
    }

    final String? body = response.body;
    if (body == null || body.trim().isEmpty) {
      return Err<Object?>(_parseFailure(operation));
    }
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        return Err<Object?>(_parseFailure(operation));
      }
      final Object? errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        return Err<Object?>(_parseFailure(operation));
      }
      final Object? data = decoded['data'];
      if (data is! Map<String, Object?>) {
        return Err<Object?>(_parseFailure(operation));
      }
      await _writeCache(cacheKey, body);
      return Ok<Object?>(data);
    } on FormatException catch (e) {
      return Err<Object?>(
        AniListFailure(
          type: AniListFailureType.parseError,
          operation: operation,
          detail: 'Malformed JSON: ${e.message}',
        ),
      );
    }
  }

  AniListFailure _parseFailure(String operation) =>
      AniListFailure(type: AniListFailureType.parseError, operation: operation);

  Future<String?> _readCache(String key) async {
    try {
      return await _resolvedCache?.read(source: cacheSource, mediaKey: key);
    } on Object {
      return null;
    }
  }

  Future<void> _writeCache(String key, String body) async {
    try {
      await _resolvedCache?.write(
        source: cacheSource,
        mediaKey: key,
        payloadJson: body,
      );
    } on Object {
      // Cache failure never fails the request.
    }
  }
}
