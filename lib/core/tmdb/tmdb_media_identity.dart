import 'package:specta/core/extensions/contract/result_models.dart';

/// SPECTA's canonical catalogue identity for one work (Phase 3).
///
/// TMDB OWNS the catalogue identity: this value is what SPECTA uses to know
/// WHICH movie/series a screen, a detail request or a source-resolution round
/// is about. Extensions never see it and never mint it — they describe
/// provider-side references, which the matcher associates with this identity
/// (see `TmdbProviderMatcher`).
///
/// The media TYPE is part of the identity because TMDB numbers movies and
/// series in separate namespaces: movie 12345 and series 12345 are different
/// works and must never collapse into one item even when they share a title.
///
/// ```dart
/// SpectaMediaIdentity(type: MediaType.movie, tmdbId: 12345) !=
/// SpectaMediaIdentity(type: MediaType.series, tmdbId: 12345)
/// ```
///
/// This identity is DELIBERATELY independent of the evidence-based key
/// (`title|type|year`, see `TitleKey.identityKey`) that watch progress, the
/// library and downloads already persist. That key stays exactly as it is —
/// no schema migration — while this one is the catalogue's own.
final class SpectaMediaIdentity {
  const SpectaMediaIdentity({required this.type, required this.tmdbId});

  /// Movie or series. Reuses the extension contract's [MediaType] — SPECTA has
  /// exactly one movie/series vocabulary and this is not a second one.
  final MediaType type;

  /// TMDB's numeric id for this work, in the namespace of [type].
  final int tmdbId;

  /// Stable, parseable string form: `movie:12345` / `series:12345`.
  ///
  /// Used by routes and by tests; NOT a persistence format (nothing is stored
  /// under it in V1).
  String get code => '${type.code}:$tmdbId';

  /// Parses [code] back into an identity, or null when malformed or when the
  /// id is not a plausible TMDB identifier (TMDB ids are positive).
  static SpectaMediaIdentity? parse(String? code) {
    if (code == null) return null;
    final int separator = code.indexOf(':');
    if (separator <= 0 || separator == code.length - 1) return null;
    final MediaType? type = MediaType.fromCode(code.substring(0, separator));
    final int? id = int.tryParse(code.substring(separator + 1));
    if (type == null || id == null || id <= 0) return null;
    return SpectaMediaIdentity(type: type, tmdbId: id);
  }

  /// The identity of the OTHER media type carrying the same TMDB number.
  /// Exists so the "same number, different namespace" case is trivially
  /// testable and so no caller is tempted to compare bare integers.
  SpectaMediaIdentity get otherType => SpectaMediaIdentity(
    type: type == MediaType.movie ? MediaType.series : MediaType.movie,
    tmdbId: tmdbId,
  );

  bool get isMovie => type == MediaType.movie;
  bool get isSeries => type == MediaType.series;

  @override
  bool operator ==(Object other) =>
      other is SpectaMediaIdentity &&
      other.type == type &&
      other.tmdbId == tmdbId;

  @override
  int get hashCode => Object.hash(type, tmdbId);

  @override
  String toString() => 'SpectaMediaIdentity($code)';
}
