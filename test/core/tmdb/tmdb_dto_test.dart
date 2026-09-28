import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';

/// A complete, valid TMDB movie summary payload.
Map<String, Object?> _movieSummary() => <String, Object?>{
  'id': 603,
  'media_type': 'movie',
  'title': '  The Matrix  ',
  'original_title': 'The Matrix',
  'overview': ' A hacker discovers the truth. ',
  'release_date': '1999-03-30',
  'vote_average': 8.2,
  'vote_count': 22000,
  'popularity': 61.4,
  'genre_ids': <Object?>[28, 878, '18', 4.5],
  'poster_path': '/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg',
  'backdrop_path': '/l4QHerTSbMI7qgvasqxP36pqjN6.jpg',
};

/// A complete, valid TMDB series summary payload (note `tv` field names).
Map<String, Object?> _seriesSummary() => <String, Object?>{
  'id': 1396,
  'media_type': 'tv',
  'name': 'Breaking Bad',
  'original_name': 'Breaking Bad',
  'overview': 'A chemistry teacher turns to crime.',
  'first_air_date': '2008-01-20',
  'vote_average': 8.9,
  'vote_count': 13000,
  'popularity': 350.1,
  'genre_ids': <Object?>[18, 80],
  'poster_path': '/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
};

void main() {
  group('TmdbMediaSummary.fromJson', () {
    test('parses a valid movie summary', () {
      final TmdbMediaSummary? summary = TmdbMediaSummary.fromJson(
        _movieSummary(),
      );

      expect(summary, isNotNull);
      expect(
        summary!.identity,
        const SpectaMediaIdentity(type: MediaType.movie, tmdbId: 603),
      );
      expect(summary.title, 'The Matrix'); // trimmed
      expect(summary.originalTitle, 'The Matrix');
      expect(summary.overview, 'A hacker discovers the truth.');
      expect(summary.year, 1999);
      expect(summary.posterPath, '/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg');
      expect(summary.backdropPath, '/l4QHerTSbMI7qgvasqxP36pqjN6.jpg');
      expect(summary.voteAverage, 8.2);
      expect(summary.voteCount, 22000);
      expect(summary.popularity, 61.4);
      // Non-int entries (string '18', double 4.5) are dropped, never thrown on.
      expect(summary.genreIds, <int>[28, 878]);
    });

    test('parses a valid series summary using tv field names', () {
      final TmdbMediaSummary? summary = TmdbMediaSummary.fromJson(
        _seriesSummary(),
      );

      expect(summary, isNotNull);
      expect(
        summary!.identity,
        const SpectaMediaIdentity(type: MediaType.series, tmdbId: 1396),
      );
      expect(summary.title, 'Breaking Bad');
      expect(summary.year, 2008);
      expect(summary.genreIds, <int>[18, 80]);
    });

    test('forcedType resolves the type when media_type is absent', () {
      final Map<String, Object?> json = _movieSummary()..remove('media_type');
      final TmdbMediaSummary? summary = TmdbMediaSummary.fromJson(
        json,
        forcedType: MediaType.movie,
      );

      expect(summary, isNotNull);
      expect(summary!.identity.type, MediaType.movie);
    });

    test(
      'a movie payload read as a series yields null (wrong title field)',
      () {
        // Movie payloads carry `title`, not `name`; under MediaType.series the
        // name field is missing → honestly rejected, not misparsed.
        final Map<String, Object?> json = _movieSummary()
          ..['media_type'] = 'tv';
        expect(TmdbMediaSummary.fromJson(json), isNull);
      },
    );

    test('invalid id values are rejected', () {
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'id': 0,
        }),
        isNull,
      );
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'id': -5,
        }),
        isNull,
      );
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'id': '603',
        }),
        isNull,
      );
    });

    test('missing or blank title is rejected', () {
      expect(
        TmdbMediaSummary.fromJson(
          <String, Object?>{..._movieSummary()}..remove('title'),
        ),
        isNull,
      );
      expect(
        TmdbMediaSummary.fromJson(
          <String, Object?>{..._movieSummary()}..['title'] = '   ',
        ),
        isNull,
      );
    });

    test('unknown media_type is rejected (person pages in multi-search)', () {
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'media_type': 'person',
        }),
        isNull,
      );
      expect(
        TmdbMediaSummary.fromJson(
          <String, Object?>{..._movieSummary()}..remove('media_type'),
        ),
        isNull,
      );
    });

    test('wrong-typed fields degrade to null instead of throwing', () {
      final TmdbMediaSummary? summary = TmdbMediaSummary.fromJson(
        <String, Object?>{
          ..._movieSummary(),
          'release_date': 19990330, // number where a string belongs
          'overview': 42,
          'vote_average': '8.2', // string where a number belongs
          'vote_count': 'many',
          'popularity': 'high',
          'genre_ids': 'not-a-list',
        },
      );

      expect(summary, isNotNull);
      expect(summary!.year, isNull);
      expect(summary.overview, isNull);
      expect(summary.voteAverage, isNull);
      expect(summary.voteCount, isNull);
      expect(summary.popularity, isNull);
      expect(summary.genreIds, isEmpty);
    });

    test('year derives only from a plausible 4-digit date prefix', () {
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'release_date': '1999',
        })!.year,
        1999,
      );
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'release_date': '',
        })!.year,
        isNull,
      );
      expect(
        TmdbMediaSummary.fromJson(<String, Object?>{
          ..._movieSummary(),
          'release_date': 'ab-cd',
        })!.year,
        isNull,
      );
    });
  });

  group('TmdbMediaPage.fromJson', () {
    test('parses a full page', () {
      final TmdbMediaPage page = TmdbMediaPage.fromJson(<String, Object?>{
        'page': 2,
        'total_pages': 50,
        'total_results': 1000,
        'results': <Object?>[_movieSummary(), _seriesSummary()],
      });

      expect(page.page, 2);
      expect(page.totalPages, 50);
      expect(page.totalResults, 1000);
      expect(page.results, hasLength(2));
      expect(page.results.first.identity.type, MediaType.movie);
      expect(page.results.last.identity.type, MediaType.series);
    });

    test('missing pagination fields fall back to sane defaults', () {
      final TmdbMediaPage page = TmdbMediaPage.fromJson(<String, Object?>{
        'results': <Object?>[],
      });

      expect(page.page, 1);
      expect(page.totalPages, 1);
      expect(page.totalResults, 0);
      expect(page.results, isEmpty);
    });

    test('wrong-typed pagination fields fall back instead of throwing', () {
      final TmdbMediaPage page = TmdbMediaPage.fromJson(<String, Object?>{
        'page': '2',
        'total_pages': '50',
        'total_results': '1000',
        'results': <Object?>[],
      });

      expect(page.page, 1);
      expect(page.totalPages, 1);
      expect(page.totalResults, 0);
    });

    test('malformed result rows are dropped, valid ones kept', () {
      final TmdbMediaPage page = TmdbMediaPage.fromJson(<String, Object?>{
        'page': 1,
        'results': <Object?>[
          'not-a-map',
          <String, Object?>{'id': 0}, // invalid id
          <String, Object?>{'title': 'no id or type'},
          _movieSummary(),
        ],
      });

      expect(page.results, hasLength(1));
      expect(page.results.single.title, 'The Matrix');
    });

    test('a results field that is not a list yields an empty page', () {
      final TmdbMediaPage page = TmdbMediaPage.fromJson(<String, Object?>{
        'results': 'oops',
      });
      expect(page.results, isEmpty);
    });

    test('forcedType applies to rows without media_type', () {
      final Map<String, Object?> bare = _movieSummary()..remove('media_type');
      final TmdbMediaPage page = TmdbMediaPage.fromJson(<String, Object?>{
        'results': <Object?>[bare],
      }, forcedType: MediaType.movie);
      expect(page.results.single.identity.type, MediaType.movie);
    });
  });

  group('TmdbImageUrl.build', () {
    test('builds a sized image URL', () {
      expect(
        TmdbImageUrl.build(
          path: '/poster.jpg',
          imageBaseUrl: 'https://image.tmdb.org/t/p',
          size: TmdbImageSize.posterLarge,
        ),
        'https://image.tmdb.org/t/p/w500/poster.jpg',
      );
    });

    test('normalizes base and path slashes', () {
      expect(
        TmdbImageUrl.build(
          path: 'poster.jpg', // no leading slash
          imageBaseUrl: 'https://image.tmdb.org/t/p/', // trailing slash
          size: TmdbImageSize.backdropMedium,
        ),
        'https://image.tmdb.org/t/p/w780/poster.jpg',
      );
    });

    test('null or blank path yields null (no broken image URLs)', () {
      expect(
        TmdbImageUrl.build(path: null, imageBaseUrl: 'https://x.test'),
        isNull,
      );
      expect(
        TmdbImageUrl.build(path: '   ', imageBaseUrl: 'https://x.test'),
        isNull,
      );
    });
  });

  group('TmdbEpisodeDetails.fromJson', () {
    test('parses a valid episode', () {
      final TmdbEpisodeDetails? episode = TmdbEpisodeDetails.fromJson(
        <String, Object?>{
          'id': 620111,
          'episode_number': 3,
          'season_number': 1,
          'name': "  ...And the Bag's in the River  ",
          'overview': ' Suspicion grows. ',
          'still_path': '/still.jpg',
          'air_date': '2008-02-10',
          'vote_average': 8.0,
          'runtime': 48,
        },
      );

      expect(episode, isNotNull);
      expect(episode!.id, 620111);
      expect(episode.episodeNumber, 3);
      expect(episode.seasonNumber, 1);
      expect(episode.name, "...And the Bag's in the River");
      expect(episode.overview, 'Suspicion grows.');
      expect(episode.runtimeMinutes, 48);
    });

    test('season 0 (specials) is valid; negative season is rejected', () {
      final Map<String, Object?> base = <String, Object?>{
        'id': 1,
        'episode_number': 1,
        'season_number': 0,
        'name': 'Special',
      };
      expect(TmdbEpisodeDetails.fromJson(base), isNotNull);
      expect(
        TmdbEpisodeDetails.fromJson({...base, 'season_number': -1}),
        isNull,
      );
    });

    test('invalid ids, episode numbers and blank names are rejected', () {
      final Map<String, Object?> base = <String, Object?>{
        'id': 1,
        'episode_number': 1,
        'season_number': 1,
        'name': 'Pilot',
      };
      expect(TmdbEpisodeDetails.fromJson({...base, 'id': 0}), isNull);
      expect(
        TmdbEpisodeDetails.fromJson({...base, 'episode_number': 0}),
        isNull,
      );
      expect(TmdbEpisodeDetails.fromJson({...base, 'name': '  '}), isNull);
      expect(TmdbEpisodeDetails.fromJson({...base, 'id': 'x'}), isNull);
    });

    test('wrong-typed numeric fields degrade to null', () {
      final TmdbEpisodeDetails? episode = TmdbEpisodeDetails.fromJson(
        <String, Object?>{
          'id': 1,
          'episode_number': 1,
          'season_number': 1,
          'name': 'Pilot',
          'vote_average': 'high',
          'runtime': 48.5, // double where TMDB documents an int
          'air_date': 20080120,
        },
      );

      expect(episode, isNotNull);
      expect(episode!.voteAverage, isNull);
      expect(episode.runtimeMinutes, isNull);
      expect(episode.airDate, isNull);
    });
  });

  group('TmdbSeasonDetails.fromJson', () {
    test('parses a season and keeps only valid episodes', () {
      final TmdbSeasonDetails? season = TmdbSeasonDetails.fromJson(
        <String, Object?>{
          'id': 620100,
          'season_number': 1,
          'name': ' Season 1 ',
          'overview': ' The beginning. ',
          'poster_path': '/season1.jpg',
          'air_date': '2008-01-20',
          'episodes': <Object?>[
            <String, Object?>{
              'id': 620101,
              'episode_number': 1,
              'season_number': 1,
              'name': 'Pilot',
            },
            <String, Object?>{'id': 0}, // invalid row → dropped
            'garbage',
          ],
        },
      );

      expect(season, isNotNull);
      expect(season!.id, 620100);
      expect(season.name, 'Season 1');
      expect(season.episodes, hasLength(1));
      expect(season.episodes.single.name, 'Pilot');
    });

    test('invalid season identity is rejected', () {
      final Map<String, Object?> base = <String, Object?>{
        'id': 620100,
        'season_number': 1,
        'name': 'Season 1',
      };
      expect(TmdbSeasonDetails.fromJson({...base, 'id': -1}), isNull);
      expect(TmdbSeasonDetails.fromJson({...base, 'name': ' '}), isNull);
      expect(
        TmdbSeasonDetails.fromJson({...base, 'season_number': -1}),
        isNull,
      );
    });

    test('missing episodes list yields an empty season', () {
      final TmdbSeasonDetails? season = TmdbSeasonDetails.fromJson(
        <String, Object?>{'id': 620100, 'season_number': 2, 'name': 'Season 2'},
      );
      expect(season, isNotNull);
      expect(season!.episodes, isEmpty);
    });
  });

  group('TmdbSeasonSummary.fromJson', () {
    test('parses a season summary', () {
      final TmdbSeasonSummary? summary = TmdbSeasonSummary.fromJson(
        <String, Object?>{
          'id': 620100,
          'season_number': 1,
          'name': 'Season 1',
          'episode_count': 7,
          'poster_path': '/s1.jpg',
          'air_date': '2008-01-20',
        },
      );

      expect(summary, isNotNull);
      expect(summary!.episodeCount, 7);
      expect(summary.seasonNumber, 1);
    });

    test('missing or wrong-typed episode_count defaults to 0', () {
      expect(
        TmdbSeasonSummary.fromJson(<String, Object?>{
          'id': 1,
          'season_number': 1,
          'name': 'Season 1',
        })!.episodeCount,
        0,
      );
      expect(
        TmdbSeasonSummary.fromJson(<String, Object?>{
          'id': 1,
          'season_number': 1,
          'name': 'Season 1',
          'episode_count': 'seven',
        })!.episodeCount,
        0,
      );
    });

    test('invalid season identity is rejected', () {
      expect(
        TmdbSeasonSummary.fromJson(<String, Object?>{
          'id': 0,
          'season_number': 1,
          'name': 'Season 1',
        }),
        isNull,
      );
      expect(
        TmdbSeasonSummary.fromJson(<String, Object?>{
          'id': 1,
          'season_number': 1,
          'name': '',
        }),
        isNull,
      );
    });
  });

  group('TmdbMediaDetails.fromJson', () {
    test('parses movie details', () {
      final TmdbMediaDetails? details = TmdbMediaDetails.fromJson(
        <String, Object?>{
          'id': 603,
          'title': 'The Matrix',
          'original_title': 'The Matrix',
          'overview': 'A hacker discovers the truth.',
          'release_date': '1999-03-30',
          'poster_path': '/poster.jpg',
          'backdrop_path': '/backdrop.jpg',
          'vote_average': 8.2,
          'vote_count': 22000,
          'status': 'Released',
          'tagline': ' Welcome to the real world. ',
          'genres': <Object?>[
            <String, Object?>{'name': ' Action '},
            <String, Object?>{'name': 'Sci-Fi'},
            <String, Object?>{'id': 878}, // no name → dropped
            'garbage',
          ],
          'runtime': 136,
        },
        type: MediaType.movie,
      );

      expect(details, isNotNull);
      expect(
        details!.identity,
        const SpectaMediaIdentity(type: MediaType.movie, tmdbId: 603),
      );
      expect(details.year, 1999);
      expect(details.runtimeMinutes, 136);
      expect(details.genres, <String>['Action', 'Sci-Fi']);
      expect(details.tagline, 'Welcome to the real world.');
      expect(details.seasons, isEmpty); // movies carry no seasons
    });

    test('parses series details with seasons', () {
      final TmdbMediaDetails? details = TmdbMediaDetails.fromJson(
        <String, Object?>{
          'id': 1396,
          'name': 'Breaking Bad',
          'original_name': 'Breaking Bad',
          'first_air_date': '2008-01-20',
          'episode_run_time': <Object?>[45, 47],
          'genres': <Object?>[
            <String, Object?>{'name': 'Drama'},
          ],
          'seasons': <Object?>[
            <String, Object?>{
              'id': 3600,
              'season_number': 1,
              'name': 'Season 1',
              'episode_count': 7,
            },
            <String, Object?>{'id': 0}, // invalid → dropped
          ],
        },
        type: MediaType.series,
      );

      expect(details, isNotNull);
      expect(details!.identity.type, MediaType.series);
      expect(details.runtimeMinutes, 45); // first episode_run_time entry
      expect(details.genres, <String>['Drama']);
      expect(details.seasons, hasLength(1));
      expect(details.seasons.single.episodeCount, 7);
    });

    test('empty episode_run_time yields a null runtime', () {
      final TmdbMediaDetails? details = TmdbMediaDetails.fromJson(
        <String, Object?>{
          'id': 1396,
          'name': 'Breaking Bad',
          'episode_run_time': <Object?>[],
        },
        type: MediaType.series,
      );
      expect(details, isNotNull);
      expect(details!.runtimeMinutes, isNull);
    });

    test('invalid details identity or title is rejected', () {
      expect(
        TmdbMediaDetails.fromJson(<String, Object?>{
          'id': -1,
          'title': 'X',
        }, type: MediaType.movie),
        isNull,
      );
      expect(
        TmdbMediaDetails.fromJson(<String, Object?>{
          'id': 1,
          'title': '   ',
        }, type: MediaType.movie),
        isNull,
      );
      // Series parse requires `name`; a movie-shaped payload must not pass.
      expect(
        TmdbMediaDetails.fromJson(<String, Object?>{
          'id': 603,
          'title': 'The Matrix',
        }, type: MediaType.series),
        isNull,
      );
    });

    test('wrong-typed fields degrade instead of throwing', () {
      final TmdbMediaDetails? details = TmdbMediaDetails.fromJson(
        <String, Object?>{
          'id': 603,
          'title': 'The Matrix',
          'release_date': 19990330,
          'runtime': '136',
          'genres': 'Action',
          'seasons': 'not-a-list',
          'poster_path': 12345,
        },
        type: MediaType.movie,
      );

      expect(details, isNotNull);
      expect(details!.year, isNull);
      expect(details.runtimeMinutes, isNull);
      expect(details.genres, isEmpty);
      expect(details.posterPath, isNull);
    });
  });

  group('SpectaMediaIdentity round trip (used by the catalogue layer)', () {
    test('code and parse are inverse', () {
      const SpectaMediaIdentity identity = SpectaMediaIdentity(
        type: MediaType.movie,
        tmdbId: 603,
      );
      expect(identity.code, 'movie:603');
      expect(SpectaMediaIdentity.parse(identity.code), identity);
      expect(SpectaMediaIdentity.parse('movie:0'), isNull);
      expect(SpectaMediaIdentity.parse('nope:603'), isNull);
      expect(SpectaMediaIdentity.parse(null), isNull);
    });
  });
}
