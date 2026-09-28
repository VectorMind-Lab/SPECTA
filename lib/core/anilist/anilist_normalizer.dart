import 'package:specta/core/anilist/anilist_dto.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/metadata/metadata_models.dart';

/// Maps AniList records into SPECTA's C1 anime identity and metadata models.
abstract final class AniListNormalizer {
  static DiscoveryItem toDiscoveryItem(AniListMedia media) {
    final String title = media.title.display!;
    return DiscoveryItem(
      key: MediaIdentity.anilistKey(media.id)!,
      title: title,
      type: MediaType.anime,
      year: media.year,
      cover: media.coverImageUrl,
      references: const <DiscoveryReference>[],
      externalIds: ExternalIds(anilistId: media.id),
    );
  }

  static MetadataItem toMetadataItem(AniListMedia media) {
    final String title = media.title.display!;
    return MetadataItem(
      key: MediaIdentity.anilistKey(media.id)!,
      title: title,
      type: MediaType.anime,
      year: media.year,
      cover: media.coverImageUrl,
      backdrop: media.bannerImageUrl,
      canonicalId: MediaIdentity.anilistKey(media.id),
      identityVersion: 2,
      format: media.format.code,
      episodeCount: media.episodes,
      details: <ReferenceMetadata>[
        ReferenceMetadata(
          extensionId: 'anilist',
          referenceUrl: 'anilist:${media.id}',
          title: title,
          isProviderMetadata: true,
          externalIds: ExternalIds(anilistId: media.id),
          originalTitle: media.title.romaji,
          cover: media.coverImageUrl,
          backdrop: media.bannerImageUrl,
          description: media.description,
          genres: media.genres,
          durationSeconds: media.duration == null ? null : media.duration! * 60,
          rating: media.rating,
          format: media.format.code,
          episodeCount: media.episodes,
          studios: media.studios
              .where((AniListStudio s) => s.isAnimationStudio)
              .map((AniListStudio s) => s.name)
              .toList(growable: false),
        ),
      ],
    );
  }
}
