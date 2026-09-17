import 'package:specta/core/extensions/contract/result_models.dart';

import 'discovery_models.dart';
import 'discovery_normalizer.dart';

/// Central SPECTA deduplication for discovery observations.
///
/// Policy (deliberate, documented, testable):
///
/// 1. Identity key = (keyTitle, type, year). Two observations merge only when
///    the normalized titles match, the media types match, AND the years match.
///    A null year never merges with a concrete year (missing data is not a
///    match). Two observations that both lack a year share the `none` year
///    bucket: same title + type + both-unknown is the same discovery key, and
///    provenance keeps both references so a later phase can still tell them
///    apart through their provider data.
/// 2. An exact duplicate observation from the SAME extension (same id + URL)
///    is ignored entirely (a repeated observation, not a second reference).
///    The same URL reported by two DIFFERENT extensions is kept: both
///    references are provenance and the identity key merges them into one
///    item.
/// 3. The same work from two DIFFERENT extensions becomes ONE unified item
///    with BOTH references preserved (mandatory provenance rule). The merged
///    item's year and title never mutate after first observation.
/// 4. Different years / different types / different titles stay separate
///    items — remakes and unrelated works must not be merged.
///
/// Within one extension, two entries with the same title+type+year but
/// different URLs are kept as separate references: an extension legitimately
/// listing two catalogue entries for one title (e.g. different cuts) is
/// provider data SPECTA has no authority to collapse.
abstract final class DiscoveryDeduplicator {
  /// Merges normalized observations into unified [DiscoveryItem]s in stable
  /// first-seen order.
  static List<DiscoveryItem> dedupe(List<DiscoveryObservation> observations) {
    final Map<String, _Accumulator> byKey = <String, _Accumulator>{};
    final Set<String> seenUrls = <String>{};
    final List<_Accumulator> ordered = <_Accumulator>[];

    for (final DiscoveryObservation o in observations) {
      if (!seenUrls.add('${o.extensionId}|${o.url}')) continue;

      final String key =
          '${o.keyTitle}|${o.type.code}|${o.year?.toString() ?? 'none'}';
      final _Accumulator? existing = byKey[key];

      if (existing == null) {
        final _Accumulator acc = _Accumulator(
          key: key,
          title: o.title,
          type: o.type,
          year: o.year,
          cover: o.cover,
        );
        acc.references.add(
          DiscoveryReference(
            extensionId: o.extensionId,
            url: o.url,
            cover: o.cover,
          ),
        );
        byKey[key] = acc;
        ordered.add(acc);
        continue;
      }

      // Merge path: same identity key. Provenance rule — append the
      // reference; never drop it. Title/type/year stay as first observed.
      existing.references.add(
        DiscoveryReference(
          extensionId: o.extensionId,
          url: o.url,
          cover: o.cover,
        ),
      );
      // Fill the cover only if the merged item has none (an extension that
      // provides artwork improves the item; it never overwrites artwork).
      existing.cover ??= o.cover;
    }

    return ordered
        .map(
          (_Accumulator a) => DiscoveryItem(
            key: a.key,
            title: a.title,
            type: a.type,
            year: a.year,
            cover: a.cover,
            references: List<DiscoveryReference>.unmodifiable(a.references),
          ),
        )
        .toList();
  }
}

/// Mutable build-time accumulator for one unified item. Never escapes the
/// deduplicator; the emitted [DiscoveryItem] is immutable.
final class _Accumulator {
  _Accumulator({
    required this.key,
    required this.title,
    required this.type,
    required this.year,
    required this.cover,
  });

  final String key;
  final String title;
  final MediaType type;
  final int? year;
  String? cover;
  final List<DiscoveryReference> references = <DiscoveryReference>[];
}
