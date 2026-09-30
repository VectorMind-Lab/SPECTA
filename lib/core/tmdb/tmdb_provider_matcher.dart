import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/identity/title_key.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';

/// The result of matching a canonical TMDB media item with installed extensions.
final class TmdbMatchResult {
  const TmdbMatchResult({
    required this.references,
    this.identity,
    this.matchedDiscoveryItem,
  });

  /// The canonical TMDB identity of the target work.
  ///
  /// Null when the target was matched by title alone (a catalogue item that
  /// carries no TMDB id on its [DiscoveryItem]). A title match is still a real
  /// match — it simply cannot claim a TMDB identity it was never given.
  final SpectaMediaIdentity? identity;

  /// Contributing extension references that match this work.
  final List<DiscoveryReference> references;

  /// The merged discovery item from extensions, if a match was found.
  final DiscoveryItem? matchedDiscoveryItem;

  bool get hasMatch => references.isNotEmpty;

  /// Map of extensionId -> extension-internal URL for playback/source resolution.
  Map<String, String> get extensionReferences => <String, String>{
    for (final DiscoveryReference ref in references) ref.extensionId: ref.url,
  };
}

/// Matches canonical TMDB media items with extension sources using [TitleKey].
///
/// Discovers candidates across enabled extensions by title query, normalizes their
/// identities using SPECTA's shared Unicode-aware [TitleKey.normalize], and selects
/// the best candidate by:
/// 1. MediaType agreement (Movie vs Series must match strictly).
/// 2. Exact normalized TitleKey match.
/// 3. Release year match (exact match or +/- 1 year tolerance for international release offsets).
abstract final class TmdbProviderMatcher {
  /// Matches a target work ([identity], [title], optional [year]) against enabled extensions.
  static Future<TmdbMatchResult> match({
    required SpectaMediaIdentity identity,
    required String title,
    required ExtensionManager extensionManager,
    int? year,
    Duration? timeoutOverride,
  }) async {
    final TmdbMatchResult result = await matchByTitle(
      title: title,
      type: identity.type,
      extensionManager: extensionManager,
      year: year,
      timeoutOverride: timeoutOverride,
    );
    return TmdbMatchResult(
      identity: identity,
      references: result.references,
      matchedDiscoveryItem: result.matchedDiscoveryItem,
    );
  }

  /// Matches a work by title/type/year alone, for a target that has no TMDB id.
  ///
  /// A catalogue rail item (Home "Trending", an AniList row) is a real work the
  /// user can see, but it never passed through discovery, so it carries NO
  /// [DiscoveryReference] and therefore cannot be played. This is the entry
  /// point that gives those items a source: it searches the installed
  /// extensions for the same work and returns the references found.
  ///
  /// The selection rules are exactly [match]'s — this exists so a title-only
  /// target gets the same quality of match, not a weaker one.
  static Future<TmdbMatchResult> matchByTitle({
    required String title,
    required MediaType type,
    required ExtensionManager extensionManager,
    int? year,
    Duration? timeoutOverride,
  }) async {
    final SearchRequest request = SearchRequest(query: title);
    if (!request.isValid) {
      return const TmdbMatchResult(references: <DiscoveryReference>[]);
    }

    final DiscoveryResult discovery = await DiscoveryCoordinator.discover(
      request: request,
      manager: extensionManager,
      perExtensionTimeoutOverride: timeoutOverride,
    );

    if (discovery.items.isEmpty) {
      return const TmdbMatchResult(references: <DiscoveryReference>[]);
    }

    final String targetNormTitle = TitleKey.normalize(title);

    DiscoveryItem? bestMatch;
    int bestScore = -1;

    for (final DiscoveryItem item in discovery.items) {
      // Must match media type strictly
      if (item.type != type) continue;

      final String itemNormTitle = TitleKey.normalize(item.title);
      if (itemNormTitle != targetNormTitle) {
        // Fallback: check if one title contains the other if exact match fails
        if (!itemNormTitle.contains(targetNormTitle) &&
            !targetNormTitle.contains(itemNormTitle)) {
          continue;
        }
      }

      int score = 0;
      if (itemNormTitle == targetNormTitle) {
        score += 10;
      } else {
        score += 3;
      }

      // Year comparison
      if (year != null && item.year != null) {
        final int diff = (year - item.year!).abs();
        if (diff == 0) {
          score += 10;
        } else if (diff == 1) {
          score += 5;
        } else {
          // Significant year difference penalty
          score -= 5;
        }
      } else if (year == null || item.year == null) {
        // One side lacks year info
        score += 2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = item;
      }
    }

    if (bestMatch != null && bestScore >= 5) {
      return TmdbMatchResult(
        references: bestMatch.references,
        matchedDiscoveryItem: bestMatch,
      );
    }

    return const TmdbMatchResult(references: <DiscoveryReference>[]);
  }
}
