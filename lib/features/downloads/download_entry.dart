import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_models.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/metadata/metadata_models.dart';
import '../playback/source_session_state.dart';

/// Entry point from the details surface into the download system (Phase 2K).
///
/// This closes the other half of the V1 download gap: the Phase 2G manager and
/// engine were complete, but nothing in the product could START a download.
///
/// It is deliberately structured exactly like [startPlayback]: it resolves the
/// pool through the SAME 2D seam ([SourceSessionNotifier]) and hands the
/// resolved pool to the download manager, which owns identity, queueing,
/// concurrency, retry, persistence and recovery. It never re-resolves,
/// re-ranks or talks to extensions directly, and it never invents a second
/// resolution path.
///
/// Resolution provenance mirrors playback: a movie resolves across every
/// contributing reference; an episode resolves ONLY across the extensions that
/// actually reported that episode (asking those who know it), falling back to
/// every contributing reference when that set is empty.
Future<void> startMovieDownload(
  BuildContext context, {
  required WidgetRef ref,
  required MetadataItem metadata,
  required DiscoveryItem item,
}) async {
  final Map<String, String> extensions = <String, String>{
    for (final ReferenceMetadata r in metadata.details)
      r.extensionId: r.referenceUrl,
  };
  if (item.references.isEmpty || extensions.isEmpty) {
    _notice(context, 'This item has nothing downloadable yet.');
    return;
  }

  final ({DownloadRequest? request, String? failure}) resolved =
      await _resolveRequest(
    ref: ref,
    metadata: metadata,
    references: item.references,
    extensions: extensions,
    reference: item.references.first.url,
  );
  if (resolved.failure != null) {
    if (!context.mounted) return;
    _notice(context, resolved.failure!);
    return;
  }
  final DownloadRequest request = resolved.request!;

  final EnqueueResult result =
      await ref.read(downloadManagerProvider).enqueue(request);
  if (!context.mounted) return;
  _notice(context, _enqueueMessage(result.action));
}

/// Series targeting: one episode's own reference is resolved across the
/// extensions that reported it, exactly like playback.
Future<void> startEpisodeDownload(
  BuildContext context, {
  required WidgetRef ref,
  required MetadataItem metadata,
  required DiscoveryItem item,
  required SeriesEpisode episode,
}) async {
  if (item.references.isEmpty) {
    _notice(context, 'This episode has nothing downloadable yet.');
    return;
  }

  Map<String, String> extensions = <String, String>{
    for (final ReferenceMetadata r in metadata.details)
      if (r.seasons.any(
        (SeriesSeason s) => s.episodes.any(
          (SeriesEpisode e) =>
              e.episodeNumber == episode.episodeNumber &&
              e.seasonNumber == episode.seasonNumber &&
              e.referenceUrl == episode.referenceUrl,
        ),
      ))
        r.extensionId: episode.referenceUrl,
  };
  if (extensions.isEmpty) {
    // The episode's reference stopped contributing details — fall back to
    // asking every contributing reference, as the player does.
    extensions = <String, String>{
      for (final ReferenceMetadata r in metadata.details)
        r.extensionId: episode.referenceUrl,
    };
  }

  final ({DownloadRequest? request, String? failure}) resolved =
      await _resolveRequest(
    ref: ref,
    metadata: metadata,
    references: item.references,
    extensions: extensions,
    reference: episode.referenceUrl,
    episode: episode,
  );
  if (resolved.failure != null) {
    if (!context.mounted) return;
    _notice(context, resolved.failure!);
    return;
  }
  final DownloadRequest request = resolved.request!;

  final EnqueueResult result =
      await ref.read(downloadManagerProvider).enqueue(request);
  if (!context.mounted) return;
  _notice(context, _enqueueMessage(result.action));
}

/// Resolves the pool through the existing source session and builds the
/// manager's request. Returns null (after an honest notice) when nothing
/// playable could be resolved — the manager is never handed an empty pool.
/// Resolves the pool through the existing source session and builds the
/// manager's request. Returns either a request or an honest, user-facing
/// reason — never both, and never an empty pool handed to the manager.
Future<({DownloadRequest? request, String? failure})> _resolveRequest({
  required WidgetRef ref,
  required MetadataItem metadata,
  required List<DiscoveryReference> references,
  required Map<String, String> extensions,
  required String reference,
  SeriesEpisode? episode,
}) async {
  await ref.read(sourceSessionProvider.notifier).resolve(
        reference: reference,
        extensions: extensions,
      );

  final SourceSessionState session = ref.read(sourceSessionProvider);
  if (session.status != SourceSessionStatus.ready || session.pool == null) {
    return (request: null, failure: 'No downloadable source was found.');
  }

  final _ItemMetadataAdapter adapter = _ItemMetadataAdapter(
    key: metadata.key,
    title: metadata.title,
    references: references,
  );

  if (episode == null) {
    return (
      request: buildMovieDownloadRequest(metadata: adapter, pool: session.pool!),
      failure: null,
    );
  }
  return (
    request: buildEpisodeDownloadRequest(
      metadata: adapter,
      episode: _EpisodeAdapter(episode),
      pool: session.pool!,
    ),
    failure: null,
  );
}

/// Every enqueue outcome is a fact about the queue, so it is stated plainly
/// rather than shown as an error.
String _enqueueMessage(DownloadEnqueueAction action) => switch (action) {
      DownloadEnqueueAction.created => 'Added to Downloads.',
      DownloadEnqueueAction.createdFailed =>
        'This item has no downloadable file.',
      DownloadEnqueueAction.alreadyQueued => 'Already in Downloads.',
      DownloadEnqueueAction.alreadyDownloading => 'Already downloading.',
      DownloadEnqueueAction.alreadyPaused => 'Already in Downloads (paused).',
      DownloadEnqueueAction.alreadyCompleted => 'Already downloaded.',
      DownloadEnqueueAction.requeuedFailed => 'Retrying the download.',
      DownloadEnqueueAction.requeuedCancelled => 'Added back to Downloads.',
    };

void _notice(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(message),
    ),
  );
}

/// Thin view of the metadata the download entries need (keeps them decoupled
/// from the full [MetadataItem] shape, and trivially testable).
class _ItemMetadataAdapter implements MetadataAdapter {
  const _ItemMetadataAdapter({
    required this.key,
    required this.title,
    required this.references,
  });

  @override
  final String key;
  @override
  final String title;
  @override
  final List<DiscoveryReference> references;
}

class _EpisodeAdapter implements EpisodeAdapter {
  const _EpisodeAdapter(this._episode);

  final SeriesEpisode _episode;

  @override
  int get seasonNumber => _episode.seasonNumber;
  @override
  int get episodeNumber => _episode.episodeNumber;
  @override
  String get referenceUrl => _episode.referenceUrl;
}
