import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/identity/title_key.dart';
import 'package:specta/core/metadata/metadata_models.dart';
import 'package:specta/core/tmdb/tmdb_dto.dart';

/// Converts TMDB models into SPECTA's domain models ([DiscoveryItem] and [MetadataItem]).
///
/// TMDB IS THE CATALOGUE: SPECTA DECIDES.
///
/// Conversions:
/// 1. [TmdbMediaSummary] -> [DiscoveryItem]:
///    - Deduplication key: uses [TitleKey.identityKey] so identity across TMDB catalogue items
///      and extension discovery items is mathematically compatible.
///    - References: initially empty (or contains supplied reference if available).
///    - Poster: constructed via [TmdbImageUrl.build].
/// 2. [TmdbMediaDetails] -> [MetadataItem]:
///    - Key: uses [TitleKey.identityKey].
///    - Title, year, cover, backdrop.
///    - Details: synthesized [ReferenceMetadata] provenance for TMDB or wraps extension references.
///    - Seasons and Episodes: mapped to [SeriesSeason] and [SeriesEpisode].

/// The identity a CALLER already established for a work, handed to
/// [TmdbNormalizer.toMetadataItem] so a provider record can COMPLETE that work
/// instead of minting a second identity for it.
///
/// A grouped value rather than three optional parameters, for one concrete
/// reason: [year] is legitimately nullable (the identity key reads
/// `title|type|none`), and a bare `int? yearOverride` cannot tell "the caller's
/// year IS null" from "the caller said nothing" — the first must stay null, the
/// second must fall back to the payload. With a group the whole identity is
/// present, or the whole identity is absent.
///
/// Keeping key, year and cover together is also what stops them from
/// disagreeing: they all describe the same card the user tapped, and a record
/// whose year contradicts its own key is worse than no record at all.
final class CatalogueIdentity {
  const CatalogueIdentity({required this.key, this.year, this.cover});

  /// The `title|type|year` key the discovery layer established.
  final String key;

  /// The year that key encodes. Null is a real value here, not "unknown".
  final int? year;

  /// Artwork the caller already had; kept when the detail payload omits one.
  final String? cover;
}

abstract final class TmdbNormalizer {
  /// Converts a [TmdbMediaSummary] to a canonical [DiscoveryItem].
  static DiscoveryItem toDiscoveryItem(
    TmdbMediaSummary summary, {
    required String imageBaseUrl,
    List<DiscoveryReference> references = const <DiscoveryReference>[],
  }) {
    final String key = TitleKey.identityKey(
      title: summary.title,
      typeCode: summary.identity.type.code,
      year: summary.year,
    );

    final String? coverUrl = TmdbImageUrl.build(
      path: summary.posterPath,
      imageBaseUrl: imageBaseUrl,
      size: TmdbImageSize.posterLarge,
    );

    return DiscoveryItem(
      key: key,
      title: summary.title,
      type: summary.identity.type,
      year: summary.year,
      cover: coverUrl,
      references: references,
    );
  }

  /// Converts a [TmdbMediaDetails] to a canonical [MetadataItem].
  ///
  /// Can merge with existing [ReferenceMetadata] contributions if [existingDetails] are provided.
  ///
  /// Pass [identity] when the caller already established this work's identity.
  /// A catalogue-only item (one the catalogue itself discovered, with no
  /// extension behind it) carries a perfectly good `title|type|year` key; it is
  /// then used verbatim, so the record COMPLETES that work rather than creating
  /// a second identity for it.
  ///
  /// Omit [identity] and key/year/cover are derived from the payload, which is
  /// the correct behaviour whenever the provider IS the identity's origin.
  static MetadataItem toMetadataItem(
    TmdbMediaDetails details, {
    required String imageBaseUrl,
    List<ReferenceMetadata> existingDetails = const <ReferenceMetadata>[],
    CatalogueIdentity? identity,
  }) {
    final String key =
        identity?.key ??
        TitleKey.identityKey(
          title: details.title,
          typeCode: details.identity.type.code,
          year: details.year,
        );

    final String? coverUrl = TmdbImageUrl.build(
      path: details.posterPath,
      imageBaseUrl: imageBaseUrl,
      size: TmdbImageSize.posterLarge,
    );

    final String? backdropUrl = TmdbImageUrl.build(
      path: details.backdropPath,
      imageBaseUrl: imageBaseUrl,
      size: TmdbImageSize.backdropLarge,
    );

    final List<ReferenceMetadata> mergedDetails = <ReferenceMetadata>[
      ...existingDetails,
    ];

    // If no existing extension reference metadata is provided, create a synthetic TMDB entry
    // to preserve description, genres, rating, and season metadata.
    if (mergedDetails.isEmpty) {
      final List<SeriesSeason> seasons = <SeriesSeason>[
        for (final TmdbSeasonSummary s in details.seasons)
          SeriesSeason(
            seasonNumber: s.seasonNumber,
            title: s.name,
            episodes: const <SeriesEpisode>[],
          ),
      ];

      mergedDetails.add(
        ReferenceMetadata(
          extensionId: 'tmdb',
          referenceUrl: details.identity.code,
          title: details.title,
          isProviderMetadata: true,
          originalTitle: details.originalTitle,
          cover: coverUrl,
          backdrop: backdropUrl,
          description: details.overview,
          genres: details.genres,
          durationSeconds: details.runtimeMinutes != null
              ? details.runtimeMinutes! * 60
              : null,
          rating: details.voteAverage,
          seasons: seasons,
        ),
      );
    }

    return MetadataItem(
      key: key,
      title: details.title,
      type: details.identity.type,
      // Branch on PRESENCE, not on nullness. `identity?.year ?? details.year`
      // would treat a caller whose year is genuinely null as if it had said
      // nothing, and backfill a year the caller's own key denies.
      year: identity != null ? identity.year : details.year,
      cover: identity == null ? coverUrl : (identity.cover ?? coverUrl),
      backdrop: backdropUrl,
      details: mergedDetails,
    );
  }

  /// Converts a [TmdbSeasonDetails] to a [SeriesSeason].
  static SeriesSeason toSeriesSeason(
    TmdbSeasonDetails season, {
    required String imageBaseUrl,
  }) {
    final List<SeriesEpisode> episodes = <SeriesEpisode>[
      for (final TmdbEpisodeDetails ep in season.episodes)
        SeriesEpisode(
          episodeNumber: ep.episodeNumber,
          seasonNumber: ep.seasonNumber,
          title: ep.name,
          referenceUrl:
              'tmdb:tv:ep:${season.id}:${ep.seasonNumber}:${ep.episodeNumber}',
          description: ep.overview,
          durationSeconds: ep.runtimeMinutes != null
              ? ep.runtimeMinutes! * 60
              : null,
          cover: TmdbImageUrl.build(
            path: ep.stillPath,
            imageBaseUrl: imageBaseUrl,
            size: TmdbImageSize.backdropMedium,
          ),
        ),
    ];

    return SeriesSeason(
      seasonNumber: season.seasonNumber,
      title: season.name,
      episodes: episodes,
    );
  }
}
