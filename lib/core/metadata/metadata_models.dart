import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

/// Canonical SPECTA metadata — the details-layer counterpart of the Phase 2B
/// [DiscoveryItem].
///
/// One logical work (movie or series) as SPECTA canonically sees it, built by
/// the Metadata Manager from a provider's `details(url)` response and merged
/// across every provider reference that could supply it. EXTENSIONS DISCOVER /
/// SPECTA DECIDES: extensions report; SPECTA validates, normalizes, and owns
/// this model.
///
/// Boundary discipline (Phase 2C):
/// - No playback/source information of any kind (2D owns sources).
/// - No watch progress, no download state (2F/2G own those).
/// - No external metadata provider (TMDB etc.) data: this model is built from
///   extension references only. The provider abstraction for TMDB belongs to
///   its own authorization.
final class MetadataItem {
  const MetadataItem({
    required this.key,
    required this.title,
    required this.type,
    required this.details,
    this.year,
    this.cover,
    this.backdrop,
  });

  /// Stable metadata identity. Deterministic: the same normalized
  /// (title, type, year) identity key the discovery layer established for the
  /// item this metadata was loaded for. SPECTA deliberately does NOT invent a
  /// global identity algorithm beyond this evidence-based key.
  final String key;

  /// Canonical display title (normalized; never invented).
  final String title;

  /// Movie or series. Never converted from anything else.
  final MediaType type;

  /// Release year when at least one reference observed one (lowest wins when
  /// references disagree, matching the discovery layer's documented rule).
  final int? year;

  /// Best available artwork among the references (first found wins).
  final String? cover;

  /// Best available backdrop among the references (first found wins).
  final String? backdrop;

  /// Canonical per-reference details. Every reference that successfully
  /// supplied metadata is preserved — one entry per [DiscoveryReference], in
  /// reference order. A reference that failed or supplied nothing has no
  /// entry here, but the reference itself is never discarded.
  final List<ReferenceMetadata> details;

  /// True when more than one reference contributed metadata.
  bool get isCrossReference => details.length > 1;

  /// The series' seasons, flattened from the contributing series details.
  /// Empty for movies.
  List<SeriesSeason> get seasons {
    if (type != MediaType.series) return const <SeriesSeason>[];
    // Prefer the first reference that actually carries seasons.
    for (final ReferenceMetadata r in details) {
      if (r.seasons.isNotEmpty) return r.seasons;
    }
    return const <SeriesSeason>[];
  }

  @override
  String toString() =>
      'MetadataItem($key, type: ${type.code}, refs: ${details.length})';
}

/// One provider reference's metadata contribution — SPECTA-normalized.
///
/// The provider URL is identity/resolution data for later phases and is never
/// rendered in the UI. This is exactly what 2D will need to request sources
/// through the correct extension, and nothing more.
final class ReferenceMetadata {
  const ReferenceMetadata({
    required this.extensionId,
    required this.referenceUrl,
    required this.title,
    this.originalTitle,
    this.cover,
    this.backdrop,
    this.description,
    this.genres = const <String>[],
    this.durationSeconds,
    this.rating,
    this.status,
    this.seasons = const <SeriesSeason>[],
  });

  /// The contributing extension's registry id.
  final String extensionId;

  /// The extension-internal reference the extension expects back through
  /// `details(url)` / later `getSources(reference)`. Never a playback URL.
  final String referenceUrl;

  /// The reference's own title (trimmed). The canonical item's title is
  /// derived from the first contributing reference, falling back to the
  /// discovery-observed title.
  final String title;

  final String? originalTitle;
  final String? cover;
  final String? backdrop;
  final String? description;
  final List<String> genres;
  final int? durationSeconds;
  final double? rating;
  final SeriesStatus? status;

  /// Seasons with their episodes, for series. Empty for movies.
  final List<SeriesSeason> seasons;

  @override
  String toString() =>
      'ReferenceMetadata($extensionId, seasons: ${seasons.length})';
}

/// A canonical season of a series — SPECTA's own normalized shape, detached
/// from any single provider's JSON.
final class SeriesSeason {
  const SeriesSeason({
    required this.seasonNumber,
    required this.episodes,
    this.title,
  });

  final int seasonNumber;
  final String? title;

  /// Episodes in ascending episode-number order, per-reference deduplicated.
  final List<SeriesEpisode> episodes;

  @override
  String toString() =>
      'SeriesSeason(s: $seasonNumber, eps: ${episodes.length})';
}

/// A canonical episode of a series season.
final class SeriesEpisode {
  const SeriesEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.referenceUrl,
    this.title,
    this.description,
    this.cover,
    this.durationSeconds,
  });

  final int seasonNumber;
  final int episodeNumber;

  /// Extension-internal reference (future resolution data; never rendered).
  final String referenceUrl;

  final String? title;
  final String? description;
  final String? cover;
  final int? durationSeconds;

  @override
  String toString() => 'SeriesEpisode(s$seasonNumber:e$episodeNumber)';
}
