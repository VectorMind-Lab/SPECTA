/// Typed result models for extension contract operations.
///
/// These are the data shapes extensions return to SPECTA.  All models are
/// immutable value types.  SPECTA owns normalisation and validation of the
/// data before it reaches any UI layer.
library;

/// Type of media content.
enum MediaType {
  movie('movie'),
  series('series'),
  anime('anime');

  const MediaType(this.code);
  final String code;

  static MediaType? fromCode(String? code) {
    if (code == null) return null;
    for (final MediaType t in MediaType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// External identifiers reported by an extension for a work.
final class ExternalIds {
  const ExternalIds({this.anilistId});

  final int? anilistId;

  /// Parses the defensive contract shape. Only a positive integer is valid.
  static ExternalIds? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final Object? value = raw['anilist'];
    if (value is! int || value <= 0) return null;
    return ExternalIds(anilistId: value);
  }
}

/// Canonical identity helpers for SPECTA-owned media keys.
abstract final class MediaIdentity {
  const MediaIdentity._();

  static String? anilistKey(int id) => id > 0 ? 'anilist:$id' : null;

  static String episodeKey(String mediaKey, int season, int episode) =>
      '$mediaKey|s${season}e$episode';
}

/// Status of a series in production.
enum SeriesStatus {
  ongoing('ongoing'),
  completed('completed'),
  cancelled('cancelled'),
  unknown('unknown');

  const SeriesStatus(this.code);
  final String code;

  static SeriesStatus fromCode(String code) {
    for (final SeriesStatus s in SeriesStatus.values) {
      if (s.code == code) return s;
    }
    return SeriesStatus.unknown;
  }
}

/// A single search result returned by an extension's `search()` or `latest()`.
final class SearchResult {
  const SearchResult({
    required this.title,
    required this.url,
    required this.type,
    this.cover,
    this.year,
    this.externalIds,
  });

  /// Display title.
  final String title;

  /// Extension-internal URL used to fetch [MediaDetails].  SPECTA never
  /// exposes this URL in the user-facing UI (neutral server labels only).
  final String url;

  /// Artwork URL, or null if the extension did not provide one.
  final String? cover;

  /// Release year, or null when unknown.
  final int? year;

  /// Content type.
  final MediaType type;

  /// Optional external work identifiers, including AniList.
  final ExternalIds? externalIds;

  @override
  String toString() => 'SearchResult(title: $title, type: ${type.code})';
}

/// A single episode within a [MediaSeason].
final class MediaEpisode {
  const MediaEpisode({
    required this.episodeNumber,
    required this.url,
    this.title,
    this.description,
    this.cover,
    this.durationSeconds,
  });

  final int episodeNumber;
  final String url;
  final String? title;
  final String? description;
  final String? cover;
  final int? durationSeconds;

  @override
  String toString() => 'MediaEpisode(ep: $episodeNumber)';
}

/// A season of a series.
final class MediaSeason {
  const MediaSeason({
    required this.seasonNumber,
    required this.episodes,
    this.title,
  });

  final int seasonNumber;
  final String? title;
  final List<MediaEpisode> episodes;

  @override
  String toString() => 'MediaSeason(s: $seasonNumber, eps: ${episodes.length})';
}

/// Full metadata for a movie or series returned by an extension's `details()`.
final class MediaDetails {
  const MediaDetails({
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    this.externalIds,
    this.originalTitle,
    this.cover,
    this.backdrop,
    this.year,
    this.description,
    this.genres = const <String>[],
    this.durationSeconds,
    this.rating,
    this.status,
    this.seasons = const <MediaSeason>[],
  });

  /// Extension-internal ID.  SPECTA maps this to its own identity separately.
  final String id;
  final String title;
  final String? originalTitle;
  final MediaType type;
  final String url;
  final ExternalIds? externalIds;
  final String? cover;
  final String? backdrop;
  final int? year;
  final String? description;
  final List<String> genres;
  final int? durationSeconds;
  final double? rating;
  final SeriesStatus? status;

  /// Non-empty for [MediaType.series]; empty for [MediaType.movie].
  final List<MediaSeason> seasons;

  @override
  String toString() => 'MediaDetails(id: $id, title: $title)';
}
