import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/metadata/metadata_models.dart';
import 'playback_session_state.dart';
import 'playback_view.dart';
import 'source_session_state.dart';

/// Entry point from the details surface into playback (Phase 2E).
///
/// The player is a CONSUMER of the source manager: this coordinator asks the
/// EXISTING 2D seam ([SourceSessionNotifier]) to resolve the pool, then hands
/// the ordered candidates (selected + fallbacks) to the playback session. It
/// never re-ranks, re-validates, or talks to extensions directly.
///
/// Series targeting: an episode's own [SeriesEpisode.referenceUrl] is resolved
/// ONLY across the extensions that actually carry that episode (provenance —
/// "ask those who reported it"); a whole-item fallback resolves across every
/// contributing reference. For a movie the whole item resolves across all
/// contributing references.
Future<void> startPlayback(
  BuildContext context, {
  required WidgetRef ref,
  required MetadataItem metadata,
  required DiscoveryItem item,
  SeriesEpisode? episode,
  Duration? startPosition,
}) async {
  final SourceSessionNotifier sources = ref.read(
    sourceSessionProvider.notifier,
  );

  final Map<String, String> extensions;
  final String reference;
  if (episode != null) {
    extensions = <String, String>{
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
      // The episode came from a reference that no longer contributes
      // details; fall back to asking every contributing reference.
      for (final ReferenceMetadata r in metadata.details) {
        extensions[r.extensionId] = episode.referenceUrl;
      }
    }
    reference = episode.referenceUrl;
  } else {
    extensions = <String, String>{
      for (final ReferenceMetadata r in metadata.details)
        r.extensionId: r.referenceUrl,
    };
    if (item.references.isEmpty) {
      // Metadata resolved, but no reference identified the work. Refuse
      // honestly instead of throwing a StateError out of `first`.
      _showNoSources(context);
      return;
    }
    reference = item.references.first.url;
  }

  await sources.resolve(reference: reference, extensions: extensions);

  final SourceSessionState session = ref.read(sourceSessionProvider);
  if (session.status != SourceSessionStatus.ready || session.pool == null) {
    // Honest failure: nothing could be resolved; the details surface stays.
    if (!context.mounted) return;
    _showNoSources(context);
    return;
  }

  // Durability (2F resume follow-up): remember the exact discovery provenance
  // for this work so Continue Watching can be re-opened later without a title
  // search. Only provenance is stored — never a source URL, which is always
  // re-resolved through the current SourceManager.
  if (item.references.isNotEmpty) {
    unawaited(
      ref
          .read(libraryStoreProvider)
          .saveReferences(metadata.key, item.references),
    );
  }

  // The session reports through its own state from here; the returned
  // future completes only when the session ends.
  unawaited(
    ref
        .read(playbackSessionProvider.notifier)
        .open(
          PlaybackRequest.fromPool(
            session.pool!,
            playbackKey: episode == null
                ? metadata.key
                : '${metadata.key}|s${episode.seasonNumber}e${episode.episodeNumber}',
            title: metadata.title,
            subtitle: episode == null
                ? null
                : 'Season ${episode.seasonNumber}'
                      ' · Episode ${episode.episodeNumber}',
            // Persistence identity (2F): the parent key plus the episode
            // numbers, so an episode's progress can never land on another one.
            mediaKey: metadata.key,
            mediaType: metadata.type,
            seasonNumber: episode?.seasonNumber,
            episodeNumber: episode?.episodeNumber,
            startPosition: startPosition,
          ),
        ),
  );

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (BuildContext _) => const PlaybackView()),
  );
  // PlaybackView.dispose calls leave(): the session is reset when the user
  // exits the surface; nothing else to do here.
}

/// Honest, non-throwing "nothing playable" notice for the details surface.
void _showNoSources(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('No sources were found for this item. Try again later.'),
    ),
  );
}
