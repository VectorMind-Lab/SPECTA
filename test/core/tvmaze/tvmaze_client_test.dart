import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/daos/metadata_cache_dao.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';
import 'package:specta/core/tvmaze/tvmaze_client.dart';
import 'package:specta/core/tvmaze/tvmaze_dto.dart';
import 'package:specta/core/tvmaze/tvmaze_transport.dart';

/// Scriptable [TvmazeTransport] double: records every request and answers with a
/// scripted response. No network — and, deliberately, no credential, because
/// TVMaze requires none.
class _FakeTransport implements TvmazeTransport {
  _FakeTransport({
    this.response = const TvmazeHttpResponse(statusCode: 200, body: '{}'),
  });

  TvmazeHttpResponse response;
  final List<Uri> uris = <Uri>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];
  int callCount = 0;

  @override
  Future<TvmazeHttpResponse> get({
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

TvmazeFailure _failureOf(SpectaResult<Object?> result) {
  final SpectaFailure failure = result.failureOrNull!;
  expect(failure, isA<TvmazeFailure>());
  return failure as TvmazeFailure;
}

const Map<String, Object?> _showJson = <String, Object?>{
  'id': 82,
  'name': '  Better Call Saul  ',
  'originalTitle': null,
  'summary': 'A lawyer turned morally ambiguous.',
  'image': 'https://static.tvmaze.com/poster.jpg',
  'officialSite': 'https://example.test/bcs',
  'premiered': '2015-02-08',
  'status': 'Running',
  'genres': <String>['Drama', '  '],
  'rating': <String, Object?>{'average': 9.1},
  'averageRuntime': 47,
};

void main() {
  group('TvmazeShow.fromJson — defensive parsing', () {
    test(
      'maps a full payload, trimming strings and keeping the artwork URL',
      () {
        final TvmazeShow? show = TvmazeShow.fromJson(_showJson);

        expect(show, isNotNull);
        expect(show!.id, 82);
        expect(show.title, 'Better Call Saul');
        expect(show.overview, 'A lawyer turned morally ambiguous.');
        expect(show.posterUrl, 'https://static.tvmaze.com/poster.jpg');
        expect(show.premieredYear, 2015);
        expect(show.status, 'Running');
        // The blank genre is dropped rather than stored as an empty label.
        expect(show.genres, <String>['Drama']);
        expect(show.rating, 9.1);
        expect(show.averageRuntimeMinutes, 47);
        expect(show.cacheKey, 'show:82');
      },
    );

    test(
      'rejects payloads with no usable id or title rather than guessing',
      () {
        expect(
          TvmazeShow.fromJson(<String, Object?>{'id': 0, 'name': 'X'}),
          isNull,
        );
        expect(
          TvmazeShow.fromJson(<String, Object?>{'id': '82', 'name': 'X'}),
          isNull,
        );
        expect(TvmazeShow.fromJson(<String, Object?>{'id': 82}), isNull);
        expect(
          TvmazeShow.fromJson(<String, Object?>{'id': 82, 'name': '   '}),
          isNull,
        );
      },
    );

    test('wrong-typed optional fields degrade to null, never throw', () {
      final TvmazeShow? show = TvmazeShow.fromJson(<String, Object?>{
        'id': 1,
        'name': 'Show',
        'summary': 42,
        'image': <String>['nope'],
        'premiered': 'not-a-year',
        'genres': 'Drama',
        'rating': 'nope',
        'averageRuntime': '47',
      });

      expect(show, isNotNull);
      expect(show!.overview, isNull);
      expect(show.posterUrl, isNull);
      expect(show.premieredYear, isNull);
      expect(show.genres, isEmpty);
      expect(show.rating, isNull);
      expect(show.averageRuntimeMinutes, isNull);
    });
  });
  group('TvmazeClient — credential-free requests', () {
    test('sends no credential header and hits the expected endpoint', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TvmazeHttpResponse(
          statusCode: 200,
          body: jsonEncode(_showJson),
        ),
      );
      final TvmazeClient client = TvmazeClient(transport: transport);

      final SpectaResult<TvmazeShow> result = await client.getShow(82);

      expect(result.isOk, isTrue);
      expect(transport.callCount, 1);
      expect(transport.uris.single.path, '/shows/82');
      // TVMaze needs no key: nothing resembling a credential may be sent.
      expect(transport.headers.single, <String, String>{
        'Accept': 'application/json',
      });
    });

    test('rejects a non-positive id without a network call', () async {
      final _FakeTransport transport = _FakeTransport();
      final TvmazeClient client = TvmazeClient(transport: transport);

      final SpectaResult<TvmazeShow> result = await client.getShow(0);

      expect(transport.callCount, 0);
      expect(_failureOf(result).type, TvmazeFailureType.parseError);
    });

    test(
      'an empty search short-circuits to an empty list, no network',
      () async {
        final _FakeTransport transport = _FakeTransport();
        final TvmazeClient client = TvmazeClient(transport: transport);

        final SpectaResult<TvmazeShowList> result = await client.searchShows(
          '   ',
        );

        expect(transport.callCount, 0);
        expect(result.valueOrNull!.results, isEmpty);
      },
    );

    test('a search skips unparseable elements instead of failing', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TvmazeHttpResponse(
          statusCode: 200,
          body: jsonEncode(<Object?>[
            _showJson,
            <String, Object?>{'id': 0, 'name': 'Broken'},
            'not-an-object',
          ]),
        ),
      );
      final TvmazeClient client = TvmazeClient(transport: transport);

      final SpectaResult<TvmazeShowList> result = await client.searchShows(
        'saul',
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.results.single.id, 82);
    });
  });
  test('maps 404, 429 and 5xx to distinct failure types', () async {
    Future<TvmazeFailureType> typeFor(int status) async {
      final TvmazeClient client = TvmazeClient(
        transport: _FakeTransport(
          response: TvmazeHttpResponse(statusCode: status, body: '{}'),
        ),
      );
      return _failureOf(await client.getShow(1)).type;
    }

    expect(await typeFor(404), TvmazeFailureType.notFound);
    expect(await typeFor(429), TvmazeFailureType.rateLimited);
    expect(await typeFor(503), TvmazeFailureType.serverError);
    expect(await typeFor(418), TvmazeFailureType.httpError);
  });

  test('a malformed body is a parse failure, never an exception', () async {
    final TvmazeClient client = TvmazeClient(
      transport: _FakeTransport(
        response: const TvmazeHttpResponse(statusCode: 200, body: '{not json'),
      ),
    );

    expect(
      _failureOf(await client.getShow(1)).type,
      TvmazeFailureType.parseError,
    );
  });

  test(
    'a list endpoint receiving an object is rejected, not coerced',
    () async {
      final TvmazeClient client = TvmazeClient(
        transport: _FakeTransport(
          response: TvmazeHttpResponse(
            statusCode: 200,
            body: jsonEncode(_showJson),
          ),
        ),
      );

      expect(
        _failureOf(await client.searchShows('saul')).type,
        TvmazeFailureType.parseError,
      );
    },
  );

  group('TvmazeClient — persistent read-through cache', () {
    late SpectaDatabase database;
    late MetadataCacheDao cache;

    setUp(() {
      database = SpectaDatabase(NativeDatabase.memory());
      cache = MetadataCacheDao(database);
    });

    tearDown(() => database.close());

    test(
      'a second call is served from the cache with no network request',
      () async {
        final _FakeTransport transport = _FakeTransport(
          response: TvmazeHttpResponse(
            statusCode: 200,
            body: jsonEncode(_showJson),
          ),
        );
        final TvmazeClient client = TvmazeClient(
          transport: transport,
          cache: cache,
        );

        final SpectaResult<TvmazeShow> first = await client.getShow(82);
        // The transport now fails; a cache hit must not notice.
        transport.response = const TvmazeHttpResponse(
          statusCode: 500,
          body: '{}',
        );
        final SpectaResult<TvmazeShow> second = await client.getShow(82);

        expect(transport.callCount, 1);
        expect(second.isOk, isTrue);
        expect(second.valueOrNull!.title, first.valueOrNull!.title);
        // The artwork URL survives the round trip through the cache verbatim.
        expect(
          second.valueOrNull!.posterUrl,
          'https://static.tvmaze.com/poster.jpg',
        );
      },
    );
    test(
      'the cached row keeps the source and endpoint as its identity',
      () async {
        final TvmazeClient client = TvmazeClient(
          transport: _FakeTransport(
            response: TvmazeHttpResponse(
              statusCode: 200,
              body: jsonEncode(_showJson),
            ),
          ),
          cache: cache,
        );

        await client.getShow(82);

        expect(
          await cache.read(source: 'tvmaze', mediaKey: '/shows/82'),
          jsonEncode(_showJson),
        );
        // A different source namespace must not see the TVMaze row.
        expect(await cache.read(source: 'tmdb', mediaKey: '/shows/82'), isNull);
      },
    );

    test('a stale row is refetched and replaced', () async {
      // Seed a row written 31 days ago against a 30-day TTL.
      await cache.write(
        source: 'tvmaze',
        mediaKey: '/shows/82',
        payloadJson: jsonEncode(_showJson),
        now: DateTime.utc(2026, 1, 1),
      );
      final _FakeTransport transport = _FakeTransport(
        response: TvmazeHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'id': 82, 'name': 'Fresher'}),
        ),
      );
      final TvmazeClient client = TvmazeClient(
        transport: transport,
        cache: cache,
      );

      final SpectaResult<TvmazeShow> result = await client.getShow(82);

      expect(transport.callCount, 1);
      expect(result.valueOrNull!.title, 'Fresher');
      expect(
        await cache.read(source: 'tvmaze', mediaKey: '/shows/82'),
        contains('Fresher'),
      );
    });
    test('a failed fetch is not cached, so the next call retries', () async {
      final _FakeTransport transport = _FakeTransport(
        response: const TvmazeHttpResponse(statusCode: 500, body: '{}'),
      );
      final TvmazeClient client = TvmazeClient(
        transport: transport,
        cache: cache,
      );

      await client.getShow(82);
      await client.getShow(82);

      expect(transport.callCount, 2);
      expect(await cache.read(source: 'tvmaze', mediaKey: '/shows/82'), isNull);
    });

    test('without a cache every call reaches the network', () async {
      final _FakeTransport transport = _FakeTransport(
        response: TvmazeHttpResponse(
          statusCode: 200,
          body: jsonEncode(_showJson),
        ),
      );
      final TvmazeClient client = TvmazeClient(transport: transport);

      await client.getShow(82);
      await client.getShow(82);

      expect(transport.callCount, 2);
    });
  });
}
