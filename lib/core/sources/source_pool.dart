import '../extensions/contract/extension_source.dart';
import 'source_models.dart';

/// The unified, ranked source pool SPECTA owns after a resolution round.
///
/// One logical playback target as SPECTA sees it: every validated candidate
/// from every contributing extension, with provenance preserved, ranked by
/// SPECTA's policy, and a deterministic selection. The player (2E) will
/// consume [selected] and fall back through [ranked]; it will never need to
/// re-resolve to get alternatives.
final class SourcePool {
  const SourcePool({
    required this.ranked,
    required this.outcomes,
    required this.reference,
  });

  /// Validated candidates in SPECTA's ranking order (best first). Ties are
  /// broken deterministically (see [SourceRanker]).
  final List<RankedSource> ranked;

  /// One outcome per queried extension, in query order — the provenance and
  /// health record of the round.
  final List<ExtensionSourceOutcome> outcomes;

  /// The reference this pool was resolved for (e.g. a movie reference or an
  /// episode URL).
  final String reference;

  /// The candidate SPECTA recommends for playback. Null when nothing valid
  /// survived (the honest empty/failure representation).
  RankedSource? get selected => ranked.isEmpty ? null : ranked.first;

  /// The remaining candidates after the selected one — 2E's fallback order.
  List<RankedSource> get fallbacks =>
      ranked.isEmpty ? const <RankedSource>[] : ranked.sublist(1);

  Iterable<ExtensionSourceOutcome> get failures =>
      outcomes.where((ExtensionSourceOutcome o) => o.isFailed);

  /// True when at least one extension was queried and every queried extension
  /// failed or produced nothing valid — distinct from a genuine empty pool.
  bool get allQueriedFailed =>
      outcomes.isNotEmpty &&
      !outcomes.any(
        (ExtensionSourceOutcome o) => o.isSuccess && o.candidates.isNotEmpty,
      ) &&
      outcomes.any((ExtensionSourceOutcome o) => o.isFailed || o.isInvalid);

  /// True when no extension could be queried (nothing enabled with `sources`).
  bool get noExtensionAvailable =>
      outcomes.isEmpty ||
      outcomes.every((ExtensionSourceOutcome o) => o.isSkipped);

  @override
  String toString() =>
      'SourcePool(reference: $reference, '
      'ranked: ${ranked.length}, outcomes: ${outcomes.length})';
}

/// A validated source candidate plus its SPECTA-side ranking data.
///
/// The wrapped [source] is the extension's own [ExtensionSource] (unchanged);
/// SPECTA adds provenance and ranking on top. The provider URL is never a
/// user-facing label — UI shows neutral labels only.
final class RankedSource {
  const RankedSource({
    required this.source,
    required this.extensionId,
    required this.reference,
    required this.score,
  });

  /// The contributing extension's registry id (provenance).
  final String extensionId;

  /// The extension-internal reference the candidate came from (identity +
  /// future refresh data).
  final String reference;

  /// The validated candidate.
  final ExtensionSource source;

  /// SPECTA's ranking score (higher is better). Deterministic for a given
  /// pool + preference; never fabricated from unmeasured telemetry.
  final int score;

  @override
  String toString() =>
      'RankedSource($extensionId, ${source.type.code}, ${source.quality}, '
      'score: $score)';
}
