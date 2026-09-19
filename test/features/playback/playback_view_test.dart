// Widget tests for the SPECTA player surface (Phase 2E).
//
// These cover what the session-level tests cannot: the RENDERED control
// surface — the touch overlay (auto-hide and poke), D-pad focus feedback on
// the focusable control primitive, and the subtitle/speed menus wired to the
// playback session.
//
// The real engine needs native code, so a deterministic fake engine drives the
// session here; only the engine seam is faked, never the widgets under test.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/core/extensions/contract/extension_source.dart';
import 'package:specta/core/playback/playback_engine.dart';
import 'package:specta/core/sources/source_pool.dart';
import 'package:specta/features/playback/playback_models.dart';
import 'package:specta/features/playback/playback_session_state.dart';
import 'package:specta/features/playback/playback_view.dart';

/// Minimal deterministic engine: every open reaches a playable state, and the
/// control calls are recorded so the menu wiring can be asserted.
class _FakeEngine implements PlaybackEngine {
  final StreamController<PlaybackEngineEvent> _events =
      StreamController<PlaybackEngineEvent>.broadcast(sync: true);

  int pauseCalls = 0;
  int playCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Duration? lastSeek;
  double? lastRate;
  SubtitleTrack? lastSubtitle;

  @override
  Stream<PlaybackEngineEvent> get events => _events.stream;

  @override
  SubtitleTrack? get currentSubtitle => lastSubtitle;

  @override
  Future<void> open(ExtensionSource source) async {
    // A real engine reports playing, then advances the position — the
    // session's honest "playable" signal requires the position tick.
    _events.add(const EnginePlaying());
    _events.add(
      const EngineProgress(
        position: Duration(seconds: 1),
        duration: Duration(minutes: 2),
        buffered: Duration(seconds: 8),
        rate: 1.0,
        volume: 1.0,
      ),
    );
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _events.add(const EnginePaused());
  }

  @override
  Future<void> play() async {
    playCalls++;
    _events.add(const EnginePlaying());
  }

  @override
  Future<void> seek(Duration position) async => lastSeek = position;

  @override
  Future<void> setRate(double rate) async {
    lastRate = rate;
    // MediaKit's rate stream reports the applied rate back.
    _events.add(EngineRateChanged(rate));
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSubtitle(SubtitleTrack? subtitle) async =>
      lastSubtitle = subtitle;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {
    // Deliberately does not close the event controller: the playback session
    // awaits engine disposal in leave(), and closing a *sync* broadcast
    // controller makes that await never complete under the widget-test
    // fake-async zone. The real (async) engine closes its own stream and is
    // exercised on device.
    disposeCalls++;
  }
}

const SubtitleTrack _english = SubtitleTrack(
  url: 'https://a/en.vtt',
  language: 'en',
  label: 'English',
);

RankedSource _hlsSource({List<SubtitleTrack>? subtitles}) => RankedSource(
      source: ExtensionSource(
        url: 'https://a/stream.m3u8',
        type: SourceType.hls,
        isAdaptive: true,
        subtitles: subtitles,
      ),
      extensionId: 'extA',
      reference: 'ref-hls',
      score: 50,
    );

/// Renders only the controls overlay, driven by the live session state the way
/// [PlaybackView] drives it (the overlay takes its snapshot from its parent).
class _ControlsHost extends ConsumerWidget {
  const _ControlsHost({required this.isTv});

  final bool isTv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot snapshot = ref.watch(playbackSessionProvider);
    return SpectaPlayerControls(snapshot: snapshot, isTv: isTv);
  }
}

final class _Harness {
  _Harness();

  bool _disposed = false;

