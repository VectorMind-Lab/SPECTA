import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';
import 'package:specta/core/tmdb/tmdb_normalizer.dart';

const String _imageBase = 'https://image.tmdb.org/t/p';

TmdbMediaSummary _summary({
  int id = 603,
  MediaType type = MediaType.movie,
  String title = 'The Matrix',
  int? year = 1999,
  String? posterPath = '/poster.jpg',
}) {
  final String date = year == null ? '' : '$year-03-30';
  return TmdbMediaSummary(
    identity: SpectaMediaIdentity(type: type, tmdbId: id),
    title: title,
    posterPath: posterPath,
    releaseDate: date.isEmpty ? null : date,
  );
}

TmdbMediaDetails _details({
  int id = 1396,
  MediaType type = MediaType.series,
  String title = 'Breaking Bad',
  int? year = 2008,
  String? posterPath = '/poster.jpg',
  String? backdropPath = '/backdrop.jpg',
  String overview = 'A chemistry teacher turns to crime.',
  List<String> genres = const <String>['Drama', 'Crime'],
  int? runtimeMinutes = 45,
  double voteAverage = 8.9,
  List<TmdbSeasonSummary> seasons = const <TmdbSeasonSummary>[],
}) => TmdbMediaDetails(
  identity: SpectaMediaIdentity(type: type, tmdbId: id),
  title: title,
  posterPath: posterPath,
  backdropPath: backdropPath,
  releaseDate: year == null ? null : '$year-01-20',
  overview: overview,
  genres: genres,
  runtimeMinutes: runtimeMinutes,
  voteAverage: voteAverage,
  seasons: seasons,
);

