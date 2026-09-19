import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_models.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/watch_progress.dart';
import '../../core/metadata/metadata_manager.dart';
import '../../core/metadata/metadata_models.dart';

/// Entry point back into the existing playback pipeline from a persisted
/// Continue Watching / Library / History item (Phase 2F resume follow-up).
///
/// The persisted identity is the SAME evidence-based metadata key the rest of
/// SPECTA uses, and it is SELF-DESCRIBING:
///
///     <normalizedTitle>|<type>|<year-or-none>
///
/// (the `|` separator can never appear inside a part: the key title
/// normalizer strips it). Resume therefore reconstructs the exact
/// [DiscoveryItem] from the stored key plus the stored discovery references,
/// re-runs the metadata layer, and hands the result to the UNCHANGED 2D/2E
/// pipeline. No title search, no new identity system, no stored source URLs.

/// Rebuilds the [DiscoveryItem] for [progress] from [references].
///
/// Returns null when the identity is malformed or there is no provenance —
/// resume must fail honestly rather than guess.
DiscoveryItem? discoveryItemFor(
  WatchProgress progress,
  List<DiscoveryReference> references,
) {
  if (references.isEmpty) return null;

  final List<String> parts = progress.mediaKey.split('|');
  if (parts.length != 3) return null;

  final String normalizedTitle = parts[0];
  final MediaType? type = MediaType.fromCode(parts[1]);
  if (type == null || normalizedTitle.isEmpty) return null;

  final int? year = parts[2] == 'none' ? null : int.tryParse(parts[2]);
  // A non-'none', non-parsing year part means the key was not produced by the
  // metadata identity function — refuse rather than silently mis-resolve.
  if (parts[2] != 'none' && year == null) return null;

  return DiscoveryItem(
    key: progress.mediaKey,
    title: normalizedTitle,
    type: type,
    year: year,
    references: references,
  );
}

/// The exact episode a persisted record refers to, matched on season AND
/// episode number so S1E2 can never be replaced by S1E1 or S2E2.
SeriesEpisode? episodeFor(MetadataItem metadata, WatchProgress progress) {
  if (!progress.isEpisode) return null;
  for (final SeriesSeason season in metadata.seasons) {
    if (season.seasonNumber != progress.seasonNumber) continue;
    for (final SeriesEpisode episode in season.episodes) {
      if (episode.episodeNumber == progress.episodeNumber) return episode;
    }
  }
  return null;
}

/// Where playback should start for [progress].
///
/// A completed record restarts from the beginning (never an arbitrary old
/// position); an unfinished record resumes at its stored position; no known
/// position means no seek.
Duration? resumeStartPosition(WatchProgress progress) {
  if (progress.completed) return null;
  if (progress.position <= Duration.zero) return null;
  return progress.position;
}

/// Loads canonical metadata for a reconstructed item. Injected so the resume
/// flow is testable without an extension manager.
typedef MetadataLookup = Future<MetadataItem?> Function(DiscoveryItem item);

final Provider<MetadataLookup> metadataLookupProvider =
    Provider<MetadataLookup>((Ref ref) {
  return (DiscoveryItem item) async {
    final MetadataResult result =
        await ref.read(metadataServiceProvider).metadataFor(item);
    return result.item;
  };
});

/// Starts playback of an already-resolved item. Injected by the caller so the
/// production path uses the real [startPlayback] (which owns navigation) while
/// tests can observe the request without a widget tree.
typedef PlaybackStarter = Future<void> Function({
  required MetadataItem metadata,
  required DiscoveryItem item,
  SeriesEpisode? episode,
  Duration? startPosition,
});

/// How a resume attempt ended. Data, never an exception.
enum ResumeStatus {
  /// Playback was handed to the existing pipeline.
  started,

  /// No discovery provenance is stored for this item.
  noReferences,

  /// The stored identity could not be reconstructed.
  invalidIdentity,

  /// The metadata layer could not supply the work right now.
  metadataUnavailable,

  /// The referenced episode no longer exists in the provider's metadata.
  episodeMissing,
}

/// The structured outcome of a resume attempt.
final class ResumeResult {
  const ResumeResult(this.status);

  final ResumeStatus status;

  bool get started => status == ResumeStatus.started;

  /// User-facing, non-technical explanation. Honest: nothing is fabricated.
  String get message => switch (status) {
        ResumeStatus.started => 'Resuming…',
        ResumeStatus.noReferences =>
          'This item can no longer be resolved. Open it from Search again.',
        ResumeStatus.invalidIdentity =>
          'This item cannot be resumed right now.',
        ResumeStatus.metadataUnavailable =>
          'Its provider could not supply details right now. Try again later.',
        ResumeStatus.episodeMissing =>
          'That episode is no longer available from its provider.',
      };

  @override
  String toString() => 'ResumeResult(${status.name})';
}

/// Re-opens a persisted item through the existing pipeline.
///
/// Reads the durable provenance, rebuilds the identity, re-runs the metadata
/// layer through [metadataLookupProvider], selects the exact episode, then
/// calls [starter] — which in production is the UNCHANGED [startPlayback], so
/// sources are re-resolved through the existing SourceManager/SourcePool.
Future<ResumeResult> resumeWatchProgress({
  required WidgetRef ref,
  required WatchProgress progress,
  required PlaybackStarter starter,
}) {
  return resumeWith(
    progress: progress,
    loadReferences: () =>
        ref.read(libraryStoreProvider).referencesFor(progress.mediaKey),
    lookup: ref.read(metadataLookupProvider),
    starter: starter,
  );
}

/// The orchestration behind [resumeWatchProgress], with its two dependencies
/// injected so it is fully testable without a widget tree or extensions.
Future<ResumeResult> resumeWith({
  required WatchProgress progress,
  required Future<List<DiscoveryReference>> Function() loadReferences,
  required MetadataLookup lookup,
  required PlaybackStarter starter,
}) async {
  final List<DiscoveryReference> references;
  try {
    references = await loadReferences();
  } on Object {
    return const ResumeResult(ResumeStatus.noReferences);
  }

  final DiscoveryItem? item = discoveryItemFor(progress, references);
  if (item == null) {
    return ResumeResult(
      references.isEmpty
          ? ResumeStatus.noReferences
          : ResumeStatus.invalidIdentity,
    );
  }

  MetadataItem? metadata;
  try {
    metadata = await lookup(item);
  } on Object {
    metadata = null; // absolute containment — never a throw into the UI
  }
  if (metadata == null) {
    return const ResumeResult(ResumeStatus.metadataUnavailable);
  }

  SeriesEpisode? episode;
  if (progress.isEpisode) {
    episode = episodeFor(metadata, progress);
    if (episode == null) {
      return const ResumeResult(ResumeStatus.episodeMissing);
    }
  }

  await starter(
    metadata: metadata,
    item: item,
    episode: episode,
    startPosition: resumeStartPosition(progress),
  );
  return const ResumeResult(ResumeStatus.started);
}
