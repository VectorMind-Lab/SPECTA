import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sources/source_manager.dart';
import '../../core/sources/source_models.dart';
import '../../core/sources/source_pool.dart';

/// Status of one source-resolution session.
enum SourceSessionStatus {
  /// Nothing requested yet.
  idle,

  /// A resolution round is in flight.
  loading,

  /// A pool with at least one valid candidate is available.
  ready,

  /// The round completed but produced no usable source (all extensions
  /// failed / nothing valid survived).
  failure,
}

/// Immutable snapshot of one source-resolution session.
///
/// Core/service-layer state only: this exposes the pool SPECTA decided on.
/// It deliberately contains no playback controls, no progress, and no
/// player wiring (2E owns those) — it is the clean seam 2E consumes.
final class SourceSessionState {
  const SourceSessionState({
    required this.status,
    required this.generation,
    this.pool,
    this.preference = QualityPreference.auto,
  });

  final SourceSessionStatus status;

  /// Monotonic round counter — Episode 1's late result can never overwrite
  /// Episode 2 (same pattern as the 2B/2C sessions).
  final int generation;

  /// The resolved pool with ranked candidates and provenance. Only for
  /// [SourceSessionStatus.ready].
  final SourcePool? pool;

  /// The preference the current/last round used.
  final QualityPreference preference;

  static const SourceSessionState initial = SourceSessionState(
    status: SourceSessionStatus.idle,
    generation: 0,
  );
}

/// Drives source-resolution rounds over the source service.
class SourceSessionNotifier extends Notifier<SourceSessionState> {
  int _generation = 0;
  bool _disposed = false;

  @override
  SourceSessionState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++; // invalidate any in-flight round
    });
    return SourceSessionState.initial;
  }

  /// Resolves sources for [reference] across [extensions] (extension id →
  /// that extension's internal reference for the same logical target).
  Future<void> resolve({
    required String reference,
    required Map<String, String> extensions,
    QualityPreference preference = QualityPreference.auto,
  }) async {
    if (extensions.isEmpty) return;

    final int gen = ++_generation;
    state = SourceSessionState(
      status: SourceSessionStatus.loading,
      generation: gen,
      preference: preference,
    );

    final SourcePool pool;
    try {
      pool = await ref.read(sourceServiceProvider).resolve(
            reference: reference,
            extensions: extensions,
            preference: preference,
          );
    } on Object {
      // Absolute containment: the UI layer never sees an exception.
      _applyIfCurrent(
        gen,
        SourceSessionState(
          status: SourceSessionStatus.failure,
          generation: gen,
          preference: preference,
        ),
      );
      return;
    }
    if (_disposed) return;

    _applyIfCurrent(gen, _stateFrom(pool, gen, preference));
  }

  void reset() {
    _generation++;
    state = SourceSessionState.initial;
  }

  void _applyIfCurrent(int gen, SourceSessionState next) {
    if (_disposed) return;
    if (gen != _generation) return; // stale round — reject
    state = next;
  }

  SourceSessionState _stateFrom(
    SourcePool pool,
    int gen,
    QualityPreference preference,
  ) {
    if (pool.ranked.isEmpty) {
      return SourceSessionState(
        status: SourceSessionStatus.failure,
        generation: gen,
        preference: preference,
      );
    }
    return SourceSessionState(
      status: SourceSessionStatus.ready,
      generation: gen,
      pool: pool,
      preference: preference,
    );
  }
}

/// The current source-resolution session state.
final NotifierProvider<SourceSessionNotifier, SourceSessionState>
    sourceSessionProvider =
    NotifierProvider<SourceSessionNotifier, SourceSessionState>(
      SourceSessionNotifier.new,
    );
