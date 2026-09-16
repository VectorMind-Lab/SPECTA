/// Extension content type — the category of content an extension provides.
///
/// SPECTA's Phase 1 architecture is scoped to movie and series discovery.
/// The enum is a sealed vocabulary: do not add types for anime, comics, novels,
/// or other content systems until those phases are agreed and scoped.
enum ExtensionContentType {
  /// Movies only.
  movie('movie'),

  /// TV series only.
  series('series'),

  /// Both movies and TV series.
  moviesSeries('movies_series');

  const ExtensionContentType(this.code);

  /// Stable string identifier used in manifests and persistence.
  final String code;

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
  /// The manifest header may list individual types as comma-separated tokens
  /// (e.g. `movies,series` or `movie,series`).  This helper accepts both the
  /// long-form codes (`movies_series`) and comma-separated short-form tokens,
  /// mapping `movie` + `series` to [moviesSeries].
  ///
  /// Returns null when one or more tokens are unrecognised.
  static ExtensionContentType? fromManifestType(String rawType) {
    final List<String> tokens = rawType
        .split(',')
        .map((String t) => t.trim().toLowerCase())
        .where((String t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return null;

    // Long-form code (e.g. "movies_series") maps directly.
    if (tokens.length == 1) {
      final ExtensionContentType? direct = fromCode(tokens.first);
      if (direct != null) return direct;
    }

    // Normalise plural aliases to singular MediaType codes understood by the
    // extension contract.
    final Set<String> normalised = <String>{};
    for (final String token in tokens) {
      if (token == 'movies') {
        normalised.add('movie');
      } else if (token == 'series') {
        normalised.add('series');
      } else {
        return null;
      }
    }

    if (normalised.length == 1) {
      return fromCode(normalised.first);
    }

    // Both movie and series present → the combined type.
    if (normalised.length == 2) {
      return ExtensionContentType.moviesSeries;
    }

    return null;
  }
}
