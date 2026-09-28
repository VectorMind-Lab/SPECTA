/// Immutable TMDB configuration for one request round (Phase 3).
///
/// The API key is a developer-owned app secret baked in at build time via
/// `--dart-define=TMDB_API_KEY=...` and read here through
/// [tmdb_providers.appTmdbApiKey]. It is never entered in Settings, never
/// persisted in the local database, never read from an asset or extension,
/// never logged, and never handed to an extension runtime.
final class TmdbConfig {
  const TmdbConfig({
    this.apiKey,
    this.language = defaultLanguage,
    this.includeAdult = false,
    this.apiBaseUrl = defaultApiBaseUrl,
    this.imageBaseUrl = defaultImageBaseUrl,
    this.requestTimeout = defaultRequestTimeout,
  });

  /// TMDB REST base. v3 endpoints, e.g. `GET {base}/movie/popular`.
  static const String defaultApiBaseUrl = 'https://api.themoviedb.org/3';

  /// TMDB image CDN base. Image paths from responses are appended to a size
  /// segment: `{base}/w500/{poster_path}` (see `TmdbImage`).
  static const String defaultImageBaseUrl = 'https://image.tmdb.org/t/p';

  /// Catalogue language requested from TMDB (`xx-YY`).
  static const String defaultLanguage = 'en-US';

  /// Bounded deadline for one TMDB request. Short enough that a stalled
  /// connection cannot hang a surface, long enough for a slow mobile network.
  static const Duration defaultRequestTimeout = Duration(seconds: 12);

  /// The stored API key, or null when the catalogue is not configured.
  final String? apiKey;

  final String language;

  /// Whether TMDB may include adult titles. SPECTA's default is NO; the value
  /// is a configuration field so a future settings toggle does not require a
  /// model change.
  final bool includeAdult;

  final String apiBaseUrl;
  final String imageBaseUrl;
  final Duration requestTimeout;

  /// True when a usable key is present. Blank/whitespace keys are treated as
  /// absent so a stray space can never look configured.
  bool get isConfigured => normalizedKey != null;

  /// The key without surrounding whitespace, or null when absent/blank.
  String? get normalizedKey {
    final String? key = apiKey?.trim();
    if (key == null || key.isEmpty) return null;
    return key;
  }

  /// The key reduced to its last 4 characters for display, e.g. `••••a1b2`.
  ///
  /// Never returns the full key and never returns more than 4 real
  /// characters. Provided for developer diagnostics only — the build-time
  /// credential is never shown on a user-facing screen.
  String? get maskedKey {
    final String? key = normalizedKey;
    if (key == null) return null;
    final String tail = key.length <= 4 ? key : key.substring(key.length - 4);
    return '$_mask$tail';
  }

  /// Fixed-width mask (Dart has no string repeat operator).
  static const String _mask =
      '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';

  /// Whether [candidate] looks like a TMDB API credential: a v3 key (32
  /// hexadecimal characters) or a v4 read-access token (a JWT, `eyJ…`).
  ///
  /// This is build-config shape validation, not
  /// authentication — only TMDB can say whether a key is valid, and an invalid
  /// one is reported honestly as [TmdbFailureType.invalidKey] on first use.
  static bool looksLikeApiKey(String candidate) {
    final String value = candidate.trim();
    if (value.length == 32 && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value)) {
      return true;
    }
    return value.startsWith('eyJ') && value.length > 40;
  }

  TmdbConfig copyWith({
    String? apiKey,
    bool clearApiKey = false,
    String? language,
    bool? includeAdult,
    String? apiBaseUrl,
    String? imageBaseUrl,
    Duration? requestTimeout,
  }) {
    return TmdbConfig(
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      language: language ?? this.language,
      includeAdult: includeAdult ?? this.includeAdult,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      imageBaseUrl: imageBaseUrl ?? this.imageBaseUrl,
      requestTimeout: requestTimeout ?? this.requestTimeout,
    );
  }

  @override
  String toString() {
    // Deliberately key-free: it is safe to interpolate this object into a log.
    final String keyState = isConfigured ? 'configured' : 'absent';
    return 'TmdbConfig(key: $keyState, language: $language, '
        'adult: $includeAdult)';
  }
}
