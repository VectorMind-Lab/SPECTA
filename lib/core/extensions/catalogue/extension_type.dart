/// Extension content type â€” the category of content an extension provides.
///
/// Existing movie/series scopes remain stable. Anime is an additive scope;
/// it is never inferred from a title or a provider URL.
enum ExtensionContentType {
  /// Movies only.
  movie('movie'),

  /// TV series only.
  series('series'),

  /// Anime only.
  anime('anime'),

  /// Both movies and TV series.
  moviesSeries('movies_series'),

  /// Movies, TV series, and anime.
  moviesSeriesAnime('movies_series_anime');

  const ExtensionContentType(this.code);

  /// Stable string identifier used in manifests and persistence.
  final String code;

  /// Whether this scope can provide [mediaType].
  ///
  /// The legacy `movies_series` scope deliberately does not imply anime.
  bool supports(String mediaType) => switch (this) {
    ExtensionContentType.movie => mediaType == 'movie',
    ExtensionContentType.series => mediaType == 'series',
    ExtensionContentType.anime => mediaType == 'anime',
    ExtensionContentType.moviesSeries =>
      mediaType == 'movie' || mediaType == 'series',
    ExtensionContentType.moviesSeriesAnime =>
      mediaType == 'movie' || mediaType == 'series' || mediaType == 'anime',
  };

  /// Parse a [code] string into an [ExtensionContentType].
  ///
  /// Returns null for unrecognised codes so callers can handle future
  /// extension types gracefully rather than crashing.
  static ExtensionContentType? fromCode(String code) {
    for (final ExtensionContentType type in ExtensionContentType.values) {
      if (type.code == code) return type;
    }
    return null;
  }

  /// Resolves a comma-separated manifest `@type` value into an
  /// [ExtensionContentType].
  ///
  /// `movies,series` remains the legacy combined scope. `anime` is only
  /// accepted when explicitly declared; the legacy combined scope does not
  /// silently gain anime support.
  static ExtensionContentType? fromManifestType(String rawType) {
    final List<String> tokens = rawType
        .split(',')
        .map((String t) => t.trim().toLowerCase())
        .where((String t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return null;
    if (tokens.length == 1) return fromCode(tokens.first);

    final Set<String> normalised = <String>{};
    for (final String token in tokens) {
      if (token == 'movies') {
        normalised.add('movie');
      } else if (token == 'series' || token == 'anime') {
        normalised.add(token);
      } else {
        return null;
      }
    }

    if (normalised.length == 1) return fromCode(normalised.first);
    if (normalised.length == 2 &&
        normalised.contains('movie') &&
        normalised.contains('series')) {
      return ExtensionContentType.moviesSeries;
    }
    if (normalised.length == 3 &&
        normalised.contains('movie') &&
        normalised.contains('series') &&
        normalised.contains('anime')) {
      return ExtensionContentType.moviesSeriesAnime;
    }
    return null;
  }
}
