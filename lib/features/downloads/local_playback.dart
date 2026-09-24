/// Offline playback of a completed download (Phase 2J/2K).
///
/// This closes a real V1 gap: the download engine could produce a finished file
/// on disk, but nothing in the product could play it. This seam is what makes
/// acceptance criterion "play downloaded media offline" true.
///
/// Design notes — why this is not a second playback path:
///
/// * It reuses the UNCHANGED 2E player session. It hands
///   [PlaybackSessionNotifier] a [PlaybackRequest.direct] with ONE candidate,
///   exactly as the extension path hands it a resolved pool. Controls, ordered
///   fallback, the honest state machine, immersive/orientation handling, TV
///   focus and the progress sink are all the same code.
/// * It does NOT touch the SourceManager, the SourceValidator or the extension
///   runtime. `SourceValidator` deliberately refuses non-http(s) schemes, and
///   that rule is left exactly as it is: a file on this device is not an
///   extension-discovered source and must not be laundered into one.
/// * It does NOT go through the network. A download is played because it is
///   already on disk, which is what makes it work with no connectivity.
/// * Progress identity is the record's own id (`<mediaKey>` for a movie,
///   `<mediaKey>|s<S>e<E>` for an episode) — the SAME identity the streaming
///   path and the library already use, so offline viewing updates Continue
///   Watching and can be resumed from it. No second identity, no second
///   progress row.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_models.dart';
import '../../core/extensions/contract/extension_source.dart';
import '../../core/sources/source_pool.dart';
import '../playback/playback_session_state.dart';
import '../playback/playback_view.dart';

/// Provenance id for a source that came from local storage rather than from an
/// extension.
///
/// It is deliberately not shaped like an extension id and is never resolved
/// through the extension manager: if anything ever tried to treat it as one,
/// the lookup would fail loudly rather than silently querying some extension.
const String localPlaybackSourceId = 'local.download';

/// Plays a COMPLETED download from local storage.
///
/// Every refusal is honest and explained to the user:
/// * the record is not completed yet → say so, do not attempt playback;
/// * the file is missing (deleted outside the app, or a wiped storage volume)
///   → say so, do not open a player that would fail obscurely.
Future<void> startLocalPlayback(
  BuildContext context, {
  required WidgetRef ref,
  required DownloadRecord record,
}) async {
  if (record.status != DownloadStatus.completed) {
    _notice(
      context,
      'This download is not finished yet. It will be playable once it completes.',
    );
    return;
  }

  final File file = File(record.filePath);
  final bool exists = await file.exists();
  if (!context.mounted) return;
  if (!exists) {
    _notice(
      context,
      'The downloaded file is no longer on this device. Download it again to '
      'watch it offline.',
    );
    return;
  }

  // The V1 download system transfers a single progressive file, so the local
  // candidate is a direct mp4. The plain on-disk path is handed to the engine
  // (MediaKit gives this string to mpv, which reads a local file directly) —
  // no `file://` wrapping, so no percent-encoding to get wrong. If the
  // download format ever stops being a single mp4, this is the one place that
  // has to change.
  final RankedSource candidate = RankedSource(
    source: ExtensionSource(
      url: record.filePath,
      type: SourceType.mp4,
      label: 'Downloaded',
    ),
    extensionId: localPlaybackSourceId,
    reference: record.filePath,
    score: 0,
  );

  unawaited(
    ref
        .read(playbackSessionProvider.notifier)
        .open(
          PlaybackRequest.direct(
            <RankedSource>[candidate],
            // The persisted download identity IS the playback identity, so an
            // offline session reports progress to the same library row the
            // streaming session would have.
            playbackKey: record.id,
            title: record.title,
            subtitle: record.subtitleLine,
            mediaKey: record.mediaKey,
            mediaType: record.mediaType,
            seasonNumber: record.seasonNumber,
            episodeNumber: record.episodeNumber,
          ),
        ),
  );

  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (BuildContext _) => const PlaybackView()),
  );
}

void _notice(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(message),
    ),
  );
}
