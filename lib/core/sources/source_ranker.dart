import '../extensions/contract/extension_source.dart';
import 'source_models.dart';
import 'source_pool.dart';

/// SPECTA's source ranking policy.
///
/// Design (brief §13, §14, §30):
/// - Deterministic: the same pool + preference always produces the same
///   order. No randomness, no dependence on async completion order; ties
///   break on (quality score, type, URL) so equal candidates land in a
///   stable order.
/// - Honest: only measurable signals are scored. Playback telemetry
///   (startup time, buffering history, success rates) does not exist until
///   the player (2E) produces it — 2D deliberately does not fabricate it.
///   The ranker is pure so 2E can add a health term later without a
///   rewrite.
///
/// Score composition (simple additive, documented, testable):
/// - Quality match with the user's preference: the dominant term.
///   `auto` prefers higher native quality with a small adaptive bonus.
///   A concrete preference (720p etc.) scores exact matches highest,
///   with deterministic proximity falloff — NOT "highest quality first".
/// - Adaptive bonus (small): adaptive streams can serve the connection
///   they get; only rewarded under `auto` where adaptation is the point.
/// - Type preference under `auto` (small): HLS's adaptive variant already
///   carries the bonus; mp4 and hls are otherwise equal. No hidden bias.
/// - Unknown/missing quality: scored explicitly (never invented, never
///   confused with a real resolution).
abstract final class SourceRanker {
  /// Native quality tier. Higher is more detail. `null` (unknown) is a
  /// distinct, explicitly-scored case.
  static int? _tier(String? quality) => switch (quality?.trim()) {
    '480p' => 480,
    '720p' => 720,
    '1080p' => 1080,
    '4K' => 2160,
    _ => null,
  };

  /// Ranks [candidates] for [preference]. Returns a new list, best first.
  static List<RankedSource> rank(
    List<RankedSource> candidates,
    QualityPreference preference,
  ) {
    final List<RankedSource> scored = candidates
        .map(
          (RankedSource c) => RankedSource(
            source: c.source,
            extensionId: c.extensionId,
            reference: c.reference,
            score: _score(c, preference),
          ),
        )
        .toList(growable: false);

    final List<RankedSource> sorted = <RankedSource>[...scored]
      ..sort((RankedSource a, RankedSource b) {
        int cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        // Deterministic tie-breakers: quality tier, then type, then URL.
        cmp = (_tier(b.source.quality) ?? -1).compareTo(
          _tier(a.source.quality) ?? -1,
        );
        if (cmp != 0) return cmp;
        cmp = b.source.type.code.compareTo(a.source.type.code);
        if (cmp != 0) return cmp;
        return a.source.url.compareTo(b.source.url);
      });
    return sorted;
  }

  static int _score(RankedSource c, QualityPreference preference) {
    final ExtensionSource s = c.source;
    final int? tier = _tier(s.quality);

    int score = 0;
    switch (preference) {
      case QualityPreference.auto:
        if (tier == null) {
          score += 30; // unknown quality: usable, but never preferred over
          //             a known resolution (explicit, not invented).
        } else {
          score += 40 + (tier ~/ 54); // 480->+48, 720->+53, 1080->+60, 4K->+80
        }
        if (s.isAdaptive) score += 8;
      case QualityPreference.p480:
      case QualityPreference.p720:
      case QualityPreference.p1080:
      case QualityPreference.uhd4k:
        final int? wanted = _tier(preference.code);
        if (tier == null) {
          score += 20; // unknown: acceptable fallback, not a match.
        } else {
          final int distance = (tier - wanted!).abs();
          score += switch (distance) {
            0 => 100, // exact match
            <= 360 => 70, // near (one step away)
            _ => 45, // far (e.g. 4K requested, 480p available)
          };
        }
        // Under a concrete preference a fixed stream of the wanted quality
        // slightly beats an adaptive one at the same nominal quality: the
        // user asked for exactly this.
        if (!s.isAdaptive) score += 3;
    }
    return score;
  }
}
