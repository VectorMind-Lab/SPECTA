import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

import 'metadata_models.dart';

/// The outcome of normalizing one raw [MediaDetails] payload.
///
/// Validation failures are DATA, never thrown into the manager: a reference
/// whose payload cannot be trusted produces [normalized] == null with a
/// reason, and the manager records that per reference without affecting any
/// other reference.
final class NormalizedDetails {
  const NormalizedDetails._({this.normalized, this.dropReason});

  final ReferenceMetadata? normalized;
  final String? dropReason;

  bool get isDropped => normalized == null;

  static NormalizedDetails ok(ReferenceMetadata metadata) =>
      NormalizedDetails._(normalized: metadata);

  static NormalizedDetails dropped(String reason) =>
      NormalizedDetails._(dropReason: reason);
}

/// Central SPECTA normalization/validation for `details()` payloads.
///
/// Validation policy (deliberate, documented, testable):
///
/// DROPPED (payload cannot be trusted — SPECTA never invents or repairs):
/// - blank title or blank reference URL,
/// - type mismatch with the expected type (a series payload answering a
///   movie request — or vice versa — is provider confusion, not data),
/// - title/reference longer than 512 characters (protocol-noise guard,
///   mirroring the discovery layer).
///
/// TOLERATED (kept safely):
/// - missing optional fields (overview, backdrop, genres, rating, runtime,
///   status, seasons),
/// - empty season lists (a series whose extension returned no seasons yet —
///   a legitimate partial payload, recorded as partial, not failure),
/// - duplicate episode rows (per-reference deduplication by episode number),
/// - unsorted episodes (sorted canonically here),
/// - season/episode titles missing.
///
/// Consistency policy: seasons keep only episodes whose seasonNumber matches
/// their season row when the row declares one, and episode rows are
/// re-parented by their own seasonNumber when present so a flat `episodes`
/// structure from a lazy provider still lands in the right season.
abstract final class MetadataNormalizer {
  /// Maximum accepted length for titles and references.
  static const int maxFieldLength = 512;

  /// Normalizes one raw [MediaDetails] payload for [reference].
  ///
  /// [expectedType] is the type the discovery layer observed for the work.
  /// A payload that disagrees with it is dropped.
  static NormalizedDetails normalize({
    required MediaDetails raw,
    required DiscoveryReference reference,
    required MediaType expectedType,
  }) {
    final String title = raw.title.trim();
    final String url = reference.url.trim();

    if (title.isEmpty) return NormalizedDetails.dropped('blank title');
    if (url.isEmpty) return NormalizedDetails.dropped('blank reference url');
    if (title.length > maxFieldLength) {
      return NormalizedDetails.dropped('title exceeds $maxFieldLength chars');
    }
    if (url.length > maxFieldLength) {
      return NormalizedDetails.dropped('reference exceeds $maxFieldLength chars');
    }
    if (raw.type != expectedType) {
      return NormalizedDetails.dropped(
        'payload type ${raw.type.code} != expected ${expectedType.code}',
      );
    }

    return NormalizedDetails.ok(
      ReferenceMetadata(
        extensionId: reference.extensionId,
        referenceUrl: url,
        title: title,
        originalTitle: _cleanOptional(raw.originalTitle),
        cover: _cleanOptional(raw.cover),
        backdrop: _cleanOptional(raw.backdrop),
        description: _cleanOptional(raw.description),
        genres: _cleanGenres(raw.genres),
        durationSeconds: raw.durationSeconds,
        rating: raw.rating,
        status: raw.status,
        seasons: _normalizeSeasons(raw.seasons),
      ),
    );
  }

  static String? _cleanOptional(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _cleanGenres(List<String> raw) => raw
      .map((String g) => g.trim())
      .where((String g) => g.isNotEmpty)
      .toList(growable: false);

  /// Seasons sorted ascending; malformed negative numbers tolerated as-is
  /// (provider data, not SPECTA's to renumber) but duplicates by season
  /// number keep the first occurrence.
  static List<SeriesSeason> _normalizeSeasons(List<MediaSeason> raw) {
    if (raw.isEmpty) return const <SeriesSeason>[];

    final List<MediaSeason> sorted = <MediaSeason>[...raw]
      ..sort((MediaSeason a, MediaSeason b) =>
          a.seasonNumber.compareTo(b.seasonNumber));

    final List<SeriesSeason> seasons = <SeriesSeason>[];
    int? lastSeasonNumber;
    for (final MediaSeason season in sorted) {
      if (lastSeasonNumber == season.seasonNumber) continue; // duplicate season
      lastSeasonNumber = season.seasonNumber;
      seasons.add(
        SeriesSeason(
          seasonNumber: season.seasonNumber,
          title: _cleanOptional(season.title),
          episodes: _normalizeEpisodes(season.seasonNumber, season.episodes),
        ),
      );
    }
    return seasons;
  }

  /// Episodes sorted by episode number, deduplicated per number (first wins),
  /// with malformed rows (empty URL) skipped.
  static List<SeriesEpisode> _normalizeEpisodes(
    int seasonNumber,
    List<MediaEpisode> raw,
  ) {
    if (raw.isEmpty) return const <SeriesEpisode>[];

    final List<MediaEpisode> sorted = <MediaEpisode>[...raw]
      ..sort((MediaEpisode a, MediaEpisode b) =>
          a.episodeNumber.compareTo(b.episodeNumber));

    final List<SeriesEpisode> episodes = <SeriesEpisode>[];
    int? lastEpisodeNumber;
    for (final MediaEpisode episode in sorted) {
      final String url = episode.url.trim();
      if (url.isEmpty) continue;
      if (lastEpisodeNumber == episode.episodeNumber) continue;
      lastEpisodeNumber = episode.episodeNumber;
      episodes.add(
        SeriesEpisode(
          seasonNumber: seasonNumber,
          episodeNumber: episode.episodeNumber,
          referenceUrl: url,
          title: _cleanOptional(episode.title),
          description: _cleanOptional(episode.description),
          cover: _cleanOptional(episode.cover),
          durationSeconds: episode.durationSeconds,
        ),
      );
    }
    return episodes;
  }
}
