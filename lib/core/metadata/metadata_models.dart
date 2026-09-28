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
    this.canonicalId,
    this.identityVersion = 1,
    this.format,
    this.episodeCount,
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

  /// Canonical provider work identity, e.g. `anilist:123`.
  final String? canonicalId;

  /// 1 = legacy title/type/year key; 2 = provider canonical key.
  final int identityVersion;

  /// Provider-neutral media format label, e.g. `TV`, `MOVIE`, `OVA`.
  final String? format;

  /// Total episode count when the provider supplies one.
  final int? episodeCount;

  /// Canonical per-reference details. Every reference that successfully
  /// supplied metadata is preserved — one entry per [DiscoveryReference], in
  /// reference order. A reference that failed or supplied nothing has no
  /// entry here, but the reference itself is never discarded.
  final List<ReferenceMetadata> details;

  /// True when more than one reference contributed metadata.
  bool get isCrossReference => details.length > 1;

  /// Whether this work is presented as episodic (seasons + per-episode actions)
  /// rather than as a single title.
  ///
  /// Movies are never episodic. Series always is. Anime depends on the
  /// provider's format, and an anime FILM (format `MOVIE`) is a single title —
  /// a device run showed a "Seasons" panel for Spirited Away because the type
  /// alone was treated as episodic.
  ///
  /// When the format is unknown the answer is deliberately `false`: the surface
  /// stays quiet rather than guessing at a Seasons panel. The format label is
  /// provider-neutral text ([format]), so this compares against the single
  /// feature label case-insensitively instead of importing a provider enum.
  bool get isEpisodic {
    if (type == MediaType.movie) return false;
    if (type == MediaType.series) return true;
    final String? label = format?.trim().toUpperCase();
    if (label == null || label.isEmpty) return false;
    return label != 'MOVIE';
  }

  /// True when a real extension (not a metadata provider) contributed.
  ///
  /// A catalogue-only item can never report episodes, so surfaces use this to
  /// tell "the extension has nothing yet" apart from "there is no extension at
  /// all" and say something honest in each case.
  bool get hasExtensionContribution =>
      details.any((ReferenceMetadata d) => !d.isProviderMetadata);

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

  /// Returns a copy enriched with one provider contribution.
  ///
  /// PROVIDER DATA IS AN ADDITION, NEVER AN OVERRIDE. Extension metadata is
  /// SPECTA's primary source; a catalogue provider (TMDB/TVMaze/AniList) may
  /// only fill fields that are still empty. Existing titles, artwork,
  /// descriptions, genres, ratings and seasons are preserved exactly, and the
  /// canonical `key`, `type`, `year`, `canonicalId` and `identityVersion` are
  /// never changed by enrichment — a fallback can therefore never mint a
  /// second identity for a work.
  MetadataItem withEnrichment(ReferenceMetadata contribution) {
    return MetadataItem(
      key: key,
      title: title,
      type: type,
      year: year,
      cover: cover ?? contribution.cover,
      backdrop: backdrop ?? contribution.backdrop,
      canonicalId: canonicalId,
      identityVersion: identityVersion,
      format: format ?? contribution.format,
      episodeCount: episodeCount ?? contribution.episodeCount,
      details: <ReferenceMetadata>[...details, contribution],
    );
  }

  /// The best description among contributions, first non-empty wins.
  String? get description {
    for (final ReferenceMetadata r in details) {
      if (r.description != null) return r.description;
    }
    return null;
  }

  /// Union of genres across contributions, order-preserving.
  List<String> get genres {
    final List<String> merged = <String>[];
    final Set<String> seen = <String>{};
    for (final ReferenceMetadata r in details) {
      for (final String g in r.genres) {
        if (seen.add(g)) merged.add(g);
      }
    }
    return merged;
  }

  /// First non-null rating among contributions.
  double? get rating {
    for (final ReferenceMetadata r in details) {
      if (r.rating != null) return r.rating;
    }
    return null;
  }
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
    this.externalIds,
    this.originalTitle,
    this.cover,
    this.backdrop,
    this.description,
    this.genres = const <String>[],
    this.durationSeconds,
    this.format,
    this.episodeCount,
    this.studios = const <String>[],
    this.isProviderMetadata = false,
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

  /// Optional external identity supplied by the extension, including AniList.
  final ExternalIds? externalIds;

  final String? originalTitle;
  final String? cover;
  final String? backdrop;
  final String? description;
  final List<String> genres;
  final int? durationSeconds;
  final String? format;
  final int? episodeCount;
  final List<String> studios;

  /// True when this entry came from a metadata provider (TMDB / TVMaze /
  /// AniList) rather than from an extension. Provider entries carry canonical
  /// metadata but can never supply streams, episodes, or a playback reference.
  final bool isProviderMetadata;

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
