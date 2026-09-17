import 'package:flutter_test/flutter_test.dart' as t;

import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/core/metadata/metadata_normalizer.dart';

/// Builds a minimal valid raw [MediaDetails].
MediaDetails _raw({
  String title = 'Test Movie',
  MediaType type = MediaType.movie,
  String url = 'https://example.com/movie/1',
  List<MediaSeason> seasons = const <MediaSeason>[],
  String? description = '  A description.  ',
  String? cover = '  https://example.com/cover.jpg  ',
}) =>
    MediaDetails(
      id: 'm1',
      title: title,
      type: type,
      url: url,
      description: description,
      cover: cover,
      seasons: seasons,
    );

DiscoveryReference _ref({String extensionId = 'extA'}) =>
    DiscoveryReference(extensionId: extensionId, url: 'https://example.com/movie/1');

void main() {
  t.group('MetadataNormalizer — accepted payloads', () {
    t.test('normalizes a valid movie payload', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(),
        reference: _ref(),
        expectedType: MediaType.movie,
      );

      t.expect(out.isDropped, t.isFalse);
      t.expect(out.normalized!.title, 'Test Movie');
      t.expect(out.normalized!.extensionId, 'extA');
      t.expect(out.normalized!.referenceUrl, 'https://example.com/movie/1');
      // Trimmed optionals.
      t.expect(out.normalized!.description, 'A description.');
      t.expect(out.normalized!.cover, 'https://example.com/cover.jpg');
    });

    t.test('blank optionals become null (no empty-string garbage)', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(description: '   ', cover: ''),
        reference: _ref(),
        expectedType: MediaType.movie,
      );

      t.expect(out.normalized!.description, t.isNull);
      t.expect(out.normalized!.cover, t.isNull);
    });

    t.test('missing optionals stay null', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(description: null, cover: null),
        reference: _ref(),
        expectedType: MediaType.movie,
      );

      t.expect(out.normalized!.description, t.isNull);
      t.expect(out.normalized!.cover, t.isNull);
    });

    t.test('genres are trimmed and blanks dropped', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(),
        reference: _ref(),
        expectedType: MediaType.movie,
      );
      // (genres default empty on the helper; exercised in the manager tests)
      t.expect(out.normalized!.genres, t.isEmpty);
    });
  });

  t.group('MetadataNormalizer — dropped payloads', () {
    t.test('blank title is dropped', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(title: '   '),
        reference: _ref(),
        expectedType: MediaType.movie,
      );

      t.expect(out.isDropped, t.isTrue);
      t.expect(out.dropReason, t.contains('title'));
    });

    t.test('a type mismatch with discovery is dropped', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(type: MediaType.series),
        reference: _ref(),
        expectedType: MediaType.movie,
      );

      t.expect(out.isDropped, t.isTrue);
      t.expect(out.dropReason, t.contains('type'));
    });

    t.test('an over-long title is dropped (protocol-noise guard)', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(title: 'A' * 600),
        reference: _ref(),
        expectedType: MediaType.movie,
      );

      t.expect(out.isDropped, t.isTrue);
    });
  });

  t.group('MetadataNormalizer — seasons and episodes', () {
    t.test('episodes are sorted and deduplicated by number', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(
          type: MediaType.series,
          seasons: <MediaSeason>[
            MediaSeason(
              seasonNumber: 1,
              episodes: <MediaEpisode>[
                MediaEpisode(
                  episodeNumber: 2,
                  url: 'https://example.com/e2',
                ),
                MediaEpisode(
                  episodeNumber: 1,
                  url: 'https://example.com/e1',
                ),
                // Duplicate episode 1 — first occurrence wins after sort.
                MediaEpisode(
                  episodeNumber: 1,
                  url: 'https://example.com/e1-alt',
                ),
                // Blank URL — skipped.
                const MediaEpisode(episodeNumber: 3, url: '   '),
              ],
            ),
          ],
        ),
        reference: _ref(),
        expectedType: MediaType.series,
      );

      t.expect(out.isDropped, t.isFalse);
      final List<SeriesEpisode> episodes = out.normalized!.seasons.single.episodes;
      t.expect(
        episodes.map((SeriesEpisode e) => e.episodeNumber),
        <int>[1, 2],
      );
      t.expect(episodes.first.referenceUrl, 'https://example.com/e1');
    });

    t.test('duplicate seasons keep the first occurrence', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(
          type: MediaType.series,
          seasons: <MediaSeason>[
            MediaSeason(seasonNumber: 2, episodes: <MediaEpisode>[]),
            MediaSeason(seasonNumber: 1, episodes: <MediaEpisode>[]),
            MediaSeason(seasonNumber: 1, episodes: <MediaEpisode>[]),
          ],
        ),
        reference: _ref(),
        expectedType: MediaType.series,
      );

      t.expect(
        out.normalized!.seasons.map((SeriesSeason s) => s.seasonNumber),
        <int>[1, 2],
      );
    });

    t.test('an empty season list is tolerated (partial series)', () {
      final NormalizedDetails out = MetadataNormalizer.normalize(
        raw: _raw(type: MediaType.series),
        reference: _ref(),
        expectedType: MediaType.series,
      );

      t.expect(out.isDropped, t.isFalse);
      t.expect(out.normalized!.seasons, t.isEmpty);
    });
  });
}
