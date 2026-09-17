import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_models.dart';
import '../../core/metadata/metadata_manager.dart';
import '../../core/metadata/metadata_models.dart';

/// User-facing details status. Every state the brief requires, with no raw
/// internal exceptions exposed to the UI.
enum DetailsStatus {
  /// No item opened yet.
  idle,

  /// A metadata request is in flight.
  loading,

  /// Canonical metadata loaded (possibly from fewer references than asked —
  /// see [failedReferences] for the honest partial-failure picture).
  success,

  /// Every reference failed or was invalid — no metadata could be loaded.
  failure,
}

/// Immutable snapshot of one details session for one discovery item.
final class DetailsState {
  const DetailsState({
    required this.status,
    required this.generation,
    this.item,
    this.metadata,
    this.failedReferences = const <String>[],
    this.invalidReferences = const <String>[],
  });

  final DetailsStatus status;

  /// Monotonic request counter. A response from an older request is
  /// discarded — rapid navigation (A → B → A → C) can never let a slow
  /// older response overwrite a newer one.
  final int generation;

  /// The discovery item this session is about (set on open, so the UI can
  /// render title/poster immediately from discovery data while details load).
  final DiscoveryItem? item;

  /// Canonical metadata — only for [DetailsStatus.success].
  final MetadataItem? metadata;

  /// References whose extension failed (ids only — no raw errors in UI).
  final List<String> failedReferences;

  /// References whose payload failed validation (ids only).
  final List<String> invalidReferences;

  /// True when at least one reference failed or was invalid but metadata
  /// still loaded — the honest partial-failure state.
  bool get isPartial => status == DetailsStatus.success &&
      (failedReferences.isNotEmpty || invalidReferences.isNotEmpty);

  static const DetailsState initial = DetailsState(
    status: DetailsStatus.idle,
    generation: 0,
  );

  DetailsState copyWith({
    DetailsStatus? status,
    int? generation,
    DiscoveryItem? item,
    MetadataItem? metadata,
    List<String>? failedReferences,
    List<String>? invalidReferences,
  }) {
    return DetailsState(
      status: status ?? this.status,
      generation: generation ?? this.generation,
      item: item ?? this.item,
      metadata: metadata ?? this.metadata,
      failedReferences: failedReferences ?? this.failedReferences,
      invalidReferences: invalidReferences ?? this.invalidReferences,
    );
  }
}

/// Drives details requests over the metadata service.
///
/// Race handling mirrors the search session: a monotonically increasing
/// generation stamps every request; when it completes it is applied only if
/// no newer request has started. Repeated opens of the same item are safe —
/// each open is a fresh request.
class DetailsSessionNotifier extends Notifier<DetailsState> {
  int _generation = 0;
  bool _disposed = false;

  @override
  DetailsState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++; // invalidate any in-flight request
    });
    return DetailsState.initial;
  }

  /// Opens details for [item]: shows discovery data immediately, then loads
  /// canonical metadata through the metadata service.
  Future<void> open(DiscoveryItem item) async {
    final int gen = ++_generation;

    // Immediate discovery-level render: title/type/year/cover from the item
    // while the details round is in flight. Never fabricated — this is
    // exactly what discovery observed.
    state = DetailsState(
      status: DetailsStatus.loading,
      generation: gen,
      item: item,
    );

    final MetadataResult result;
    try {
      result = await ref.read(metadataServiceProvider).metadataFor(item);
    } on Object {
      // Absolute containment: the UI layer never sees an exception.
      _applyIfCurrent(
        gen,
        DetailsState(
          status: DetailsStatus.failure,
          generation: gen,
          item: item,
        ),
      );
      return;
    }
    if (_disposed) return;

    _applyIfCurrent(
      gen,
      _stateFrom(result, item, gen),
    );
  }

  /// Returns the session to idle (details surface left).
  void reset() {
    _generation++; // reject any in-flight request
    state = DetailsState.initial;
  }

  void _applyIfCurrent(int gen, DetailsState next) {
    if (_disposed) return;
    if (gen != _generation) return; // stale request — reject
    state = next;
  }

  DetailsState _stateFrom(MetadataResult result, DiscoveryItem item, int gen) {
    if (!result.hasItem) {
      return DetailsState(
        status: DetailsStatus.failure,
        generation: gen,
        item: item,
        failedReferences: _idsOf(result, invalid: false),
        invalidReferences: _idsOf(result, invalid: true),
      );
    }

    return DetailsState(
      status: DetailsStatus.success,
      generation: gen,
      item: item,
      metadata: result.item,
      failedReferences: _idsOf(result, invalid: false),
      invalidReferences: _idsOf(result, invalid: true),
    );
  }

  static List<String> _idsOf(MetadataResult result, {required bool invalid}) =>
      result.outcomes
          .where(
            (ReferenceOutcome o) =>
                invalid ? o.isInvalid : (o.isFailed || o.kind == ReferenceOutcomeKind.skipped),
          )
          .map((ReferenceOutcome o) => o.reference.extensionId)
          .toList(growable: false);
}

/// The current details session state.
final NotifierProvider<DetailsSessionNotifier, DetailsState>
detailsSessionProvider =
    NotifierProvider<DetailsSessionNotifier, DetailsState>(
      DetailsSessionNotifier.new,
    );
