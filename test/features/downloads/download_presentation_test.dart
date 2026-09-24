@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/features/downloads/download_presentation.dart';

/// Phase 2K: the Downloads surface's decisions about a *record* are pure
/// functions, so exactly what the UI will offer is testable without a widget
/// tree. These tests pin the rules that matter: a control is offered only
/// where the manager will accept it, waiting/failure text is shown only while
/// it is true, and nothing is invented (no fraction without a real total, no
/// fabricated byte precision).
DownloadRecord record({
  String id = 'D',
  DownloadStatus status = DownloadStatus.queued,
  DownloadWaitReason? waitReason,
  DownloadFailure? failure,
  int bytesDownloaded = 0,
  int? totalBytes,
  DateTime? createdAt,
  int? seasonNumber,
  int? episodeNumber,
}) {
  final DateTime stamp = createdAt ?? DateTime.utc(2026, 1, 1);
  return DownloadRecord(
    id: id,
    mediaKey: 'Movie|movie|2024',
    mediaType: seasonNumber == null ? MediaType.movie : MediaType.series,
    title: 'A Title',
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    status: status,
    waitReason: waitReason,
    bytesDownloaded: bytesDownloaded,
    totalBytes: totalBytes,
    filePath: '/tmp/a.mp4',
    attempt: 0,
    failure: failure,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

void main() {
  group('downloadActionsFor', () {
    test('mirrors the manager state machine exactly', () {
      expect(downloadActionsFor(DownloadStatus.queued), <DownloadAction>[
        DownloadAction.pause,
        DownloadAction.cancel,
      ]);
      expect(downloadActionsFor(DownloadStatus.downloading), <DownloadAction>[
        DownloadAction.pause,
        DownloadAction.cancel,
      ]);
      expect(downloadActionsFor(DownloadStatus.paused), <DownloadAction>[
        DownloadAction.resume,
        DownloadAction.cancel,
      ]);
      expect(downloadActionsFor(DownloadStatus.failed), <DownloadAction>[
        DownloadAction.retry,
        DownloadAction.remove,
      ]);
      expect(downloadActionsFor(DownloadStatus.cancelled), <DownloadAction>[
        DownloadAction.retry,
        DownloadAction.remove,
      ]);
      expect(downloadActionsFor(DownloadStatus.completed), <DownloadAction>[
        DownloadAction.play,
        DownloadAction.remove,
      ]);
    });

    test('play is offered only for a completed download', () {
      for (final DownloadStatus status in DownloadStatus.values) {
        expect(
          downloadActionsFor(status).contains(DownloadAction.play),
          isPlayable(status),
          reason: 'status $status',
        );
      }
    });
  });

  group('downloadSecondaryLine', () {
    test('is null when there is nothing honest to add', () {
      expect(downloadSecondaryLine(record()), isNull);
      expect(
        downloadSecondaryLine(
          record(status: DownloadStatus.downloading, bytesDownloaded: 5),
        ),
        isNull,
      );
    });

    test('shows a wait reason only while the record is actually waiting', () {
      expect(
        downloadSecondaryLine(
          record(
            status: DownloadStatus.queued,
            waitReason: DownloadWaitReason.waitingForWifi,
          ),
        ),
        'Waiting for Wi-Fi',
      );
      expect(
        downloadSecondaryLine(
          record(
            status: DownloadStatus.paused,
            waitReason: DownloadWaitReason.waitingForSlot,
          ),
        ),
        'Waiting in queue',
      );
      // A wait reason on a running or terminal record is stale — not shown.
      expect(
        downloadSecondaryLine(
          record(
            status: DownloadStatus.completed,
            waitReason: DownloadWaitReason.waitingForWifi,
          ),
        ),
        isNull,
      );
    });

    test('shows a failure message only while the record is failed', () {
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.httpError,
        message: 'The server refused the download.',
      );
      expect(
        downloadSecondaryLine(
          record(status: DownloadStatus.failed, failure: failure),
        ),
        'The server refused the download.',
      );
      expect(
        downloadSecondaryLine(
          record(status: DownloadStatus.cancelled, failure: failure),
        ),
        isNull,
      );
    });
  });

  group('downloadProgressText and downloadFraction', () {
    test('reports only the downloaded amount when the total is unknown', () {
      final DownloadRecord r = record(bytesDownloaded: 2048);
      expect(downloadProgressText(r), '2.0 KB');
      expect(downloadFraction(r), isNull);
    });

    test('reports both sides when the total is known', () {
      final DownloadRecord r =
          record(bytesDownloaded: 1024, totalBytes: 4096);
      expect(downloadProgressText(r), '1.0 KB of 4.0 KB');
      expect(downloadFraction(r), 0.25);
    });

    test('never invents a fraction from a zero or negative total', () {
      expect(downloadFraction(record(bytesDownloaded: 10, totalBytes: 0)), isNull);
      expect(
        downloadFraction(record(bytesDownloaded: 10, totalBytes: -5)),
        isNull,
      );
    });

    test('formatBytes is decimal-unit and never fabricates precision', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
      // Above 100 units the fractional digit is dropped (not invented).
      expect(formatBytes(200 * 1024), '200 KB');
    });
  });

  group('orderDownloadsForDisplay', () {
    test('puts actionable work first and finished work last', () {
      final List<DownloadRecord> ordered = orderDownloadsForDisplay(<DownloadRecord>[
        record(id: 'c', status: DownloadStatus.completed),
        record(id: 'f', status: DownloadStatus.failed),
        record(id: 'a', status: DownloadStatus.downloading),
        record(id: 'q', status: DownloadStatus.queued),
        record(id: 'p', status: DownloadStatus.paused),
        record(id: 'x', status: DownloadStatus.cancelled),
      ]);
      expect(
        ordered.map((DownloadRecord r) => r.id).toList(),
        <String>['a', 'q', 'p', 'f', 'x', 'c'],
      );
    });

    test('is deterministic within a group (created time, then identity)', () {
      final List<DownloadRecord> ordered = orderDownloadsForDisplay(<DownloadRecord>[
        record(
          id: 'b',
          status: DownloadStatus.completed,
          createdAt: DateTime.utc(2026, 1, 2),
        ),
        record(
          id: 'a',
          status: DownloadStatus.completed,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        record(
          id: 'z',
          status: DownloadStatus.completed,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      expect(
        ordered.map((DownloadRecord r) => r.id).toList(),
        <String>['a', 'z', 'b'],
      );
    });

    test('does not mutate the input list', () {
      final List<DownloadRecord> input = <DownloadRecord>[
        record(id: 'c', status: DownloadStatus.completed),
        record(id: 'a', status: DownloadStatus.downloading),
      ];
      orderDownloadsForDisplay(input);
      expect(input.map((DownloadRecord r) => r.id).toList(), <String>['c', 'a']);
    });
  });

  group('downloadStateLabel and downloadActionLabel', () {
    test('every status has a short, non-technical label', () {
      expect(downloadStateLabel(DownloadStatus.queued), 'Queued');
      expect(downloadStateLabel(DownloadStatus.downloading), 'Downloading');
      expect(downloadStateLabel(DownloadStatus.paused), 'Paused');
      expect(downloadStateLabel(DownloadStatus.completed), 'Downloaded');
      expect(downloadStateLabel(DownloadStatus.failed), 'Failed');
      expect(downloadStateLabel(DownloadStatus.cancelled), 'Cancelled');
    });

    test('every action has one canonical label', () {
      for (final DownloadAction action in DownloadAction.values) {
        expect(downloadActionLabel(action), isNotEmpty);
      }
    });
  });
}
