import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_deduplicator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/discovery/discovery_normalizer.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/runtime/extension_runtime.dart';

void main() {
  test('anime uses AniList identity and episode qualification', () {
    expect(MediaIdentity.anilistKey(16498), 'anilist:16498');
    expect(MediaIdentity.anilistKey(0), isNull);
    expect(MediaIdentity.anilistKey(-1), isNull);
    expect(
      MediaIdentity.episodeKey('anilist:16498', 1, 2),
      'anilist:16498|s1e2',
    );
  });

  test('anime without an AniList ID is rejected', () {
    expect(
      DiscoveryNormalizer.normalize(
        const SearchResult(
          title: 'Spirited Away',
          url: 'https://extension.test/anime',
          type: MediaType.anime,
        ),
        'ext',
      ),
      isNull,
    );
  });

  test('same AniList ID merges different anime titles', () {
    final List<DiscoveryObservation> observations = <DiscoveryObservation>[
      _anime('Spirited Away', 'https://a.test/1', 16498, 'a'),
      _anime('Sen to Chihiro no Kamikakushi', 'https://b.test/2', 16498, 'b'),
    ];
    final List<DiscoveryItem> items = DiscoveryDeduplicator.dedupe(
      observations,
    );
    expect(items, hasLength(1));
    expect(items.single.key, 'anilist:16498');
    expect(items.single.references, hasLength(2));
  });

  test('different AniList IDs and movie/anime titles stay separate', () {
    final List<DiscoveryObservation> observations = <DiscoveryObservation>[
      _anime('Same', 'https://a.test/1', 1, 'a'),
      _anime('Same', 'https://b.test/2', 2, 'b'),
      _other('Same', 'https://c.test/movie', MediaType.movie, 'c'),
      _anime('Same', 'https://d.test/anime', 3, 'd'),
    ];
    expect(DiscoveryDeduplicator.dedupe(observations), hasLength(4));
  });

  test('movie and series legacy identity keys are unchanged', () {
    final List<DiscoveryItem> movie = DiscoveryDeduplicator.dedupe(
      <DiscoveryObservation>[
        _other('The Batman', 'https://a.test/m', MediaType.movie, 'a', 2022),
      ],
    );
    final List<DiscoveryItem> series = DiscoveryDeduplicator.dedupe(
      <DiscoveryObservation>[
        _other('The Show', 'https://a.test/s', MediaType.series, 'a', 2024),
      ],
    );
    expect(movie.single.key, 'the batman|movie|2022');
    expect(series.single.key, 'the show|series|2024');
  });

  test('ExternalIds accepts only a positive AniList integer', () {
    expect(
      ExternalIds.fromJson(<String, Object?>{'anilist': 42})?.anilistId,
      42,
    );
    expect(ExternalIds.fromJson(<String, Object?>{'anilist': 0}), isNull);
    expect(ExternalIds.fromJson(<String, Object?>{'anilist': '42'}), isNull);
    expect(ExternalIds.fromJson(null), isNull);
    expect(ExternalIds.fromJson(<String, Object?>{'other': 42}), isNull);
  });

  test('details parsing preserves anime externalIds', () {
    final MediaDetails details = ExtensionRuntime.parseMediaDetails(
      jsonEncode(<String, Object?>{
        'id': 'a1',
        'title': 'Anime',
        'type': 'anime',
        'url': 'https://a.test/anime',
        'externalIds': <String, Object?>{'anilist': 16498},
      }),
    );
    expect(details.type, MediaType.anime);
    expect(details.externalIds?.anilistId, 16498);
  });
}

DiscoveryObservation _anime(String title, String url, int id, String ext) {
  final DiscoveryObservation? value = DiscoveryNormalizer.normalize(
    SearchResult(
      title: title,
      url: url,
      type: MediaType.anime,
      externalIds: ExternalIds(anilistId: id),
    ),
    ext,
  );
  expect(value, isNotNull);
  return value!;
}

DiscoveryObservation _other(
  String title,
  String url,
  MediaType type,
  String ext, [
  int? year,
]) {
  final DiscoveryObservation? value = DiscoveryNormalizer.normalize(
    SearchResult(title: title, url: url, type: type, year: year),
    ext,
  );
  expect(value, isNotNull);
  return value!;
}
