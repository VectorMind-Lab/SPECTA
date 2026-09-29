/// TMDB genre id -> display name.
///
/// TMDB returns genres in two different shapes and this table closes the gap
/// between them:
///
/// * `/movie/popular` and `/tv/popular` list responses carry ONLY numeric
///   `genre_ids` ([TmdbMediaSummary.genreIds]) - no names;
/// * `/movie/{id}` and `/tv/{id}` detail responses carry the NAMES
///   (`json['genres'][].name`, [TmdbMediaDetails.genres]).
///
/// Home's genre rails are built from list responses (they are what the
/// catalogue round already fetches), so the ids must be resolved locally.
/// The alternative - calling `/genre/movie/list` - would be a NEW fetch path,
/// which the Home-rails brief explicitly rules out, and resolving names
/// per-title through the detail endpoints would cost one request per item.
///
/// These are PROTOCOL CONSTANTS, not content. They are the TMDB vocabulary
/// itself (the same ids and titles TMDB documents), so nothing here is a
/// hand-picked or invented judgement about any title - which is why a table
/// is acceptable where hard-coded content is not.
///
/// The movie and TV namespaces are merged into ONE map on purpose: every id
/// the two vocabularies share (16, 18, 27, 35, 37, 80, 99, 9648, 10749,
/// 10751) carries the same name in both, and the ids that differ
/// (10759, 10762-10768 for TV; 12, 14, 28, 36, 53, 878, 10402, 10752, 10770
/// for movies) appear in only one namespace. A single lookup is therefore
/// unambiguous, and no caller has to pass a media type to get a correct name.
final class TmdbGenres {
  const TmdbGenres._();

  /// Every TMDB genre id SPECTA can name, in TMDB's own wording.
  static const Map<int, String> byId = <int, String>{
    // Movie genres.
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Science Fiction',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',

    // TV genres. Overlapping ids are intentionally absent: they are already
    // above, with the same name, and duplicating them here would only create
    // two places to drift.
    10759: 'Action & Adventure',
    10762: 'Kids',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi & Fantasy',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War & Politics',
  };

  /// The name for [id], or null when TMDB sends a genre this build does not
  /// know.
  ///
  /// Returning null rather than a placeholder is deliberate: an unknown genre
  /// must contribute NOTHING to a rail rather than appear as "Unknown" or a
  /// raw number. TMDB adds genres over time, and a rail labelled with an id
  /// would be worse than a missing rail.
  static String? nameOf(int id) => byId[id];

  /// Resolves [ids] to known genre names, in the order given, with duplicates
  /// and unknown ids removed. Never throws.
  static List<String> namesOf(Iterable<int> ids) {
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final int id in ids) {
      final String? name = nameOf(id);
      if (name == null) continue;
      if (seen.add(name)) names.add(name);
    }
    return List<String>.unmodifiable(names);
  }
}
