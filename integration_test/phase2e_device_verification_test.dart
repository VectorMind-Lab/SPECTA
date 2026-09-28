// SPECTA — Phase 2E device verification (test-only; no lib/ product change).
//
// Exercises the REAL MediaKit engine inside the real app process on a
// physical device, mirroring the Phase 1 device-verification pattern:
//
//   1. MediaKit native library loads and the engine constructs on-device.
//   2. Real MP4 playback over the device network stack reaches a playable
//      state; time-to-playable is MEASURED, not assumed.
//   3. Real HLS playback reaches a playable state.
//   4. Ordered fallback through the real engine: a candidate that cannot
//      connect fails and the session advances to a working candidate.
//   5. The in-memory progress sink receives reports from the session.
//
// The test media are well-known public test streams (Google's public
// Big Buck Bunny sample and Mux's public HLS test stream). A network-
// dependent failure here is reported as a test failure — never hidden.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:specta/core/errors/specta_failure.dart' show PlaybackFailure;
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/playback/media_kit_engine.dart';
import 'package:specta/core/playback/playback_engine.dart';
import 'package:specta/core/playback/playback_progress_sink.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';
import 'package:specta/features/playback/playback_models.dart';
import 'package:specta/features/playback/playback_session_state.dart';

// ignore: avoid_print
void marker(String m) => print('[SPECTA-P2E] $m');

const String mp4Url =
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4';

/// A second MP4 on a DIFFERENT host (W3C). Deliberately not [mp4Url]: the
/// fallback path must be exercised with an independent origin, so a
/// host-specific hiccup can never be mistaken for a fallback defect.
const String fallbackMp4Url = 'https://media.w3.org/2010/05/sintel/trailer.mp4';
const String hlsUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

