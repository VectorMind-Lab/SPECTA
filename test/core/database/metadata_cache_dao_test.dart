@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/database/daos/metadata_cache_dao.dart';
import 'package:specta/core/database/specta_database.dart';

void main() {
  late SpectaDatabase database;
  late MetadataCacheDao cache;

  setUp(() {
    database = SpectaDatabase(NativeDatabase.memory());
    cache = MetadataCacheDao(database);
  });

  tearDown(() => database.close());

  test('a miss returns null', () async {
    expect(await cache.read(source: 'tmdb', mediaKey: '/movie/550'), isNull);
  });

  test('a written payload reads back verbatim', () async {
    const String payload = '{"title":"Fight Club","poster":"https://x/y.jpg"}';
    await cache.write(
      source: 'tmdb',
      mediaKey: '/movie/550',
      payloadJson: payload,
    );

    expect(await cache.read(source: 'tmdb', mediaKey: '/movie/550'), payload);
  });

  test(
    'sources are isolated: the same key in two namespaces is two rows',
    () async {
      await cache.write(source: 'tmdb', mediaKey: 'k', payloadJson: '{"a":1}');
      await cache.write(
        source: 'tvmaze',
        mediaKey: 'k',
        payloadJson: '{"b":2}',
      );

      expect(await cache.read(source: 'tmdb', mediaKey: 'k'), '{"a":1}');
      expect(await cache.read(source: 'tvmaze', mediaKey: 'k'), '{"b":2}');
    },
  );

  test(
    'rewriting the same key replaces the row instead of duplicating it',
    () async {
      await cache.write(source: 'tmdb', mediaKey: 'k', payloadJson: '{"a":1}');
      await cache.write(source: 'tmdb', mediaKey: 'k', payloadJson: '{"a":2}');

      final rows = await database.select(database.metadataCache).get();
      expect(rows.length, 1);
      expect(rows.single.payload, '{"a":2}');
    },
  );

  test('a row is fresh before the TTL and stale after it', () async {
    final DateTime written = DateTime.utc(2026, 3, 1);
    await cache.write(
      source: 'tmdb',
      mediaKey: 'k',
      payloadJson: '{"a":1}',
      now: written,
    );

    expect(
      await cache.read(
        source: 'tmdb',
        mediaKey: 'k',
        now: written.add(
          MetadataCacheDao.timeToLive - const Duration(minutes: 1),
        ),
      ),
      isNotNull,
    );
    expect(
      await cache.read(
        source: 'tmdb',
        mediaKey: 'k',
        now: written.add(
          MetadataCacheDao.timeToLive + const Duration(minutes: 1),
        ),
      ),
      isNull,
    );
  });

  test('remove deletes only the targeted row', () async {
    await cache.write(source: 'tmdb', mediaKey: 'a', payloadJson: '{"a":1}');
    await cache.write(source: 'tmdb', mediaKey: 'b', payloadJson: '{"b":1}');

    await cache.remove(source: 'tmdb', mediaKey: 'a');

    expect(await cache.read(source: 'tmdb', mediaKey: 'a'), isNull);
    expect(await cache.read(source: 'tmdb', mediaKey: 'b'), isNotNull);
  });

  test(
    'a non-JSON payload is rejected before it can enter the cache',
    () async {
      await expectLater(
        cache.write(source: 'tmdb', mediaKey: 'k', payloadJson: 'not json'),
        throwsA(isA<FormatException>()),
      );
      expect(await cache.read(source: 'tmdb', mediaKey: 'k'), isNull);
    },
  );
}
