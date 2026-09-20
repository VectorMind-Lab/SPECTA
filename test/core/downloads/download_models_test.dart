@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/downloads/download_models.dart';
import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/result_models.dart';

void main() {
  group('DownloadIdentity', () {
    test('a movie download uses the media key itself', () {
      expect(
        DownloadIdentity.forMovie('Movie|movie|2024'),
        'Movie|movie|2024',
      );
    });

    test('an episode download is episode-qualified exactly like 2F progress',
        () {
      expect(
        DownloadIdentity.forEpisode('Show|series|2024', 1, 2),
        'Show|series|2024|s1e2',
      );
    });

    test('different episodes of one show can never collide', () {
      final String s1e1 = DownloadIdentity.forEpisode('Show|series|2024', 1, 1);
      final String s1e2 = DownloadIdentity.forEpisode('Show|series|2024', 1, 2);
      final String s2e1 = DownloadIdentity.forEpisode('Show|series|2024', 2, 1);

      expect(s1e1, isNot(s1e2));
      expect(s1e1, isNot(s2e1));
      expect(s1e2, isNot(s2e1));
    });

    test('an episode download differs from its parent movie download', () {
      final String parent = DownloadIdentity.forMovie('Show|series|2024');
      final String episode =
          DownloadIdentity.forEpisode('Show|series|2024', 1, 1);

      expect(episode, isNot(parent));
    });

    test('isEpisode recognises episode identities and refuses others', () {
      expect(
        DownloadIdentity.isEpisode('Show|series|2024|s1e2'),
        isTrue,
      );
      expect(DownloadIdentity.isEpisode('Movie|movie|2024'), isFalse);
      expect(DownloadIdentity.isEpisode('no separator at all'), isFalse);
      expect(DownloadIdentity.isEpisode('Show|series|2024|garbage'), isFalse);
      expect(DownloadIdentity.isEpisode(''), isFalse);
    });

    test('identities match the 2F watch-progress key format', () {
      // The 2F device run persisted exactly this key shape
      // (__p2f_test__|series|2026|s1e2); downloads must not fork it.
      expect(
        DownloadIdentity.forEpisode('__p2f_test__|series|2026', 1, 2),
        '__p2f_test__|series|2026|s1e2',
      );
    });
  });

  group('DownloadStateMachine', () {
    test('every documented transition is allowed', () {
      const List<(DownloadStatus, DownloadStatus)> documented = <(
        DownloadStatus,
        DownloadStatus
      )>[
        (DownloadStatus.queued, DownloadStatus.downloading),
        (DownloadStatus.queued, DownloadStatus.cancelled),
        (DownloadStatus.downloading, DownloadStatus.paused),
        (DownloadStatus.downloading, DownloadStatus.completed),
        (DownloadStatus.downloading, DownloadStatus.failed),
        (DownloadStatus.downloading, DownloadStatus.cancelled),
        (DownloadStatus.paused, DownloadStatus.downloading),
        // paused→queued: an explicit user resume routed through the queue
        // when SPECTA's concurrency policy has no free slot (2G-B).
        (DownloadStatus.paused, DownloadStatus.queued),
        (DownloadStatus.paused, DownloadStatus.cancelled),
        (DownloadStatus.failed, DownloadStatus.queued),
        (DownloadStatus.failed, DownloadStatus.cancelled),
        (DownloadStatus.cancelled, DownloadStatus.queued),
      ];

      for (final (DownloadStatus from, DownloadStatus to) in documented) {
        expect(
          DownloadStateMachine.canTransition(from, to),
          isTrue,
          reason: '$from → $to is a documented transition',
        );
      }
    });

    test('every undeclared transition is refused', () {
      const List<DownloadStatus> all = <DownloadStatus>[
        DownloadStatus.queued,
        DownloadStatus.downloading,
        DownloadStatus.paused,
        DownloadStatus.completed,
        DownloadStatus.failed,
        DownloadStatus.cancelled,
      ];

      for (final DownloadStatus from in all) {
        for (final DownloadStatus to in all) {
          final bool documented =
              DownloadStateMachine.canTransition(from, to);
          // Re-check the exact documented set; everything else must refuse.
          final bool allowed = switch (from) {
                DownloadStatus.queued =>
                  to == DownloadStatus.downloading ||
                      to == DownloadStatus.cancelled,
                DownloadStatus.downloading =>
                  to == DownloadStatus.paused ||
                      to == DownloadStatus.completed ||
                      to == DownloadStatus.failed ||
                      to == DownloadStatus.cancelled,
                DownloadStatus.paused => to == DownloadStatus.downloading ||
                    to == DownloadStatus.queued ||
                    to == DownloadStatus.cancelled,
                DownloadStatus.failed => to == DownloadStatus.queued ||
                    to == DownloadStatus.cancelled,
                DownloadStatus.cancelled =>
                  to == DownloadStatus.queued,
                DownloadStatus.completed => false,
              };
          expect(documented, allowed,
              reason: '$from → $to must match the documented machine');
        }
      }
    });

    test('completed is terminal — nothing may leave it', () {
      for (final DownloadStatus to in DownloadStatus.values) {
        expect(
          DownloadStateMachine.canTransition(DownloadStatus.completed, to),
          isFalse,
          reason: 'completed → $to must be refused',
        );
      }
    });

    test('a user retry re-queues failed and cancelled work, nothing else', () {
      expect(
        DownloadStateMachine.canTransition(
            DownloadStatus.failed, DownloadStatus.queued),
        isTrue,
      );
      expect(
        DownloadStateMachine.canTransition(
            DownloadStatus.cancelled, DownloadStatus.queued),
        isTrue,
      );
      expect(
        DownloadStateMachine.canTransition(
            DownloadStatus.completed, DownloadStatus.queued),
        isFalse,
      );
    });

    test('status codes round-trip and activity classification holds', () {
      expect(DownloadStatus.fromCode('queued'), DownloadStatus.queued);
      expect(DownloadStatus.fromCode('downloading'),
          DownloadStatus.downloading);
      expect(DownloadStatus.fromCode('nonsense'), isNull);
      expect(DownloadStatus.fromCode(null), isNull);

      expect(DownloadStatus.queued.isActive, isTrue);
      expect(DownloadStatus.downloading.isActive, isTrue);
      expect(DownloadStatus.paused.isActive, isTrue);
      expect(DownloadStatus.completed.isActive, isFalse);
      expect(DownloadStatus.failed.isTerminal, isTrue);
      expect(DownloadStatus.cancelled.isTerminal, isTrue);
      expect(DownloadStatus.downloading.isTerminal, isFalse);
    });
  });

  group('DownloadFailure (failure-model integration)', () {
    test('is a SpectaFailure — the sealed hierarchy accepted it', () {
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.networkError,
        message: 'The network dropped during the download.',
      );

      expect(failure, isA<SpectaFailure>());
      expect(failure.isRetryable, isTrue);
    });

    test('default retryability comes from the failure type', () {
      const List<DownloadFailureType> retryable = <DownloadFailureType>[
        DownloadFailureType.networkError,
        DownloadFailureType.timeout,
        DownloadFailureType.serverError,
        DownloadFailureType.storageFailure,
      ];
      const List<DownloadFailureType> notRetryable = <DownloadFailureType>[
        DownloadFailureType.httpError,
        DownloadFailureType.invalidResponse,
        DownloadFailureType.insufficientStorage,
        DownloadFailureType.unsupportedSource,
        DownloadFailureType.sourcesExhausted,
      ];

      for (final DownloadFailureType type in retryable) {
        expect(
          DownloadFailure(type: type, message: type.message).isRetryable,
          isTrue,
          reason: '${type.code} defaults to retryable',
        );
      }
      for (final DownloadFailureType type in notRetryable) {
        expect(
          DownloadFailure(type: type, message: type.message).isRetryable,
          isFalse,
          reason: '${type.code} defaults to non-retryable',
        );
      }
    });

    test('an explicit isRetryable overrides the type default', () {
      final DownloadFailure overridable = DownloadFailure(
        type: DownloadFailureType.httpError,
        message: 'Server refused.',
        isRetryable: true,
      );
      final DownloadFailure hardened = DownloadFailure(
        type: DownloadFailureType.networkError,
        message: 'Network dropped.',
        isRetryable: false,
      );

      expect(overridable.isRetryable, isTrue);
      expect(hardened.isRetryable, isFalse);
    });

    test('codes round-trip and unknown codes are refused', () {
      for (final DownloadFailureType type in DownloadFailureType.values) {
        expect(DownloadFailureType.fromCode(type.code), type);
      }
      expect(DownloadFailureType.fromCode('NO_SUCH_CODE'), isNull);
      expect(DownloadFailureType.fromCode(null), isNull);
    });

    test('every type carries honest, non-empty user-facing wording', () {
      for (final DownloadFailureType type in DownloadFailureType.values) {
        expect(type.message, isNotEmpty, reason: '${type.code} wording');
        expect(type.message, isNot(contains('Exception')));
      }
    });

    test('diagnostics expose the stable code, never more', () {
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.timeout,
        message: 'The download stalled for too long.',
        detail: 'idle for 45s',
      );

      expect(failure.toDiagnostics(), <String, Object?>{
        'errorType': 'TIMEOUT',
        'message': 'The download stalled for too long.',
        'detail': 'idle for 45s',
      });
      expect(failure.toString(), startsWith('TIMEOUT '));
    });

    test('a caller switching over SpectaFailure handles downloads '
        'exhaustively — the sealed hierarchy includes them', () {
      // This switch only compiles if DownloadFailure is part of the sealed
      // SpectaFailure hierarchy AND every subtype is covered — the same
      // exhaustiveness guarantee PlaybackFailure relies on.
      String describe(SpectaFailure failure) => switch (failure) {
            ExtensionFailure() => 'extension',
            PlaybackFailure() => 'playback',
            StorageFailure() => 'storage',
            CapabilityFailure() => 'capability',
            DownloadFailure() => 'download',
          };

      expect(
        describe(
          DownloadFailure(
            type: DownloadFailureType.sourcesExhausted,
            message: 'No downloadable source could be found for this item.',
          ),
        ),
        'download',
      );
    });
  });

  group('evaluateNetworkPolicy', () {
    test('Wi-Fi-only allows a provably unmetered network', () {
      final NetworkPolicyVerdict wifi =
          evaluateNetworkPolicy(DownloadNetworkPolicy.wifiOnly, NetworkAccess.wifi);
      final NetworkPolicyVerdict ethernet = evaluateNetworkPolicy(
          DownloadNetworkPolicy.wifiOnly, NetworkAccess.ethernet);

      expect(wifi.isAllowed, isTrue);
      expect(wifi.waitReason, isNull);
      expect(ethernet.isAllowed, isTrue);
    });

    test('Wi-Fi-only conservatively blocks what it cannot prove unmetered',
        () {
      final NetworkPolicyVerdict mobile = evaluateNetworkPolicy(
          DownloadNetworkPolicy.wifiOnly, NetworkAccess.mobile);
      final NetworkPolicyVerdict unknown = evaluateNetworkPolicy(
          DownloadNetworkPolicy.wifiOnly, NetworkAccess.unknown);
      final NetworkPolicyVerdict other = evaluateNetworkPolicy(
          DownloadNetworkPolicy.wifiOnly, NetworkAccess.other);

      expect(mobile.isAllowed, isFalse);
      expect(mobile.waitReason, DownloadWaitReason.waitingForWifi);
      expect(unknown.isAllowed, isFalse);
      expect(other.isAllowed, isFalse);
    });

    test('no network at all is blocked regardless of policy', () {
      for (final DownloadNetworkPolicy policy in DownloadNetworkPolicy.values) {
        final NetworkPolicyVerdict verdict =
            evaluateNetworkPolicy(policy, NetworkAccess.none);

        expect(verdict.isAllowed, isFalse);
        expect(verdict.waitReason, DownloadWaitReason.waitingForWifi);
      }
    });

    test('wifiAndMobile accepts mobile data but never offline', () {
      expect(
        evaluateNetworkPolicy(
                DownloadNetworkPolicy.wifiAndMobile, NetworkAccess.mobile)
            .isAllowed,
        isTrue,
      );
      expect(
        evaluateNetworkPolicy(
                DownloadNetworkPolicy.wifiAndMobile, NetworkAccess.wifi)
            .isAllowed,
        isTrue,
      );
      expect(
        evaluateNetworkPolicy(
                DownloadNetworkPolicy.wifiAndMobile, NetworkAccess.none)
            .isAllowed,
        isFalse,
      );
    });

    test('the unknown-code default is the conservative policy', () {
      expect(
        DownloadNetworkPolicy.fromCode('nonsense'),
        DownloadNetworkPolicy.wifiOnly,
      );
      expect(
        DownloadNetworkPolicy.fromCode(null),
        DownloadNetworkPolicy.wifiOnly,
      );
      expect(
        DownloadNetworkPolicy.fromCode('wifiAndMobile'),
        DownloadNetworkPolicy.wifiAndMobile,
      );
    });

    test('network access codes degrade to unknown, never guessed', () {
      expect(NetworkAccess.fromCode('wifi'), NetworkAccess.wifi);
      expect(NetworkAccess.fromCode('mobile'), NetworkAccess.mobile);
      expect(NetworkAccess.fromCode('nonsense'), NetworkAccess.unknown);
      expect(NetworkAccess.fromCode(null), NetworkAccess.unknown);
      expect(NetworkAccess.mobile.isMeteredLike, isTrue);
      expect(NetworkAccess.unknown.isMeteredLike, isTrue);
      expect(NetworkAccess.wifi.isMeteredLike, isFalse);
    });
  });

  group('downloadFileStem', () {
    test('is deterministic for the same identity and title', () {
      final String first = downloadFileStem('Movie|movie|2024', 'Dune');
      final String second = downloadFileStem('Movie|movie|2024', 'Dune');

      expect(first, second);
    });

    test('distinct identities never share a file even with equal titles', () {
      final String movie = downloadFileStem('Show|series|2024', 'Show');
      final String episode =
          downloadFileStem('Show|series|2024|s1e2', 'Show');

      expect(movie, isNot(episode));
    });

    test('sanitizes path separators and traversal attempts away', () {
      final String traversal =
          downloadFileStem('x|movie|2024', r'../../etc/passwd');
      final String windows = downloadFileStem('y|movie|2024', r'C:\Windows');

      expect(traversal.contains('/'), isFalse);
      expect(traversal.contains(r'\'), isFalse);
      expect(traversal.contains('..'), isFalse);
      expect(windows.contains(r'\'), isFalse);
      expect(windows.contains(':'), isFalse);
    });

    test('collapses hostile whitespace and caps absurdly long titles', () {
      // The documented algorithm maps every character outside
      // [A-Za-z0-9 _-] (including tab/newline) to '_' BEFORE whitespace
      // collapsing — so '  A\t\nMovie   ' becomes 'A__Movie', not 'A Movie'.
      final String spaced =
          downloadFileStem('a|movie|2024', '  A\t\nMovie   ');
      expect(spaced, startsWith('A__Movie ('));

      final String long = downloadFileStem('b|movie|2024', 'M' * 500);
      // stem (≤80) + ' (' + hash + ')'
      expect(long.length, lessThanOrEqualTo(80 + 1 + 10 + 1));
      expect(long, startsWith('M'));
    });

    test('falls back honestly for an empty title', () {
      final String empty = downloadFileStem('c|movie|2024', '   ');

      expect(empty, startsWith('download ('));
    });
  });

  group('DownloadRecord', () {
    DownloadRecord record({
      int? totalBytes,
      int bytesDownloaded = 0,
    }) =>
        DownloadRecord(
          id: 'Movie|movie|2024',
          mediaKey: 'Movie|movie|2024',
          mediaType: MediaType.movie,
          title: 'Movie',
          status: DownloadStatus.downloading,
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
          filePath: '/data/media/Movie (x).mp4',
          attempt: 0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('progress fraction is null when the size is unknown, never invented',
        () {
      expect(record(totalBytes: null).fraction, isNull);
      expect(record(totalBytes: 0).fraction, isNull);
    });

    test('progress fraction is clamped to 0..1', () {
      expect(record(totalBytes: 100, bytesDownloaded: 50).fraction, 0.5);
      expect(record(totalBytes: 100, bytesDownloaded: 150).fraction, 1.0);
    });

    test('copyWith preserves unset fields and can clear nullable ones', () {
      final DownloadRecord base = record(totalBytes: 100).copyWith(
        waitReason: DownloadWaitReason.waitingForSlot,
        failure: DownloadFailure(
          type: DownloadFailureType.timeout,
          message: 'The download stalled for too long.',
        ),
      );

      final DownloadRecord updated = base.copyWith(
        status: DownloadStatus.paused,
        bytesDownloaded: 64,
      );

      expect(updated.status, DownloadStatus.paused);
      expect(updated.bytesDownloaded, 64);
      expect(updated.waitReason, base.waitReason,
          reason: 'unset sentinel must preserve the field');
      expect(updated.failure, base.failure);
      expect(updated.filePath, base.filePath);
      expect(updated.createdAt, base.createdAt);

      final DownloadRecord cleared = base.copyWith(waitReason: null);
      expect(cleared.waitReason, isNull);
    });

    test('episode records identify themselves', () {
      final DownloadRecord episode = DownloadRecord(
        id: 'Show|series|2024|s1e2',
        mediaKey: 'Show|series|2024',
        mediaType: MediaType.series,
        title: 'Show',
        subtitleLine: 'Season 1 · Episode 2',
        seasonNumber: 1,
        episodeNumber: 2,
        status: DownloadStatus.queued,
        bytesDownloaded: 0,
        filePath: '/data/media/Show (x).mp4',
        attempt: 0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      expect(episode.isEpisode, isTrue);
      expect(record().isEpisode, isFalse);
    });
  });

  group('DownloadAttemptResult', () {
    test('completed carries bytes and the declared total', () {
      const DownloadAttemptResult result =
          DownloadAttemptResult.completed(1024, totalBytes: 4096);

      expect(result.isCompleted, isTrue);
      expect(result.bytesOnDisk, 1024);
      expect(result.totalBytes, 4096);
      expect(result.failure, isNull);
    });

    test('paused and cancelled keep the bytes but no total', () {
      const DownloadAttemptResult paused = DownloadAttemptResult.paused(512);
      const DownloadAttemptResult cancelled =
          DownloadAttemptResult.cancelled(256);

      expect(paused.isPaused, isTrue);
      expect(paused.bytesOnDisk, 512);
      expect(paused.totalBytes, isNull);
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.bytesOnDisk, 256);
    });

    test('failed carries the structured failure and bytes on disk', () {
      final DownloadFailure failure = DownloadFailure(
        type: DownloadFailureType.networkError,
        message: 'The network dropped during the download.',
      );
      final DownloadAttemptResult result =
          DownloadAttemptResult.failed(failure, 128);

      expect(result.isFailed, isTrue);
      expect(result.failure, same(failure));
      expect(result.bytesOnDisk, 128);
      expect(result.isCompleted, isFalse);
    });
  });

  group('DownloadWaitReason', () {
    test('codes round-trip and every reason has user-facing wording', () {
      for (final DownloadWaitReason reason in DownloadWaitReason.values) {
        expect(DownloadWaitReason.fromCode(reason.code), reason);
        expect(reason.message, isNotEmpty);
      }
      expect(DownloadWaitReason.fromCode('nonsense'), isNull);
    });
  });
}