  final _FakeEngine engine = _FakeEngine();
  late final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      playbackEngineFactoryProvider.overrideWith((Ref ref) => () => engine),
    ],
  );

  /// Synchronous teardown: disposing the container runs the session's
  /// disposal hook, which cancels its timers. (The session's own async
  /// `leave()` is deliberately not awaited here — it must not be a
  /// prerequisite for a widget test ending.)
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  /// Starts a playing session with an episode identity and one subtitle track.
  Future<void> startPlaying(WidgetTester tester, {required bool isTv}) async {
    await container.read(playbackSessionProvider.notifier).open(
          PlaybackRequest.direct(
            <RankedSource>[_hlsSource(subtitles: <SubtitleTrack>[_english])],
            playbackKey: 'movie|1',
            title: 'Some Movie',
            subtitle: 'Season 1 · Episode 2',
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: _ControlsHost(isTv: isTv)),
        ),
      ),
    );
    // Drain the deferred engine open + emit the resulting frame.
    await tester.pump();
    await tester.pump();
  }

  /// Unmounts the overlay (cancels the auto-hide timer) and disposes the
  /// session (cancels its timers), keeping the test free of pending timers.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
    await tester.pump();
  }
}

/// The overlay's visibility is expressed as an [AnimatedOpacity] whose child is
/// the gradient/controls layer: 1 = shown, 0 = hidden (and not hit-testable).
double _overlayOpacity(WidgetTester tester) {
  final AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
    find.ancestor(
      of: find.text('Some Movie'),
      matching: find.byType(AnimatedOpacity),
    ),
  );
  return opacity.opacity;
}

bool _overlayIgnoresPointers(WidgetTester tester) {
  final IgnorePointer ignore = tester.widget<IgnorePointer>(
    find
        .ancestor(
          of: find.text('Some Movie'),
          matching: find.byType(IgnorePointer),
        )
        .first,
  );
  return ignore.ignoring;
}

/// Whether [label]'s button currently paints the focused 2px accent ring.
bool _hasFocusRing(WidgetTester tester, String label) {
  final Iterable<AnimatedContainer> containers =
      tester.widgetList<AnimatedContainer>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return containers.any((AnimatedContainer c) {
    final Border? border = (c.decoration as BoxDecoration?)?.border as Border?;
    return border != null && border.top.width == 2;
  });
}

PlaybackStatus _status(_Harness h) =>
    h.container.read(playbackSessionProvider).status;

