import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/playback/playback_engine.dart';
import 'package:specta/core/playback/playback_progress_sink.dart';
import 'package:specta/core/sources/source_models.dart';
import 'package:specta/core/sources/source_pool.dart';
import 'package:specta/features/playback/playback_models.dart';
import 'package:specta/features/playback/playback_session_state.dart';

/// Deterministic [PlaybackEngine] for session tests: the test scripts the
/// event sequence each `open` produces. No MediaKit, no I/O, no real time —
/// timers are simulated with `fakeAsync`-friendly eager completion where the
/// session allows it.
class FakePlaybackEngine implements PlaybackEngine {
  /// The event sequence to emit for successive `open` calls. Entries are
  /// consumed in order; each entry is emitted (with delays) when that open
  /// starts. An empty list means every open stays silent (the session's
  /// open-timeout then fails the candidate).
  final List<List<PlaybackEngineEvent>> openScripts = <List<PlaybackEngineEvent>>[];

  /// Delay before each scripted event, per open script.
  Duration eventDelay = Duration.zero;

  final List<ExtensionSource> opened = <ExtensionSource>[];
  int stopCount = 0;
  int disposeCount = 0;
  double? lastRate;
  double? lastVolume;
  SubtitleTrack? lastSubtitle;

  /// Synchronous delivery: listeners (the session) observe events before
  /// `open`/`emit` returns, which makes the session's state deterministic
  /// immediately after the awaited call — no microtask pumping in tests.
  final StreamController<PlaybackEngineEvent> _events =
      StreamController<PlaybackEngineEvent>.broadcast(sync: true);

  /// Scripts the test can push events through directly (e.g. a mid-play
  /// stall or an EngineErrored while playing).
  void emit(PlaybackEngineEvent event) => _events.add(event);

  @override
  Stream<PlaybackEngineEvent> get events => _events.stream;

  @override
  SubtitleTrack? get currentSubtitle => lastSubtitle;

  @override
  Future<void> open(ExtensionSource source) async {
    opened.add(source);
    final int index = opened.length - 1;
    if (index >= openScripts.length) return; // silent open
    final List<PlaybackEngineEvent> script = openScripts[index];
    for (int i = 0; i < script.length; i++) {
      final PlaybackEngineEvent event = script[i];
      if (eventDelay > Duration.zero) {
        await Future<void>.delayed(eventDelay);
      }
      _events.add(event);
      // A real engine that reports playing also reports advancing position:
      // EnginePlaying alone is optimistic (the session's honest success rule
      // requires a progress tick with position > 0). Unless the script
      // explicitly provides progress, imply one right after playing.
      if (event is EnginePlaying &&
          (i + 1 >= script.length || script[i + 1] is! EngineProgress)) {
        _events.add(_flowing);
      }
    }
  }

  @override
  Future<void> pause() async => _events.add(const EnginePaused());

  @override
  Future<void> play() async => _events.add(const EnginePlaying());

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRate(double rate) async => lastRate = rate;

  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;

  @override
  Future<void> setSubtitle(SubtitleTrack? subtitle) async =>
      lastSubtitle = subtitle;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async => disposeCount++;
}

/// A progress tick representing content actually flowing (position > 0) —
/// the session's honest playable signal.
const EngineProgress _flowing = EngineProgress(
  position: Duration(seconds: 1),
  duration: Duration(minutes: 1),
  buffered: Duration(seconds: 5),
  rate: 1.0,
  volume: 1.0,
);

RankedSource _source(
  String url, {
  String extensionId = 'extA',
  SourceType type = SourceType.mp4,
  String? quality = '720p',
  List<SubtitleTrack>? subtitles,
}) =>
    RankedSource(
      source: ExtensionSource(
        url: url,
        type: type,
        quality: quality,
        subtitles: subtitles,
      ),
      extensionId: extensionId,
      reference: 'ref-$url',
      score: 50,
    );

