import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';
import 'package:specta/core/tmdb/tmdb_genres.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';
import 'package:specta/features/home/home_genre_rails.dart';

/// A movie carrying [genreIds]. Distinct [title]s give distinct discovery keys,
/// which is what the rails deduplicate on.
TmdbMediaSummary _movie(int id, String title, List<int> genreIds) =>
    TmdbMediaSummary(
      identity: SpectaMediaIdentity(type: MediaType.movie, tmdbId: id),
      title: title,
      releaseDate: '2020-01-01',
      genreIds: genreIds,
    );

TmdbMediaSummary _series(int id, String title, List<int> genreIds) =>
    TmdbMediaSummary(
      identity: SpectaMediaIdentity(type: MediaType.series, tmdbId: id),
      title: title,
      releaseDate: '2021-01-01',
      genreIds: genreIds,
    );

/// [count] distinct movies in [genreId], starting at tmdb id [fromId].
List<TmdbMediaSummary> _moviesIn(int genreId, int count, {int fromId = 1}) =>
    <TmdbMediaSummary>[
      for (int i = 0; i < count; i++)
        _movie(fromId + i, 'Movie ${fromId + i}', <int>[genreId]),
    ];

GenreRails _rails({
  List<TmdbMediaSummary> movies = const <TmdbMediaSummary>[],
  List<TmdbMediaSummary> series = const <TmdbMediaSummary>[],
}) => GenreRails.from(
  movies: movies,
  series: series,
  imageBaseUrl: TmdbConfig.defaultImageBaseUrl,
);

void main() {
  // TMDB genre ids used below, spelled out so the tests read as the real
  // vocabulary rather than as magic numbers.
  const int action = 28;
  const int comedy = 35;
  const int drama = 18;
  const int crime = 80;
  const int thriller = 53;

  group('TmdbGenres', () {
    test('resolves known ids in TMDB wording', () {
      expect(TmdbGenres.nameOf(action), 'Action');
      expect(TmdbGenres.nameOf(10765), 'Sci-Fi & Fantasy');
    });

    test('namesOf drops unknown ids and duplicates, preserving order', () {
      expect(
        TmdbGenres.namesOf(<int>[thriller, 999999, action, thriller, 18]),
        <String>['Thriller', 'Action', 'Drama'],
      );
    });

    test('an unknown id resolves to null rather than a placeholder', () {
      expect(TmdbGenres.nameOf(999999), isNull);
    });
  });

  group('GenreRails - the floor', () {
    test('a genre below the floor is not a rail', () {
      final GenreRails rails = _rails(
        movies: _moviesIn(action, GenreRails.minItemsPerGenre - 1),
      );

      expect(rails.hasRails, isFalse);
      expect(rails.rails, isEmpty);
    });

    test('a genre exactly at the floor becomes a rail', () {
      final GenreRails rails = _rails(
        movies: _moviesIn(action, GenreRails.minItemsPerGenre),
      );

      expect(rails.rails, hasLength(1));
      expect(rails.rails.single.genre, 'Action');
      expect(rails.rails.single.itemCount, GenreRails.minItemsPerGenre);
    });

    test('an item with no genre ids contributes nothing', () {
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[
          for (int i = 0; i < 10; i++)
            _movie(i + 1, 'Untagged $i', const <int>[]),
        ],
      );

      expect(rails.hasRails, isFalse);
    });

    test('an item whose only genre id is unknown contributes nothing', () {
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[
          for (int i = 0; i < 10; i++)
            _movie(i + 1, 'Unknown $i', const <int>[999999]),
        ],
      );

      expect(rails.hasRails, isFalse);
    });
  });

  group('GenreRails - grouping', () {
    test('an item carrying two genres is listed in both rails', () {
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[
          for (int i = 0; i < GenreRails.minItemsPerGenre; i++)
            _movie(i + 1, 'Both $i', <int>[action, thriller]),
        ],
      );

      expect(rails.rails.map((GenreRail r) => r.genre), <String>[
        'Action',
        'Thriller',
      ]);
      expect(rails.rails.every((GenreRail r) => r.itemCount == 5), isTrue);
    });

    test('movies and series pool into the same genre', () {
      final GenreRails rails = _rails(
        movies: _moviesIn(action, 3),
        series: <TmdbMediaSummary>[
          _series(11, 'Series One', <int>[action]),
          _series(12, 'Series Two', <int>[action]),
        ],
      );

      expect(rails.rails, hasLength(1));
      expect(rails.rails.single.itemCount, 5);
    });

    test('a repeated work is listed once, so it cannot inflate a rail', () {
      // Same title, same type, same year means the same discovery key. Ten
      // copies are one work, which is below the floor, so no rail appears.
      final TmdbMediaSummary repeated = _movie(1, 'Same Work', <int>[action]);
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[for (int i = 0; i < 10; i++) repeated],
      );

      expect(rails.hasRails, isFalse);
    });
  });

  group('GenreRails - ordering and cap', () {
    test('the best-populated rail comes first', () {
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[
          ..._moviesIn(comedy, 5, fromId: 1),
          ..._moviesIn(action, 7, fromId: 100),
        ],
      );

      expect(rails.rails.first.genre, 'Action');
      expect(rails.rails.first.itemCount, 7);
      expect(rails.rails.last.genre, 'Comedy');
    });

    test('equal populations are ordered by genre name, deterministically', () {
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[
          ..._moviesIn(thriller, 5, fromId: 1),
          ..._moviesIn(action, 5, fromId: 100),
          ..._moviesIn(drama, 5, fromId: 200),
        ],
      );

      expect(rails.rails.map((GenreRail r) => r.genre), <String>[
        'Action',
        'Drama',
        'Thriller',
      ]);
    });

    test('no more than maxRails rails are returned', () {
      final GenreRails rails = _rails(
        movies: <TmdbMediaSummary>[
          ..._moviesIn(action, 5, fromId: 1),
          ..._moviesIn(comedy, 5, fromId: 100),
          ..._moviesIn(drama, 5, fromId: 200),
          ..._moviesIn(crime, 5, fromId: 300),
          ..._moviesIn(thriller, 5, fromId: 400),
        ],
      );

      expect(rails.rails, hasLength(GenreRails.maxRails));
      // All five tie at 5, so name order decides which one is dropped.
      expect(rails.rails.map((GenreRail r) => r.genre), <String>[
        'Action',
        'Comedy',
        'Crime',
        'Drama',
      ]);
    });
  });

  group('GenreRails - empty input', () {
    test('no catalogue items means no rails, not an error', () {
      expect(_rails().hasRails, isFalse);
      expect(_rails().rails, isEmpty);
    });
  });
}
