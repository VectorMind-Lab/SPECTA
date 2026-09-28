import 'package:specta/core/discovery/discovery_coordinator.dart';
import 'package:specta/core/discovery/discovery_models.dart';
import 'package:specta/core/extensions/manager/extension_manager.dart';
import 'package:specta/core/identity/title_key.dart';
import 'package:specta/core/tmdb/tmdb_media_identity.dart';

/// The result of matching a canonical TMDB media item with installed extensions.
final class TmdbMatchResult {
  const TmdbMatchResult({
    required this.identity,
    required this.references,
    this.matchedDiscoveryItem,
  });

  /// The canonical TMDB identity of the target work.
  final SpectaMediaIdentity identity;

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
    final SearchRequest request = SearchRequest(query: title);
    if (!request.isValid) {
      return TmdbMatchResult(
        identity: identity,
        references: const <DiscoveryReference>[],
      );
    }

    final DiscoveryResult discovery = await DiscoveryCoordinator.discover(
      request: request,
      manager: extensionManager,
      perExtensionTimeoutOverride: timeoutOverride,
    );

    if (discovery.items.isEmpty) {
      return TmdbMatchResult(
        identity: identity,
        references: const <DiscoveryReference>[],
      );
    }

    final String targetNormTitle = TitleKey.normalize(title);

    DiscoveryItem? bestMatch;
    int bestScore = -1;

    for (final DiscoveryItem item in discovery.items) {
      // Must match media type strictly
      if (item.type != identity.type) continue;

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
        identity: identity,
        references: bestMatch.references,
        matchedDiscoveryItem: bestMatch,
      );
    }

    return TmdbMatchResult(
      identity: identity,
      references: const <DiscoveryReference>[],
    );
  }
}
