import 'package:specta/core/identity/title_key.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

/// Central SPECTA normalization for discovery observations.
///
/// Turns one raw [SearchResult] from any extension into a
/// [DiscoveryObservation] — the input to deduplication — or reports it as
/// dropped with a reason. SPECTA never invents missing information and never
/// destroys provider-specific references.
abstract final class DiscoveryNormalizer {
  /// Turns a raw result into a normalized observation.
  ///
  /// Returns null (drop) when the observation is unusable:
  /// - blank or whitespace-only title or URL,
  /// - title/URL longer than 512 characters (protocol-noise guard),
  /// - type is not movie/series/anime,
  /// - an anime result without a positive AniList ID,
  ///
  /// Tolerated (not dropped): missing year, missing cover, missing type —
  /// the type defaults to `movie` per the runtime contract, title casing is
  /// preserved, URLs are not re-queried.
  static DiscoveryObservation? normalize(SearchResult raw, String extensionId) {
    final String title = raw.title.trim();
    final String url = raw.url.trim();

    if (title.isEmpty || url.isEmpty) return null;
    if (title.length > 512 || url.length > 512) return null;
    if (raw.type != MediaType.movie &&
        raw.type != MediaType.series &&
        raw.type != MediaType.anime) {
      return null;
    }
    if (raw.type == MediaType.anime && raw.externalIds?.anilistId == null) {
      return null;
    }

    return DiscoveryObservation(
      raw: raw,
      extensionId: extensionId,
      keyTitle: _keyTitle(title),
      title: title,
      type: raw.type,
      year: raw.year,
      url: url,
      cover: raw.cover == null || raw.cover!.trim().isEmpty
          ? null
          : raw.cover!.trim(),
      externalIds: raw.externalIds,
    );
  }

  /// Builds the case/punctuation/whitespace-insensitive title key used by
  /// deduplication.
  ///
  /// The rule is the SHARED [TitleKey.normalize] (2G-C pre-flight §36.1):
  /// lowercase, strip punctuation and symbols while KEEPING Unicode letters
  /// and digits, collapse whitespace, trim, with a no-empty-key fallback —
  /// one single source of truth so this rule can never drift from the
  /// metadata layer's identity key again. "The  Batman!" and "the batman"
  /// share a key; "The Batman" (2022) and "The Batman" (1966) do not (year
  /// is part of the identity decision, not the title key). Non-Latin titles
  /// ("千と千尋の神隠し", "기생충", "Amélie") keep their letters instead of
  /// collapsing to an empty/ASCII-mangled key.
  static String _keyTitle(String title) => TitleKey.normalize(title);
}

/// A normalized discovery observation — one extension's raw result after
/// SPECTA normalization, tagged with the contributing extension's id (the
/// runtime does not tag results; the discovery coordinator supplies it) and
/// carrying the precomputed dedup key.
final class DiscoveryObservation {
  const DiscoveryObservation({
    required this.raw,
    required this.extensionId,
    required this.keyTitle,
    required this.title,
    required this.type,
    required this.year,
    required this.url,
    required this.cover,
    this.externalIds,
  });

  final SearchResult raw;

  /// The contributing extension's registry id.
  final String extensionId;
  final String keyTitle;
  final String title;
  final MediaType type;
  final int? year;
  final String url;
  final String? cover;
  final ExternalIds? externalIds;
}