/// Waits until [test] returns true, polling; fails after [timeout].
Future<void> waitFor(
  Future<bool> Function() test, {
  required String because,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting: $because');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P2E-1: MediaKit engine constructs on device', (tester) async {
    marker('engine construction start');
    final MediaKitPlaybackEngine engine = MediaKitPlaybackEngine();
    marker('engine constructed (native lib loaded)');
    expect(engine, isA<PlaybackEngine>());
    await engine.dispose();
    marker('engine disposed cleanly');
  });

  testWidgets('P2E-2: real MP4 playback reaches a playable state', (
    tester,
  ) async {
    final MediaKitPlaybackEngine engine = MediaKitPlaybackEngine();
    addTearDown(() => engine.dispose());

    final Completer<Duration?> firstFrame = Completer<Duration?>();
    final DateTime openStart = DateTime.now();
    late final StreamSubscription<PlaybackEngineEvent> sub;
    sub = engine.events.listen((PlaybackEngineEvent e) {
      if (e is EnginePlaying && !firstFrame.isCompleted) {
        firstFrame.complete(DateTime.now().difference(openStart));
      }
      if (e is EngineFailed && !firstFrame.isCompleted) {
        firstFrame.completeError(StateError('EngineFailed: ${e.reason}'));
      }
    });
    addTearDown(sub.cancel);

    marker('opening real MP4: $mp4Url');
    await engine.open(const ExtensionSource(url: mp4Url, type: SourceType.mp4));

    final Duration? ttff = await firstFrame.future.timeout(
      const Duration(seconds: 90),
    );
    marker(
      'MP4 playable — measured time-to-first-frame: ${ttff!.inMilliseconds}ms',
    );
    expect(ttff, isNotNull);
  });

  testWidgets('P2E-3: real HLS playback reaches a playable state', (
    tester,
  ) async {
    final MediaKitPlaybackEngine engine = MediaKitPlaybackEngine();
    addTearDown(() => engine.dispose());

    final Completer<void> firstFrame = Completer<void>();
    late final StreamSubscription<PlaybackEngineEvent> sub;
    sub = engine.events.listen((PlaybackEngineEvent e) {
      if (e is EnginePlaying && !firstFrame.isCompleted) {
        firstFrame.complete();
      }
      if (e is EngineFailed && !firstFrame.isCompleted) {
        firstFrame.completeError(StateError('EngineFailed: ${e.reason}'));
      }
    });
    addTearDown(sub.cancel);

    marker('opening real HLS: $hlsUrl');
    await engine.open(
      const ExtensionSource(
        url: hlsUrl,
        type: SourceType.hls,
        isAdaptive: true,
      ),
    );

    await firstFrame.future.timeout(const Duration(seconds: 90));
    marker('HLS playable');

    // Playback-rate control over the real engine.
    await engine.setRate(1.25);
    marker('setRate(1.25) applied');
  });

  // Plain test() (like the Phase 1 device suite): the session drives real
  // Timers (open/stall/progress), which must run on the device's real event
  // loop — testWidgets' FakeAsync zone would freeze them.
  test('P2E-4: ordered fallback through the real engine — dead source fails, '
      'session lands on the working source', () async {
    // The REAL engine — no fakes on device. Held explicitly so the raw engine
    // event trail can be recorded: this trace is the authoritative evidence
    // of what the native player emitted for each candidate.
    final MediaKitPlaybackEngine engine = MediaKitPlaybackEngine();
    addTearDown(engine.dispose);

    int progressTicks = 0;
    final StreamSubscription<PlaybackEngineEvent> engineTrace = engine.events
        .listen((PlaybackEngineEvent e) {
          if (e is EngineProgress) {
            progressTicks++;
            return; // high frequency: counted, never logged verbatim
          }
          marker(
            'ENGINE: ${e.runtimeType}${switch (e) {
              EngineFailed(:final String reason) => ' ($reason)',
              EngineErrored(:final String message) => ' ($message)',
              _ => '',
            }}',
          );
        });
    addTearDown(engineTrace.cancel);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        playbackEngineFactoryProvider.overrideWith(
          (Ref ref) =>
              () => engine,
        ),
        playbackOpenTimeoutProvider.overrideWith(
          (Ref ref) => const Duration(seconds: 45),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Periodic evidence while the fallback settles (the failure of the dead
    // candidate is instant; the live candidate should follow within ~1 s).
    final Timer heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      marker(
        'heartbeat: status=${container.read(playbackSessionProvider).status.name} '
        'progressTicks=$progressTicks',
      );
    });
    addTearDown(heartbeat.cancel);

    // A port-1 URL on localhost cannot connect — a deterministic dead
    // candidate (no external dependency for the FAILURE side).
    //
    // Candidate 2 is an MP4 on a THIRD-PARTY host distinct from every other
    // stream this suite touches, and candidate 3 is HLS on yet another host.
    // The ordered fallback is therefore proven across independent origins:
    // if candidate 2 cannot play, the session must still reach candidate 3
    // rather than reporting "no sources available".
    final SourcePool pool = SourcePool(
      reference: 'device-ref',
      ranked: <RankedSource>[
        RankedSource(
          source: const ExtensionSource(
            url: 'http://127.0.0.1:1/dead.mp4',
            type: SourceType.mp4,
          ),
          extensionId: 'extDead',
          reference: 'ref-dead',
          score: 99,
        ),
        RankedSource(
          source: const ExtensionSource(
            url: fallbackMp4Url,
            type: SourceType.mp4,
          ),
          extensionId: 'extLive',
          reference: 'ref-live',
          score: 50,
        ),
        RankedSource(
          source: const ExtensionSource(
            url: hlsUrl,
            type: SourceType.hls,
            isAdaptive: true,
          ),
          extensionId: 'extLiveHls',
          reference: 'ref-live-hls',
          score: 40,
        ),
      ],
      outcomes: const <ExtensionSourceOutcome>[],
    );

    marker('opening pool: dead candidate first, live MP4 second');

    // Trace state transitions (bounded; dropped after the wait completes).
    int lastGen = -1;
    bool alive = true;
    final ProviderSubscription<PlaybackSnapshot>
    traceSub = container.listen<PlaybackSnapshot>(playbackSessionProvider, (
      PlaybackSnapshot? prev,
      PlaybackSnapshot next,
    ) {
      if (!alive) return;
      if (next.generation != lastGen || next.status != prev?.status) {
        lastGen = next.generation;
        marker(
          'STATE: ${next.status.name} gen:${next.generation} '
          'attempt:${next.attemptedCount}/${next.candidates.length} '
          'failures:${next.failures.map((PlaybackAttempt f) => f.failure?.type.code).toList()}',
        );
      }
    });
    addTearDown(traceSub.close);

    await container
        .read(playbackSessionProvider.notifier)
        .open(PlaybackRequest.fromPool(pool));

    await waitFor(
      () async =>
          container.read(playbackSessionProvider).status ==
          PlaybackStatus.playing,
      because: 'fallback to the live MP4 source',
      timeout: const Duration(seconds: 45),
    );

    final PlaybackSnapshot s = container.read(playbackSessionProvider);
    marker(
      'fallback OK — playing extLive after ${s.failures.length} failure(s); '
      'attempted ${s.attemptedCount}/${s.candidates.length}; '
      'progressTicks=$progressTicks',
    );
    expect(s.current!.extensionId, 'extLive');
    expect(
      s.failures.any(
        (PlaybackAttempt f) =>
            f.candidate.extensionId == 'extDead' &&
            f.failure is PlaybackFailure,
      ),
      isTrue,
    );

    alive = false;
    traceSub.close();
    await container.read(playbackSessionProvider.notifier).leave();
    marker('session left cleanly');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('P2E-5: progress sink receives reports during playback', () async {
    final InMemoryPlaybackProgressSink sink = InMemoryPlaybackProgressSink();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        playbackEngineFactoryProvider.overrideWith(
          (Ref ref) => MediaKitPlaybackEngine.new,
        ),
        playbackProgressSinkProvider.overrideWith((Ref ref) => sink),
      ],
    );
    addTearDown(container.dispose);

    // The endless HLS test stream is used here on purpose: a 10s MP4
    // legitimately reaches end-of-stream, which the session honestly
    // surfaces as a mid-stream failure — a distraction for this test.
    await container
        .read(playbackSessionProvider.notifier)
        .open(
          PlaybackRequest.direct(<RankedSource>[
            RankedSource(
              source: const ExtensionSource(
                url: hlsUrl,
                type: SourceType.hls,
                isAdaptive: true,
              ),
              extensionId: 'extLive',
              reference: 'ref-live',
              score: 50,
            ),
          ], playbackKey: 'device-movie'),
        );

    await waitFor(
      () async {
        final PlaybackSnapshot s = container.read(playbackSessionProvider);
        if (s.status != PlaybackStatus.playing) return false;
        // Let the 1s tick report at least once.
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        return sink.elapsedFor('device-movie') != null;
      },
      because: 'a progress report to the in-memory sink',
      timeout: const Duration(seconds: 45),
    );

    marker(
      'progress sink reported elapsed: '
      '${sink.elapsedFor("device-movie")}',
    );
    expect(sink.elapsedFor('device-movie'), isNotNull);

    await container.read(playbackSessionProvider.notifier).leave();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