void main() {
  group('TmdbNormalizer.toDiscoveryItem', () {
    test('maps title, type, year and evidence key', () {
      final DiscoveryItem item = TmdbNormalizer.toDiscoveryItem(
        _summary(),
        imageBaseUrl: _imageBase,
      );

      expect(item.title, 'The Matrix');
      expect(item.type, MediaType.movie);
      expect(item.year, 1999);
      // The SAME identity key the library/downloads/watch-progress persist.
      expect(item.key, 'the matrix|movie|1999');
    });

    test('builds a w500 poster cover URL', () {
      final DiscoveryItem item = TmdbNormalizer.toDiscoveryItem(
        _summary(posterPath: '/f89U.jpg'),
        imageBaseUrl: _imageBase,
      );
      expect(item.cover, 'https://image.tmdb.org/t/p/w500/f89U.jpg');
    });

    test('a missing poster yields a null cover, not a broken URL', () {
      final DiscoveryItem item = TmdbNormalizer.toDiscoveryItem(
        _summary(posterPath: null),
        imageBaseUrl: _imageBase,
      );
      expect(item.cover, isNull);
    });

    test('passes through supplied extension references untouched', () {
      const DiscoveryReference reference = DiscoveryReference(
        extensionId: 'com.ext.one',
        url: 'https://ext.one/movie/1',
      );

      final DiscoveryItem item = TmdbNormalizer.toDiscoveryItem(
        _summary(),
        imageBaseUrl: _imageBase,
        references: const <DiscoveryReference>[reference],
      );

      expect(item.references, hasLength(1));
      expect(item.references.single.extensionId, 'com.ext.one');
    });

    test('series summaries map onto the series type', () {
      final DiscoveryItem item = TmdbNormalizer.toDiscoveryItem(
        _summary(type: MediaType.series, id: 1396, title: 'Breaking Bad'),
        imageBaseUrl: _imageBase,
      );
      expect(item.type, MediaType.series);
      expect(item.key, 'breaking bad|series|1999');
    });
  });

  group('TmdbNormalizer.toMetadataItem', () {
    test('maps identity, artwork and synthesizes TMDB provenance', () {
      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        _details(),
        imageBaseUrl: _imageBase,
      );

      expect(item.key, 'breaking bad|series|2008');
      expect(item.title, 'Breaking Bad');
      expect(item.type, MediaType.series);
      expect(item.year, 2008);
      expect(item.cover, 'https://image.tmdb.org/t/p/w500/poster.jpg');
      expect(item.backdrop, 'https://image.tmdb.org/t/p/w1280/backdrop.jpg');

      // With no extension-supplied details, one synthetic TMDB entry carries
      // the whole payload.
      expect(item.details, hasLength(1));
      final ReferenceMetadata tmdb = item.details.single;
      expect(tmdb.extensionId, 'tmdb');
      expect(tmdb.referenceUrl, 'series:1396'); // identity code, not a URL
      expect(tmdb.description, 'A chemistry teacher turns to crime.');
      expect(tmdb.genres, <String>['Drama', 'Crime']);
      expect(tmdb.durationSeconds, 45 * 60);
      expect(tmdb.rating, 8.9);
      expect(tmdb.seasons, isEmpty); // summaries come from details.seasons
    });

    test('season summaries on the details become empty-episode seasons', () {
      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        _details(
          seasons: const <TmdbSeasonSummary>[
            TmdbSeasonSummary(
              id: 3600,
              seasonNumber: 1,
              name: 'Season 1',
              episodeCount: 7,
            ),
            TmdbSeasonSummary(
              id: 3601,
              seasonNumber: 2,
              name: 'Season 2',
              episodeCount: 13,
            ),
          ],
        ),
        imageBaseUrl: _imageBase,
      );

      expect(item.seasons.map((SeriesSeason s) => s.seasonNumber), <int>[1, 2]);
      expect(item.seasons.first.title, 'Season 1');
      // Season list entries are placeholders: episodes come from
      // toSeriesSeason over /tv/{id}/season/{n}.
      expect(item.seasons.first.episodes, isEmpty);
    });

    test('existing extension details are preserved and win over synthesis', () {
      const ReferenceMetadata existing = ReferenceMetadata(
        extensionId: 'com.ext.one',
        referenceUrl: 'https://ext.one/show/1',
        title: 'Breaking Bad (from extension)',
        description: 'Extension-supplied description.',
      );

      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        _details(),
        imageBaseUrl: _imageBase,
        existingDetails: const <ReferenceMetadata>[existing],
      );

      expect(item.details, hasLength(1));
      expect(item.details.single.extensionId, 'com.ext.one');
      expect(
        item.details.single.description,
        'Extension-supplied description.',
      );
      // The canonical title still comes from TMDB â€” the catalogue owns it.
      expect(item.title, 'Breaking Bad');
    });

    test('movies produce no seasons even if seasons were supplied', () {
      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        _details(
          type: MediaType.movie,
          id: 603,
          title: 'The Matrix',
          seasons: const <TmdbSeasonSummary>[
            TmdbSeasonSummary(id: 1, seasonNumber: 1, name: 'Bogus'),
          ],
        ),
        imageBaseUrl: _imageBase,
      );

      expect(item.type, MediaType.movie);
      expect(item.seasons, isEmpty);
    });

    test('a missing poster/backdrop yields null artwork', () {
      final MetadataItem item = TmdbNormalizer.toMetadataItem(
        _details(posterPath: null, backdropPath: null),
        imageBaseUrl: _imageBase,
      );

      expect(item.cover, isNull);
      expect(item.backdrop, isNull);
      expect(item.details.single.cover, isNull);
      expect(item.details.single.backdrop, isNull);
    });
  });

  group('TmdbNormalizer.toSeriesSeason', () {
    TmdbSeasonDetails emptySeason() => TmdbSeasonDetails(
      id: 620100,
      seasonNumber: 1,
      name: 'Season 1',
      episodes: const <TmdbEpisodeDetails>[],
    );

    test('maps episodes with stable tmdb reference URLs', () {
      final TmdbSeasonDetails season = TmdbSeasonDetails(
        id: 620100,
        seasonNumber: 1,
        name: 'Season 1',
        episodes: <TmdbEpisodeDetails>[
          const TmdbEpisodeDetails(
            id: 620101,
            episodeNumber: 1,
            seasonNumber: 1,
            name: 'Pilot',
            overview: 'The pilot episode.',
            stillPath: '/still1.jpg',
            runtimeMinutes: 58,
          ),
          const TmdbEpisodeDetails(
            id: 620102,
            episodeNumber: 2,
            seasonNumber: 1,
            name: "...And the Bag's in the River",
          ),
        ],
      );

      final SeriesSeason out = TmdbNormalizer.toSeriesSeason(
        season,
        imageBaseUrl: _imageBase,
      );

      expect(out.seasonNumber, 1);
      expect(out.title, 'Season 1');
      expect(out.episodes, hasLength(2));

      final SeriesEpisode first = out.episodes.first;
      expect(first.episodeNumber, 1);
      expect(first.seasonNumber, 1);
      expect(first.title, 'Pilot');
      expect(first.description, 'The pilot episode.');
      expect(first.durationSeconds, 58 * 60);
      expect(first.cover, 'https://image.tmdb.org/t/p/w780/still1.jpg');
      expect(first.referenceUrl, 'tmdb:tv:ep:620100:1:1');

      final SeriesEpisode second = out.episodes.last;
      expect(second.durationSeconds, isNull); // absent runtime stays null
      expect(second.cover, isNull);
      expect(second.referenceUrl, 'tmdb:tv:ep:620100:1:2');
    });

    test('an empty season maps to an empty episode list', () {
      final SeriesSeason out = TmdbNormalizer.toSeriesSeason(
        emptySeason(),
        imageBaseUrl: _imageBase,
      );
      expect(out.episodes, isEmpty);
      expect(out.seasonNumber, 1);
    });
  });
}
