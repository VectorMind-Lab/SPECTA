import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_models.dart';
import '../../core/errors/specta_result.dart';
import '../../core/tmdb/tmdb_client.dart';
import '../../core/tmdb/tmdb_config.dart';
import '../../core/tmdb/tmdb_dto.dart';
import '../../core/tmdb/tmdb_genres.dart';
import '../../core/tmdb/tmdb_normalizer.dart';
import '../../core/tmdb/tmdb_providers.dart';

/// One genre rail: a genre name plus the catalogue items that carry it.
final class GenreRail {
  const GenreRail({required this.genre, required this.items});

  /// The genre, in TMDB's own wording (e.g. 'Science Fiction'). It becomes the
  /// rail title verbatim - no "Best of", and no ranking SPECTA does not
  /// compute.
  final String genre;

  final List<DiscoveryItem> items;

  int get itemCount => items.length;
}

/// The genre rails resolved for Home, already filtered, ordered and capped.
///
/// DERIVED FROM THE CATALOGUE, NOT FROM INVENTED RANKING. Every rail is just
/// "the items the catalogue already returned that carry this genre", in the
/// order the catalogue returned them. Nothing is scored, sorted by a metric
/// SPECTA does not have, or back-filled.
final class GenreRails {
  const GenreRails({this.rails = const <GenreRail>[]});

  /// A genre only becomes a rail once at least this many items carry it.
  ///
  /// This is what keeps Home from growing a row of twenty one-item rails:
  /// below the floor a genre is not a section, it is a coincidence.
  static const int minItemsPerGenre = 5;

  /// Home shows at most this many genre rails, best-populated first.
  ///
  /// The primary feed, Continue Watching and Popular come first, so genre
  /// rails are additive discovery - they must never push the real content off
  /// the surface.
  static const int maxRails = 4;

  final List<GenreRail> rails;

  bool get hasRails => rails.isNotEmpty;

  /// Groups catalogue items into genre rails. Pure: no providers, no network,
  /// no clock - so the floor, the ordering and the cap are directly testable.
  ///
  /// An item carrying several genres appears in each of them, which is correct
  /// (a film really is both Action and Thriller). An item carrying no known
  /// genre contributes nothing rather than landing in a catch-all bucket.
  static GenreRails from({
    required List<TmdbMediaSummary> movies,
    required List<TmdbMediaSummary> series,
    required String imageBaseUrl,
  }) {
    final Map<String, List<DiscoveryItem>> buckets =
        <String, List<DiscoveryItem>>{};
    final Map<String, Set<String>> seenKeys = <String, Set<String>>{};

    void absorb(List<TmdbMediaSummary> summaries) {
      for (final TmdbMediaSummary summary in summaries) {
        final List<String> genres = TmdbGenres.namesOf(summary.genreIds);
        if (genres.isEmpty) continue;

        final DiscoveryItem item = TmdbNormalizer.toDiscoveryItem(
          summary,
          imageBaseUrl: imageBaseUrl,
        );

        for (final String genre in genres) {
          // A rail must not list the same work twice, even if the provider
          // returns it in more than one round.
          final Set<String> keys = seenKeys.putIfAbsent(
            genre,
            () => <String>{},
          );
          if (!keys.add(item.key)) continue;
          buckets.putIfAbsent(genre, () => <DiscoveryItem>[]).add(item);
        }
      }
    }

    absorb(movies);
    absorb(series);

    final List<GenreRail> candidates = <GenreRail>[
      for (final MapEntry<String, List<DiscoveryItem>> entry in buckets.entries)
        if (entry.value.length >= minItemsPerGenre)
          GenreRail(
            genre: entry.key,
            items: List<DiscoveryItem>.unmodifiable(entry.value),
          ),
    ];

    // Best-populated first; ties broken by name so the visible order is
    // stable rather than dependent on map iteration order.
    candidates.sort((GenreRail a, GenreRail b) {
      final int byCount = b.itemCount.compareTo(a.itemCount);
      if (byCount != 0) return byCount;
      return a.genre.compareTo(b.genre);
    });

    return GenreRails(
      rails: List<GenreRail>.unmodifiable(candidates.take(maxRails)),
    );
  }
}

/// Home's genre rails, fed by the catalogue round the Popular rail already uses.
///
/// WHY THIS SOURCE. The catalogue list endpoints already return each work's
/// `genre_ids`, so building these rails costs NO per-item metadata request; the
/// one genuinely new request is `/tv/popular`, which is an existing client
/// method on an existing endpoint rather than a new fetch path. The
/// alternative - enriching the extension feed item by item - would cost one
/// metadata round per item on every Home load.
///
/// The trade-off is deliberate, and it is the same one the Popular rail already
/// makes: these are catalogue identities with no extension reference, so they
/// are not playable until SPECTA resolves a source for them. Tapping one opens
/// Details, exactly as Popular does - a genre rail never promises a source it
/// does not have.
///
/// An unreachable or unconfigured provider contributes NOTHING: the rails
/// simply do not appear, and a catalogue outage can never blank or block the
/// real Home feed.
final FutureProvider<GenreRails> homeGenreRailsProvider =
    FutureProvider<GenreRails>((Ref ref) async {
      try {
        final TmdbClient tmdb = ref.watch(tmdbClientProvider);
        final TmdbConfig config = ref.watch(tmdbConfigProvider);

        // Movies AND series, so the pool covers both as the brief requires.
        // `/movie/popular` is normally already warm here because
        // `trendingFeedProvider` requests the same page through the same
        // read-through cache.
        final List<SpectaResult<TmdbMediaPage>> pages = await Future.wait(
          <Future<SpectaResult<TmdbMediaPage>>>[
            tmdb.getPopularMovies(page: 1),
            tmdb.getPopularSeries(page: 1),
          ],
        );

        // Partial failure is not total failure: whatever did answer still
        // contributes its genres.
        final List<TmdbMediaSummary> movies =
            pages[0].valueOrNull?.results ?? const <TmdbMediaSummary>[];
        final List<TmdbMediaSummary> series =
            pages[1].valueOrNull?.results ?? const <TmdbMediaSummary>[];

        if (movies.isEmpty && series.isEmpty) return const GenreRails();

        return GenreRails.from(
          movies: movies,
          series: series,
          imageBaseUrl: config.imageBaseUrl,
        );
      } on Object {
        // Absolute containment: a catalogue problem is an absent rail, never a
        // thrown error reaching the widget tree.
        return const GenreRails();
      }
    });