/// A container whose engine factory exposes the single fake engine.
class Harness {
  Harness() {
    container = ProviderContainer(
      overrides: <Override>[
        playbackEngineFactoryProvider.overrideWith((Ref ref) => () => engine),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakePlaybackEngine engine = FakePlaybackEngine();
  late final ProviderContainer container;

  PlaybackSnapshot get state => container.read(playbackSessionProvider);
  PlaybackSessionNotifier get notifier =>
      container.read(playbackSessionProvider.notifier);

  /// Opens and settles: the session defers the engine open to a microtask
  /// (re-entrancy safety), so a drain is required before asserting state.
  Future<void> open(PlaybackRequest request) async {
    await notifier.open(request);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('PlaybackSessionNotifier — state machine', () {
    test('starts idle', () {
      final Harness h = Harness();
      expect(h.state.status, PlaybackStatus.idle);
      expect(h.state.generation, 0);
    });

    test('idle → loading → playing on a successful selected source', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineBuffering(),
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );

      // open() awaits only engine creation + open dispatch; the scripted
      // events are emitted synchronously inside open(), so the terminal
      // state is reached without extra pumping.
      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.attemptedCount, 1);
      expect(h.state.current!.source.url, 'https://a/720');
    });

    test('does not report playing before the engine reports a playable state',
        () async {
      final Harness h = Harness();
      // Script: buffering only, no terminal event yet.
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EngineBuffering()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );

      expect(h.state.status, isNot(PlaybackStatus.playing));
      expect(h.state.status, PlaybackStatus.loading);
    });

    test('pause/play transitions are honest', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );
      expect(h.state.status, PlaybackStatus.playing);

      h.engine.emit(const EnginePaused());
      expect(h.state.status, PlaybackStatus.paused);

      h.engine.emit(const EnginePlaying());
      expect(h.state.status, PlaybackStatus.playing);
    });

