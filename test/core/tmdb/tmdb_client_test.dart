import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/tmdb/tmdb_client.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_transport.dart';

/// Scriptable [TmdbTransport] double: records every request and answers with
/// a scripted response. No network, no real TMDB key ever required.
class _FakeTransport implements TmdbTransport {
  _FakeTransport({
    this.response = const TmdbHttpResponse(statusCode: 200, body: '{}'),
  });

  /// The response returned for every request (override per test).
  TmdbHttpResponse response;

  /// Every URI the client built, in call order.
  final List<Uri> uris = <Uri>[];

  /// Every header map the client sent, in call order.
  final List<Map<String, String>> headers = <Map<String, String>>[];

  /// Set when the client must never reach the transport (notConfigured etc).
  int callCount = 0;

  @override
  Future<TmdbHttpResponse> get({
    required Uri uri,
    required String endpoint,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    callCount++;
    uris.add(uri);
    this.headers.add(headers);
    return response;
  }
}

const String _v3Key = 'abcdef0123456789abcdef0123456789';

/// A v4 read-access token shape (JWT) â€” must be sent as a bearer header.
const String _v4Token =
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturepart';

TmdbClient _client({TmdbConfig? config, required TmdbTransport transport}) =>
    TmdbClient(
      config: config ?? const TmdbConfig(apiKey: _v3Key),
      transport: transport,
    );

TmdbFailure _failureOf(SpectaResult<Object?> result) {
  final SpectaFailure failure = result.failureOrNull!;
  expect(failure, isA<TmdbFailure>());
  return failure as TmdbFailure;
}

void main() {
  group('TmdbClient â€” HTTP status mapping', () {
    test('401 maps to invalidKey with the status recorded', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 401, body: 'Unauthorized'),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularMovies();

      expect(result.isErr, isTrue);
      final TmdbFailure failure = _failureOf(result);
      expect(failure.type, TmdbFailureType.invalidKey);
      expect(failure.statusCode, 401);
      expect(failure.endpoint, '/movie/popular');
    });

    test('404 maps to notFound', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 404, body: '{}'),
      );

      final SpectaResult<TmdbMediaDetails> result = await _client(
        transport: transport,
      ).getMovieDetails(999999999);