void main() {
  group('SpectaPlayerControls — touch overlay', () {
    testWidgets('renders the playing candidate with honest controls',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);

      expect(_status(h), PlaybackStatus.playing);
      expect(find.text('Some Movie'), findsOneWidget);
      expect(find.text('Season 1 · Episode 2'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      // Subtitle/speed affordances come from the candidate's own surface.
      expect(find.text('CC'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      // Shown immediately (phone) and hit-testable.
      expect(_overlayOpacity(tester), 1);
      expect(_overlayIgnoresPointers(tester), isFalse);

      await h.finish(tester);
    });

    testWidgets('play/pause tap drives the session, and the label follows it',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(h.engine.pauseCalls, 1);
      expect(_status(h), PlaybackStatus.paused);
      expect(find.text('Play'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(h.engine.playCalls, 1);
      expect(_status(h), PlaybackStatus.playing);
      expect(find.text('Pause'), findsOneWidget);

      await h.finish(tester);
    });

    testWidgets('seeking through the slider reaches the engine',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);

      // Drag the thumb to the middle of a 2-minute track.
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pump();

      expect(h.engine.lastSeek, isNotNull);
      expect(h.engine.lastSeek!.inSeconds, greaterThan(1));

      await h.finish(tester);
    });

    testWidgets('auto-hides after 4s of inactivity and a touch pokes it back',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);
      expect(_overlayOpacity(tester), 1);

      // Idle for longer than the hide delay.
      await tester.pump(const Duration(seconds: 5));
      expect(_overlayOpacity(tester), 0);
      expect(_overlayIgnoresPointers(tester), isTrue);

      // A touch anywhere on the surface must bring the controls back.
      await tester.tap(find.byType(SpectaPlayerControls));
      await tester.pump();
      expect(_overlayOpacity(tester), 1);
      expect(_overlayIgnoresPointers(tester), isFalse);

      await h.finish(tester);
    });

    testWidgets('TV never auto-hides the controls', (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: true);

      await tester.pump(const Duration(seconds: 30));
      expect(_overlayOpacity(tester), 1);
      expect(_overlayIgnoresPointers(tester), isFalse);

      await h.finish(tester);
    });
  });

  group('SpectaPlayerControls — D-pad / focus', () {
    testWidgets('the TV surface auto-focuses its primary action',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: true);

      // The play/pause control is the remote's anchor...
      final SpectaPlayerButton primary = tester.widget<SpectaPlayerButton>(
        find.ancestor(
          of: find.text('Pause'),
          matching: find.byType(SpectaPlayerButton),
        ),
      );
      expect(primary.autofocus, isTrue);
      // ...and that focus is actually drawn as a visible ring.
      expect(_hasFocusRing(tester, 'Pause'), isTrue);
      expect(_hasFocusRing(tester, 'Back'), isFalse);

      await h.finish(tester);
    });

    testWidgets('focus moves with arrow keys and the ring follows',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: true);
      expect(_hasFocusRing(tester, 'Pause'), isTrue);

      // Move focus back to the Back control: the ring must follow the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(_hasFocusRing(tester, 'Back'), isTrue);
      expect(_hasFocusRing(tester, 'Pause'), isFalse);

      await h.finish(tester);
    });

    testWidgets('a focused button is activatable from the D-pad',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: true);
      expect(_hasFocusRing(tester, 'Pause'), isTrue);

      // Enter/Select on the focused control toggles playback through the
      // session — the D-pad path the remote actually uses.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(h.engine.pauseCalls, 1);
      expect(_status(h), PlaybackStatus.paused);

      await h.finish(tester);
    });
  });

  group('SpectaPlayerButton — focus feedback', () {
    testWidgets('paints the accent ring only while focused',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SpectaPlayerButton(
                  label: 'First',
                  autofocus: true,
                  onTap: () {},
                ),
                SpectaPlayerButton(label: 'Second', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_hasFocusRing(tester, 'First'), isTrue);
      expect(_hasFocusRing(tester, 'Second'), isFalse);

      // Arrow-key traversal moves the ring to the next focusable control.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_hasFocusRing(tester, 'First'), isFalse);
      expect(_hasFocusRing(tester, 'Second'), isTrue);

      // Tapping (non-autofocus) still activates it — focus is not required.
      await tester.tap(find.text('Second'));
      await tester.pump();
    });
  });

  group('SpectaPlayerControls — subtitle menu', () {
    testWidgets('lists the candidate tracks and applies the selection',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);
      expect(
        h.container.read(playbackSessionProvider).selectedSubtitle,
        isNull,
      );

      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();

      expect(find.text('Off'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(h.engine.lastSubtitle, _english);
      expect(
        h.container.read(playbackSessionProvider).selectedSubtitle,
        _english,
      );

      await h.finish(tester);
    });

    testWidgets('turning subtitles off clears the selection',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);

      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        h.container.read(playbackSessionProvider).selectedSubtitle,
        _english,
      );

      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      expect(h.engine.lastSubtitle, isNull);
      expect(
        h.container.read(playbackSessionProvider).selectedSubtitle,
        isNull,
      );

      await h.finish(tester);
    });
  });

  group('SpectaPlayerControls — speed menu', () {
    testWidgets('offers the supported rates and applies the choice',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      addTearDown(h.dispose);

      await h.startPlaying(tester, isTv: false);
      expect(find.text('Speed'), findsOneWidget);

      await tester.tap(find.text('Speed'));
      await tester.pumpAndSettle();

      // Normal is the label for 1.0x; the rest are shown as multipliers.
      expect(find.text('Normal'), findsOneWidget);
      for (final String rate in <String>['0.5x', '1.5x', '2x']) {
        expect(find.text(rate), findsOneWidget);
      }

      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      expect(h.engine.lastRate, 1.5);
      // The engine reports the applied rate back, so the control reflects it.
      expect(find.text('1.5x'), findsOneWidget);

      await h.finish(tester);
    });
  });
}