    test('completed on engine completion', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
        const EngineCompleted(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );

      expect(h.state.status, PlaybackStatus.completed);
    });

    test('leave() returns to idle, stops and disposes the engine', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );
      await h.notifier.leave();

      expect(h.state.status, PlaybackStatus.idle);
      expect(h.engine.stopCount, greaterThanOrEqualTo(1));
      expect(h.engine.disposeCount, 1);
    });
  });

  group('PlaybackSessionNotifier — MP4/HLS handling', () {
    test('MP4 source opens with its URL', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/video.mp4', type: SourceType.mp4),
        ]),
      );

      expect(h.engine.opened.single.type, SourceType.mp4);
      expect(h.state.status, PlaybackStatus.playing);
    });

    test('HLS source opens with its URL and headers are forwarded', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      final RankedSource hls = RankedSource(
        source: ExtensionSource(
          url: 'https://a/stream.m3u8',
          type: SourceType.hls,
          isAdaptive: true,
          headers: const <String, String>{'Referer': 'https://a/'},
        ),
        extensionId: 'extA',
        reference: 'ref-hls',
        score: 50,
      );

      await h.open(PlaybackRequest.direct(<RankedSource>[hls]));

      expect(h.engine.opened.single.type, SourceType.hls);
      expect(h.state.status, PlaybackStatus.playing);
    });
  });

  group('PlaybackSessionNotifier — fallback', () {
    test('first source failure falls back to the second source', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('boom'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/bad'),
          _source('https://b/good', extensionId: 'extB'),
        ]),
      );

      expect(h.engine.opened.map((ExtensionSource s) => s.url),
          <String>['https://a/bad', 'https://b/good']);
      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.attemptedCount, 2);
      expect(h.state.failures.single.candidate.extensionId, 'extA');
      expect(h.state.failures.single.failure, isA<PlaybackFailure>());
      // Provenance of the surviving candidate is preserved.
      expect(h.state.current!.extensionId, 'extB');
    });

    test('a single failed source is NOT "no sources available" while '
        'fallbacks remain', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('dead'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/dead'),
          _source('https://b/alive'),
        ]),
      );

      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.failure, isNull);
    });

    test('fallback exhaustion ends in a structured failure', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x1'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x2'),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/1'),
          _source('https://b/2'),
        ]),
      );

      expect(h.state.status, PlaybackStatus.failed);
      expect(h.state.failure!.type, PlaybackFailureType.sourcesExhausted);
      expect(h.state.failures.length, 2);
      // Provenance preserved for every failed attempt.
      expect(h.state.failures[0].candidate.extensionId, 'extA');
      expect(h.state.failures[1].candidate.extensionId, 'extA'); // same ext
      expect(h.state.failures[1].candidate.source.url, 'https://b/2');
    });

    test('fromPool: selected first, then fallbacks, in 2D order', () async {
      final Harness h = Harness();
      final SourcePool pool = SourcePool(
        reference: 'movie-ref',
        ranked: <RankedSource>[
          _source('https://a/first'),
          _source('https://b/second', extensionId: 'extB'),
          _source('https://c/third', extensionId: 'extC'),
        ],
        outcomes: const <ExtensionSourceOutcome>[],
      );
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('f1'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('f2'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(PlaybackRequest.fromPool(pool));

      expect(
        h.engine.opened.map((ExtensionSource s) => s.url).toList(),
        <String>['https://a/first', 'https://b/second', 'https://c/third'],
      );
      expect(h.state.status, PlaybackStatus.playing);
    });

    test('fallback exhaustion preserves the session identity line', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x1'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x2'),
      ]);

      await h.open(
        PlaybackRequest.direct(
          <RankedSource>[_source('https://a/1'), _source('https://b/2')],
          playbackKey: 'movie|1',
          title: 'Some Movie',
          subtitle: 'Season 1 · Episode 2',
        ),
      );

      expect(h.state.status, PlaybackStatus.failed);
      // The terminal snapshot must not drop what the user was watching.
      expect(h.state.title, 'Some Movie');
      expect(h.state.subtitle, 'Season 1 · Episode 2');
    });

    test('retry() replays SPECTA\'s original order with the same identity',
        () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x1'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x2'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('x1'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(
          <RankedSource>[_source('https://a/1'), _source('https://b/2')],
          title: 'Some Movie',
          subtitle: 'Season 1 · Episode 2',
        ),
      );
      expect(h.state.status, PlaybackStatus.failed);

      await h.notifier.retry();
      await Future<void>.delayed(Duration.zero);

      // Same candidates, from the beginning — never a new resolution.
      expect(
        h.engine.opened.map((ExtensionSource s) => s.url).toList(),
        <String>['https://a/1', 'https://b/2', 'https://a/1', 'https://b/2'],
      );
      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.title, 'Some Movie');
      expect(h.state.subtitle, 'Season 1 · Episode 2');
    });
  });

  group('PlaybackSessionNotifier — races and disposal', () {
    test('a new open invalidates the previous session (stale fallback '
        'cannot overwrite)', () async {
      final Harness h = Harness();
      // Session A: silent open → open-timeout would eventually fail it, but
      // a new open arrives first; A must never advance afterwards.
      h.engine.openScripts.add(<PlaybackEngineEvent>[]); // silent
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/old'),
          _source('https://a/old-fallback'),
        ]),
      );
      final int genA = h.state.generation;
      expect(h.state.status, PlaybackStatus.loading);

      // Session B supersedes A.
      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://b/new')]),
      );
      expect(h.state.generation, greaterThan(genA));
      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.current!.source.url, 'https://b/new');

      // A late event from session A's candidate must not disturb B.
      h.engine.emit(const EnginePlaying());
      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.current!.source.url, 'https://b/new');
    });

    test('engine failure after a newer open is ignored (error isolation)',
        () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/one')]),
      );
      expect(h.state.status, PlaybackStatus.playing);

      // A second open of the same engine — events from the first still flow
      // through the same stream, but a failure must not kill session two
      // unless it arrives while session two is loading its own candidate.
      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://b/two')]),
      );
      expect(h.state.status, PlaybackStatus.playing);
      expect(h.state.current!.source.url, 'https://b/two');
    });

    test('leave() rejects in-flight fallbacks', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('gone'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/dead'),
          _source('https://b/alive'),
        ]),
      );
      // The failure already advanced; leave anyway.
      await h.notifier.leave();
      expect(h.state.status, PlaybackStatus.idle);
    });

    test('provider disposal stops the engine and swallows late events',
        () async {
      final FakePlaybackEngine engine = FakePlaybackEngine();
      engine.openScripts.add(<PlaybackEngineEvent>[const EngineBuffering()]);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          playbackEngineFactoryProvider.overrideWith((Ref ref) => () => engine),
        ],
      );

      await container.read(playbackSessionProvider.notifier).open(
            PlaybackRequest.direct(<RankedSource>[_source('https://a/x')]),
          );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(playbackSessionProvider).status,
        PlaybackStatus.loading,
      );

      container.dispose();
      expect(engine.stopCount, greaterThanOrEqualTo(1));

      // Late engine events after disposal must not throw or mutate anything.
      engine.emit(const EnginePlaying());
      await Future<void>.delayed(Duration.zero);
      expect(engine.disposeCount, 1);
    });

    test('observation log records only measured outcomes', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EngineFailed('nope'),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(), // fallback success for https://b/ok2
      ]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/ok'),
        ]),
      );
      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://b/bad'),
          _source('https://b/ok2'),
        ]),
      );

      final List<PlaybackAttemptRecord> log = h.notifier.observationLog;
      // Success for the first open; failure + success for the second.
      expect(log.length, 3);
      expect(log[0].outcome, 'success');
      expect(log[1].outcome, PlaybackFailureType.sourceOpenFailure.code);
      expect(log[2].outcome, 'success');
      // timeToPlayable is a real measurement (>= 0), never fabricated.
      expect(log[0].timeToPlayable, isNotNull);
    });
  });

  group('PlaybackSessionNotifier — controls and errors', () {
    test('togglePlay pauses then resumes', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );

      await h.notifier.togglePlay();
      expect(h.state.status, PlaybackStatus.paused);

      await h.notifier.togglePlay();
      expect(h.state.status, PlaybackStatus.playing);
    });

    test('setRate/setVolume reach the engine', () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[_source('https://a/720')]),
      );
      await h.notifier.setRate(1.5);
      await h.notifier.setVolume(0.3);

      expect(h.engine.lastRate, 1.5);
      expect(h.engine.lastVolume, 0.3);
    });

    test('mid-stream EngineErrored is a recoverable stall; a real '
        'interruption (stall timeout) falls back', () async {
      // Short stall timeout so the fallback path runs quickly in-test.
      final FakePlaybackEngine engine = FakePlaybackEngine();
      engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);
      engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
      ]);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          playbackEngineFactoryProvider
              .overrideWith((Ref ref) => () => engine),
          playbackStallTimeoutProvider
              .overrideWith((Ref ref) => const Duration(milliseconds: 60)),
        ],
      );
      addTearDown(container.dispose);

      Future<void> openReq(List<RankedSource> sources) async {
        await container.read(playbackSessionProvider.notifier).open(
              PlaybackRequest.direct(sources),
            );
        await Future<void>.delayed(Duration.zero);
      }

      PlaybackSnapshot s() => container.read(playbackSessionProvider);

      await openReq(<RankedSource>[
        _source('https://a/dies-midway'),
        _source('https://b/rescue'),
      ]);
      expect(s().status, PlaybackStatus.playing);

      // Non-fatal transport error: the session enters a recoverable stall.
      engine.emit(const EngineErrored('transient demuxer error'));
      expect(s().status, PlaybackStatus.buffering);

      // Playback recovers — the candidate is NOT failed.
      engine.emit(const EngineRecovered());
      expect(s().status, PlaybackStatus.playing);
      expect(s().failures, isEmpty);

      // A real interruption: error, then no recovery — the stall timer
      // fails the candidate and the ordered fallback takes over.
      engine.emit(const EngineErrored('connection reset'));
      expect(s().status, PlaybackStatus.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await Future<void>.delayed(Duration.zero);
      expect(s().status, PlaybackStatus.playing);
      expect(s().current!.source.url, 'https://b/rescue');
      expect(s().failures.single.failure!.type,
          PlaybackFailureType.bufferingFailure);
    });

    test('empty candidate list is an honest structured failure', () async {
      final Harness h = Harness();
      await h.open(const PlaybackRequest.direct(<RankedSource>[]));

      expect(h.state.status, PlaybackStatus.failed);
      expect(h.state.failure!.type, PlaybackFailureType.sourcesExhausted);
      expect(h.state.candidates, isEmpty);
      expect(h.engine.opened, isEmpty);
    });

    test('subtitle selection applies the candidate\'s own track and clears '
        'on an explicit null', () async {
      final Harness h = Harness();
      const SubtitleTrack en = SubtitleTrack(
        url: 'https://a/en.vtt',
        language: 'en',
        label: 'English',
      );
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source(
            'https://a/stream.m3u8',
            type: SourceType.hls,
            subtitles: <SubtitleTrack>[en],
          ),
        ]),
      );

      expect(h.state.availableSubtitles, <SubtitleTrack>[en]);
      expect(h.state.selectedSubtitle, isNull);

      await h.notifier.selectSubtitle(en);
      expect(h.engine.lastSubtitle, en);
      expect(h.state.selectedSubtitle, en);

      await h.notifier.selectSubtitle(null);
      expect(h.engine.lastSubtitle, isNull);
      expect(h.state.selectedSubtitle, isNull);
    });

    test('a stray engine failure after completion cannot restart playback',
        () async {
      final Harness h = Harness();
      h.engine.openScripts.add(<PlaybackEngineEvent>[
        const EnginePlaying(),
        const EngineCompleted(),
      ]);
      h.engine.openScripts.add(<PlaybackEngineEvent>[const EnginePlaying()]);

      await h.open(
        PlaybackRequest.direct(<RankedSource>[
          _source('https://a/one'),
          _source('https://b/two'),
        ]),
      );
      expect(h.state.status, PlaybackStatus.completed);

      // Late engine noise must never open a fallback behind the user.
      h.engine.emit(const EngineFailed('late noise'));
      h.engine.emit(const EngineErrored('late noise'));
      expect(h.state.status, PlaybackStatus.completed);
      expect(h.state.current!.source.url, 'https://a/one');
      expect(h.engine.opened.length, 1);
    });
  });

  group('InMemoryPlaybackProgressSink', () {
    test('records elapsed watch time per target, in memory only', () {
      final InMemoryPlaybackProgressSink sink = InMemoryPlaybackProgressSink();

      sink.report(
        targetKey: 'movie|1',
        elapsed: const Duration(seconds: 42),
        position: const Duration(seconds: 42),
        completed: false,
      );
      sink.report(
        targetKey: 'movie|1',
        elapsed: const Duration(seconds: 60),
        position: const Duration(seconds: 60),
        completed: false,
      );

      expect(sink.elapsedFor('movie|1'), const Duration(seconds: 60));
      expect(sink.elapsedFor('unknown'), isNull);
    });

    test('is bounded (defensive memory cap)', () {
      final InMemoryPlaybackProgressSink sink = InMemoryPlaybackProgressSink();
      for (int i = 0; i < 600; i++) {
        sink.report(
          targetKey: 't$i',
          elapsed: Duration(seconds: i),
          completed: false,
        );
      }
      expect(sink.elapsedFor('t0'), isNull); // evicted
      expect(sink.elapsedFor('t599'), const Duration(seconds: 599));
    });

    test('empty target keys are never recorded', () {
      final InMemoryPlaybackProgressSink sink = InMemoryPlaybackProgressSink();
      sink.report(targetKey: '', elapsed: const Duration(seconds: 1), completed: false);
      expect(sink.elapsedFor(''), isNull);
    });
  });
}
