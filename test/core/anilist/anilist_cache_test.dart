@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/anilist/anilist_client.dart';
import 'package:specta/core/anilist/anilist_dto.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/database/daos/metadata_cache_dao.dart';
import 'package:specta/core/database/specta_database.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

import '../../support/anilist_test_harness.dart';

void main() {
  late SpectaDatabase database;
  late MetadataCacheDao cache;

  setUp(() {
    database = SpectaDatabase(NativeDatabase.memory());
    cache = MetadataCacheDao(database);
  });

  tearDown(() => database.close());

  group('AniList cache — reuse and isolation', () {
    test('a fresh row answers without touching the transport', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistMediaBody(),
        ),
      );
      final AniListClient client = AniListClient(
        transport: transport,
        cache: cache,
      );

      await client.getMedia(16498);
      expect(transport.callCount, 1);

      final SpectaResult<AniListMedia> second = await client.getMedia(16498);

      expect(second.isOk, isTrue);
      expect(second.valueOrNull!.id, 16498);
      // The second read is served from the shared metadata cache.
      expect(transport.callCount, 1);
    });

    test('the cache is namespaced away from tmdb and tvmaze', () async {
      await cache.write(
        source: AniListClient.cacheSource,
        mediaKey: 'k',
        payloadJson: '{"anilist":1}',
      );
      await cache.write(
        source: 'tmdb',
        mediaKey: 'k',
        payloadJson: '{"tmdb":1}',
      );
      await cache.write(
        source: 'tvmaze',
        mediaKey: 'k',
        payloadJson: '{"tvmaze":1}',
      );

      expect(
        await cache.read(source: AniListClient.cacheSource, mediaKey: 'k'),
        '{"anilist":1}',
      );
      expect(await cache.read(source: 'tmdb', mediaKey: 'k'), '{"tmdb":1}');
    });

    test('an expired row is refetched rather than served', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistMediaBody(),
        ),
      );
      final AniListClient client = AniListClient(
        transport: transport,
        cache: cache,
      );

      await client.getMedia(16498);
      expect(transport.callCount, 1);

      await cache.remove(
        source: AniListClient.cacheSource,
        mediaKey: 'media:16498',
      );
      final SpectaResult<AniListMedia> afterExpiry = await client.getMedia(
        16498,
      );

      expect(afterExpiry.isOk, isTrue);
      expect(transport.callCount, 2);
    });

    test('search results are cached per query and page', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistSearchBody(),
        ),
      );
      final AniListClient client = AniListClient(
        transport: transport,
        cache: cache,
      );

      await client.searchMedia('ghibli');
      await client.searchMedia('ghibli');
      expect(transport.callCount, 1);

      await client.searchMedia('ghibli', page: 2);
      expect(transport.callCount, 2);
    });
  });

  group('AniList offline and failure behavior', () {
    final AniListHttpResponse offline = AniListHttpResponse(
      failure: AniListFailure(
        type: AniListFailureType.networkError,
        detail: 'offline',
      ),
    );

    test('offline with a warm cache still returns the record', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistMediaBody(),
        ),
      );
      final AniListClient client = AniListClient(
        transport: transport,
        cache: cache,
      );
      await client.getMedia(16498);

      // The network dies once the cache is warm.
      transport.response = offline;

      final SpectaResult<AniListMedia> afterOffline = await client.getMedia(
        16498,
      );
      expect(afterOffline.isOk, isTrue);
      expect(afterOffline.valueOrNull!.id, 16498);
    });

    test(
      'offline with a cold cache fails as a structured network error',
      () async {
        final SpectaResult<AniListMedia> result = await AniListClient(
          transport: FakeAniListTransport(response: offline),
          cache: cache,
        ).getMedia(16498);

        expect(result.isErr, isTrue);
        expect(anilistFailureOf(result).type, AniListFailureType.networkError);
      },
    );

    test('an unusable cache row is a miss, not a hard failure', () async {
      // Valid JSON, wrong shape: the client must treat it as a miss and
      // revalidate rather than fail the request.
      await cache.write(
        source: AniListClient.cacheSource,
        mediaKey: 'media:16498',
        payloadJson: '{"data":"not-a-map"}',
      );
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistMediaBody(),
        ),
      );

      final SpectaResult<AniListMedia> result = await AniListClient(
        transport: transport,
        cache: cache,
      ).getMedia(16498);

      expect(result.isOk, isTrue);
      expect(transport.callCount, 1);
    });

    test('with no cache wired every request reaches the transport', () async {
      final FakeAniListTransport transport = FakeAniListTransport(
        response: AniListHttpResponse(
          statusCode: 200,
          body: anilistMediaBody(),
        ),
      );
      final AniListClient client = AniListClient(transport: transport);

      await client.getMedia(16498);
      await client.getMedia(16498);

      expect(transport.callCount, 2);
    });
  });
}