      expect(_failureOf(result).type, TmdbFailureType.notFound);
    });

    test('429 maps to rateLimited (retryable)', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 429, body: '{}'),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularSeries();

      final TmdbFailure failure = _failureOf(result);
      expect(failure.type, TmdbFailureType.rateLimited);
      expect(failure.isRetryable, isTrue);
    });

    test('5xx maps to serverError (retryable)', () async {
      for (final int status in <int>[500, 502, 503, 599]) {
        final _FakeTransport transport = _FakeTransport(
          response: TmdbHttpResponse(statusCode: status, body: 'boom'),
        );
        final SpectaResult<TmdbMediaPage> result = await _client(
          transport: transport,
        ).getPopularMovies();
        final TmdbFailure failure = _failureOf(result);
        expect(
          failure.type,
          TmdbFailureType.serverError,
          reason: 'status $status',
        );
        expect(failure.statusCode, status);
      }
    });

    test('other non-2xx statuses map to httpError', () async {
      for (final int status in <int>[400, 403, 418]) {
        final _FakeTransport transport = _FakeTransport(
          response: TmdbHttpResponse(statusCode: status, body: '{}'),
        );
        final SpectaResult<TmdbMediaPage> result = await _client(
          transport: transport,
        ).getPopularMovies();
        expect(
          _failureOf(result).type,
          TmdbFailureType.httpError,
          reason: 'status $status',
        );
      }
    });
  });

  group('TmdbClient â€” configuration gating', () {
    test(
      'a missing key fails as notConfigured without touching transport',
      () async {
        final _FakeTransport transport = _FakeTransport();

        final SpectaResult<TmdbMediaPage> result = await _client(
          config: const TmdbConfig(),
          transport: transport,
        ).getPopularMovies();

        expect(result.isErr, isTrue);
        expect(_failureOf(result).type, TmdbFailureType.notConfigured);
        expect(transport.callCount, 0);
      },
    );

    test('a blank/whitespace key counts as absent', () async {
      final _FakeTransport transport = _FakeTransport();

      final SpectaResult<TmdbMediaPage> result = await _client(
        config: const TmdbConfig(apiKey: '   '),
        transport: transport,
      ).getPopularMovies();

      expect(_failureOf(result).type, TmdbFailureType.notConfigured);
      expect(transport.callCount, 0);
    });
  });

  group('TmdbClient â€” credential transport (v3 query key vs v4 bearer)', () {
    test('a v3 hex key travels as api_key query, never as a header', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 200, body: '{}'),
      );

      await _client(transport: transport).getPopularMovies();

      final Uri uri = transport.uris.single;
      expect(uri.queryParameters['api_key'], _v3Key);
      expect(transport.headers.single.containsKey('Authorization'), isFalse);
      expect(uri.queryParameters['page'], '1');
      expect(uri.queryParameters['language'], TmdbConfig.defaultLanguage);
      expect(uri.path, endsWith('/movie/popular'));
    });

    test(
      'a v4 eyJ token travels as Authorization Bearer, not in the query',
      () async {
        final _FakeTransport transport = _FakeTransport(
          response: const TmdbHttpResponse(statusCode: 200, body: '{}'),
        );

        await _client(
          config: const TmdbConfig(apiKey: _v4Token),
          transport: transport,
        ).getPopularMovies();

        expect(transport.headers.single['Authorization'], 'Bearer $_v4Token');
        expect(
          transport.uris.single.queryParameters.containsKey('api_key'),
          isFalse,
        );
      },
    );

    test('failure text and diagnostics never contain the key', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 401, body: 'Unauthorized'),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularMovies();

      final TmdbFailure failure = _failureOf(result);
      final String dump =
          '${failure.message} ${failure.toString()} '
          '${failure.toDiagnostics()} ${failure.endpoint} ${failure.detail}';
      expect(dump.contains(_v3Key), isFalse);
      expect(dump.contains('api_key'), isFalse);
      // Endpoint is path-only: never the full URI the transport saw.
      expect(failure.endpoint, '/movie/popular');
    });

    test(
      'transport URIs carry the key (by design); failures never echo it',
      () async {
        final _FakeTransport transport = _FakeTransport(
          response: const TmdbHttpResponse(statusCode: 500, body: 'boom'),
        );

        final SpectaResult<TmdbMediaPage> result = await _client(
          transport: transport,
        ).getPopularMovies();

        // The transport boundary is where the raw query lives...
        expect(transport.uris.single.toString(), contains(_v3Key));
        // ...and the failure built from its response does not.
        expect(_failureOf(result).toString(), isNot(contains(_v3Key)));
      },
    );
  });

  group('TmdbClient â€” successful parsing', () {
    test('popular movies parses a full page with forced type', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TmdbHttpResponse(
          statusCode: 200,
          body:
              '{"page":1,"total_pages":10,"total_results":200,'
              '"results":[{"id":603,"title":"The Matrix",'
              '"release_date":"1999-03-30"}]}',
        ),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularMovies(page: 3);

      expect(result.isOk, isTrue);
      final TmdbMediaPage page = result.valueOrNull!;
      expect(page.page, 1);
      expect(page.totalPages, 10);
      expect(page.results, hasLength(1));
      // /movie/popular rows carry no media_type â€” forcedType supplies it.
      expect(page.results.single.identity.type, MediaType.movie);
      expect(page.results.single.title, 'The Matrix');
      expect(transport.uris.single.queryParameters['page'], '3');
    });

    test('popular series forces MediaType.series', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TmdbHttpResponse(
          statusCode: 200,
          body: '{"results":[{"id":1396,"name":"Breaking Bad"}]}',
        ),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularSeries();

      expect(
        result.valueOrNull!.results.single.identity.type,
        MediaType.series,
      );
    });

    test('searchMulti parses media_type rows (movie, tv, person dropped)', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TmdbHttpResponse(
          statusCode: 200,
          body:
              '{"page":1,"total_pages":1,"total_results":2,'
              '"results":[{"id":603,"media_type":"movie","title":"The Matrix"},'
              '{"id":1396,"media_type":"tv","name":"Breaking Bad"},'
              '{"id":31,"media_type":"person","name":"Tom Hanks"}]}',
        ),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).searchMulti(query: '  matrix  ');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.results, hasLength(2));
      // Query is trimmed and dispatched with include_adult=false.
      expect(transport.uris.single.queryParameters['query'], 'matrix');
      expect(transport.uris.single.queryParameters['include_adult'], 'false');
    });

    test(
      'searchMulti with a blank query answers empty WITHOUT a round trip',
      () async {
        final _FakeTransport transport = _FakeTransport();

        final SpectaResult<TmdbMediaPage> result = await _client(
          transport: transport,
        ).searchMulti(query: '   ');

        expect(result.isOk, isTrue);
        expect(result.valueOrNull!.results, isEmpty);
        expect(transport.callCount, 0);
      },
    );
  });

  group('TmdbClient â€” details and season parsing', () {
    test('movie details parse into identity and fields', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TmdbHttpResponse(
          statusCode: 200,
          body:
              '{"id":603,"title":"The Matrix","release_date":"1999-03-30",'
              '"runtime":136,"vote_average":8.2,'
              '"genres":[{"name":"Action"},{"name":"Sci-Fi"}]}',
        ),
      );

      final SpectaResult<TmdbMediaDetails> result = await _client(
        transport: transport,
      ).getMovieDetails(603);

      final TmdbMediaDetails details = result.valueOrNull!;
      expect(details.identity.code, 'movie:603');
      expect(details.year, 1999);
      expect(details.runtimeMinutes, 136);
      expect(details.genres, <String>['Action', 'Sci-Fi']);
      expect(transport.uris.single.path, endsWith('/movie/603'));
    });

    test('season details parse episodes and hit the documented path', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TmdbHttpResponse(
          statusCode: 200,
          body:
              '{"id":620100,"season_number":1,"name":"Season 1",'
              '"episodes":[{"id":620101,"episode_number":1,'
              '"season_number":1,"name":"Pilot"}]}',
        ),
      );

      final SpectaResult<TmdbSeasonDetails> result = await _client(
        transport: transport,
      ).getSeasonDetails(tmdbId: 1396, seasonNumber: 1);

      expect(result.valueOrNull!.episodes, hasLength(1));
      expect(transport.uris.single.path, endsWith('/tv/1396/season/1'));
    });

    test('a season payload failing DTO validation is a parseError', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 200, body: '{"id": 0}'),
      );

      final SpectaResult<TmdbSeasonDetails> result = await _client(
        transport: transport,
      ).getSeasonDetails(tmdbId: 1396, seasonNumber: 1);

      expect(_failureOf(result).type, TmdbFailureType.parseError);
    });
  });

  group('TmdbClient â€” parse and transport failures', () {
    test('an empty 200 body is a parseError', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 200, body: '   '),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularMovies();

      expect(_failureOf(result).type, TmdbFailureType.parseError);
    });

    test('malformed JSON is a parseError, never an exception', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 200, body: '{not json'),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularMovies();

      expect(_failureOf(result).type, TmdbFailureType.parseError);
    });

    test('a non-object JSON root is a parseError', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 200, body: '[1,2,3]'),
      );

      final SpectaResult<TmdbMediaDetails> result = await _client(
        transport: transport,
      ).getMovieDetails(603);

      expect(_failureOf(result).type, TmdbFailureType.parseError);
    });

    test('a transport-level failure passes through unchanged', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TmdbHttpResponse(
          failure: TmdbFailure(
            type: TmdbFailureType.networkError,
            endpoint: '/movie/popular',
          ),
        ),
      );

      final SpectaResult<TmdbMediaPage> result = await _client(
        transport: transport,
      ).getPopularMovies();

      final TmdbFailure failure = _failureOf(result);
      expect(failure.type, TmdbFailureType.networkError);
      expect(failure.isRetryable, isTrue);
    });

    test('details payloads that fail DTO validation are parseError', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TmdbHttpResponse(statusCode: 200, body: '{"id": -1}'),
      );

      final SpectaResult<TmdbMediaDetails> result = await _client(
        transport: transport,
      ).getMovieDetails(603);

      expect(_failureOf(result).type, TmdbFailureType.parseError);
    });
  });
}
