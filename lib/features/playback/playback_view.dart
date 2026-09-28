import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/playback/media_kit_engine.dart';
import '../../core/playback/playback_engine.dart';
import 'playback_models.dart';
import 'playback_session_state.dart';

/// Engine → controller binding. Only one engine is active at a time; the
/// cache is pruned whenever the active engine changes (the session disposes
/// engines on leave, and stale entries would otherwise pin native resources).
VideoController? _controllerForEngine(PlaybackEngine? engine) {
  if (engine is! MediaKitPlaybackEngine) return null;
  _controllerCache.removeWhere(
    (PlaybackEngine k, VideoController _) => !identical(k, engine),
  );
  return _controllerCache.putIfAbsent(
    engine,
    () => VideoController(engine.player),
  );
}

final Map<PlaybackEngine, VideoController> _controllerCache =
    <PlaybackEngine, VideoController>{};

/// The SPECTA player surface (Phase 2E).
///
/// Phone: entered from details, pins landscape-fullscreen while playing and
/// restores the application orientation on exit; controls are touch-first
/// and auto-hide. TV: the same surface renders D-pad-focusable controls with
/// visible focus; play/pause is auto-focused so the remote always has an
/// anchor. One codebase, no separate TV player architecture.
///
/// All playback state comes from [playbackSessionProvider]; the view holds no
/// playback state of its own. Failures are rendered as honest, structured
/// states — raw engine text is never shown.
class PlaybackView extends ConsumerStatefulWidget {
  const PlaybackView({super.key});

  @override
  ConsumerState<PlaybackView> createState() => _PlaybackViewState();
}

class _PlaybackViewState extends ConsumerState<PlaybackView> {
  bool _landscapePinned = false;

  // Captured before disposal: the session notifier must be reachable from
  // dispose() without touching `ref` (which Riverpod invalidates on unmount).
  PlaybackSessionNotifier? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= ref.read(playbackSessionProvider.notifier);
  }

  @override
  void initState() {
    super.initState();
    if (!ref.read(formFactorProvider).isTelevision) {
      _landscapePinned = true;
      // Best-effort: orientation/immersion failures must never break the
      // player surface itself.
      try {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } on Object {
        // Ignore: surface remains usable in the current orientation.
      }
    }
  }

  @override
  void dispose() {
    if (_landscapePinned) {
      try {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } on Object {
        // Ignore: app shell re-applies its own layout anyway.
      }
    }
    // Leaving the surface ends the session (aborts the engine, flushes the
    // progress seam). Fire-and-forget: widget disposal must not depend on it.
    _session?.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackSnapshot snapshot = ref.watch(playbackSessionProvider);
    final bool isTv = ref.watch(formFactorProvider).isTelevision;
    final VideoController? controller = _controllerForEngine(snapshot.engine);

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (snapshot.status) {
        PlaybackStatus.idle => const _CenteredMessage(
          icon: Icons.movie_creation_outlined,
          message: 'Nothing is playing.',
        ),
        PlaybackStatus.loading || PlaybackStatus.switchingSource =>
          _LoadingBody(snapshot: snapshot, isTv: isTv),
        PlaybackStatus.playing ||
        PlaybackStatus.paused ||
        PlaybackStatus.buffering =>
          controller == null
              ? _LoadingBody(snapshot: snapshot, isTv: isTv)
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Video(
                      controller: controller,
                      controls: NoVideoControls, // SPECTA controls below
                      wakelock: true,
                    ),
                    SpectaPlayerControls(snapshot: snapshot, isTv: isTv),
                  ],
                ),
        PlaybackStatus.completed => _TerminalBody(
          snapshot: snapshot,
          isTv: isTv,
          icon: Icons.check_circle_outline_rounded,
          message: 'Playback finished.',
        ),
        PlaybackStatus.failed => _TerminalBody(
          snapshot: snapshot,
          isTv: isTv,
          icon: Icons.cloud_off_rounded,
          message:
              snapshot.failure?.message ?? 'This source could not be played.',
        ),
      },
    );
  }
}

/// Centered, honest status message.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: SpectaColors.textMuted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: SpectaColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading / switching-source body: honest status, attempt counter, cancel.
class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.snapshot, required this.isTv});

  final PlaybackSnapshot snapshot;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final bool switching = snapshot.status == PlaybackStatus.switchingSource;
    return SafeArea(
      child: Stack(
        children: <Widget>[
          const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: _BackButton(isTv: isTv),
          ),
          if (snapshot.candidates.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      snapshot.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: SpectaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      switching
                          ? 'Trying source ${snapshot.attemptedCount} of '
                                '${snapshot.candidates.length}…'
                          : 'Source ${snapshot.attemptedCount} of '
                                '${snapshot.candidates.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpectaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Terminal (completed / failed) body. Offers an honest Retry that restarts
/// the same ordered candidate list from its beginning — the pool SPECTA
/// already decided, never a new ranking.
class _TerminalBody extends ConsumerWidget {
  const _TerminalBody({
    required this.snapshot,
    required this.isTv,
    required this.icon,
    required this.message,
  });

  final PlaybackSnapshot snapshot;
  final bool isTv;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Stack(
        children: <Widget>[
          _CenteredMessage(icon: icon, message: message),
          Align(
            alignment: Alignment.topLeft,
            child: _BackButton(isTv: isTv),
          ),
          if (snapshot.candidates.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SpectaPlayerButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  autofocus: isTv,
                  // Replays SPECTA's original candidate order with the same
                  // session identity — see PlaybackSessionNotifier.retry.
                  onTap: () =>
                      ref.read(playbackSessionProvider.notifier).retry(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// D-pad/touch-safe back affordance.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.isTv});

  final bool isTv;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SpectaPlayerButton(
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          autofocus: isTv,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

/// SPECTA-styled focusable button used across the player surface.
///
/// Visible focus ring for 10-ft TV distances; tap works on touch devices.
class SpectaPlayerButton extends StatefulWidget {
  const SpectaPlayerButton({
    required this.label,
    required this.onTap,
    super.key,
    this.icon,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<SpectaPlayerButton> createState() => _SpectaPlayerButtonState();
}

class _SpectaPlayerButtonState extends State<SpectaPlayerButton> {
  bool _focused = false;

  /// Keys that mean "activate the focused control" on a remote/D-pad.
  ///
  /// A plain [GestureDetector] does not respond to any of these, so without
  /// explicit handling a TV remote could focus a control but never press it.
  static bool _isActivationKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (bool f) => setState(() => _focused = f),
      onKeyEvent: (FocusNode _, KeyEvent event) {
        if (event is KeyDownEvent && _isActivationKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? accent.withValues(alpha: 0.25)
                : SpectaColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(SpectaMetrics.pillRadius),
            border: Border.all(
              color: _focused ? accent : SpectaColors.outline,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(widget.icon, size: 18, color: SpectaColors.textPrimary),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SpectaColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SPECTA player controls overlay.
///
/// Extracted as a public widget so the D-pad/focus behavior is testable in
/// isolation with a fabricated snapshot (the live surface requires a real
/// engine, which only exists on-device).
class SpectaPlayerControls extends ConsumerStatefulWidget {
  const SpectaPlayerControls({
    required this.snapshot,
    required this.isTv,
    super.key,
  });

  final PlaybackSnapshot snapshot;
  final bool isTv;

  @override
  ConsumerState<SpectaPlayerControls> createState() =>
      _SpectaPlayerControlsState();
}

class _SpectaPlayerControlsState extends ConsumerState<SpectaPlayerControls> {
  Timer? _hideTimer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(SpectaPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New candidate or status change while hidden: surface the controls so
    // the user can see what is happening.
    if (!_visible &&
        oldWidget.snapshot.current?.source.url !=
            widget.snapshot.current?.source.url) {
      _poke();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.isTv) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  void _poke() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackSnapshot s = widget.snapshot;
    final bool buffering = s.status == PlaybackStatus.buffering;
    final bool playing = s.status == PlaybackStatus.playing;

    return Listener(
      onPointerDown: (_) => _poke(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _poke,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_visible,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xAA080B11),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC080B11),
                  ],
                  stops: <double>[0, 0.25, 0.7, 1],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: <Widget>[
                          SpectaPlayerButton(
                            label: 'Back',
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (s.title != null)
                                  Text(
                                    s.title!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: SpectaColors.textPrimary,
                                    ),
                                  ),
                                if (s.subtitle != null)
                                  Text(
                                    s.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: SpectaColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (s.availableSubtitles.isNotEmpty)
                            _SubtitleMenuButton(onPoke: _poke),
                          _SpeedMenuButton(onPoke: _poke),
                        ],
                      ),
                    ),
                  ),
                  if (buffering)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              _fmt(s.position),
                              style: const TextStyle(
                                fontSize: 11,
                                color: SpectaColors.textSecondary,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: s.duration > Duration.zero
                                      ? (s.position.inMilliseconds /
                                                s.duration.inMilliseconds)
                                            .clamp(0.0, 1.0)
                                      : 0,
                                  max: 1,
                                  onChanged: s.duration > Duration.zero
                                      ? (double v) {
                                          _poke();
                                          ref
                                              .read(
                                                playbackSessionProvider
                                                    .notifier,
                                              )
                                              .seek(
                                                Duration(
                                                  milliseconds:
                                                      (v *
                                                              s
                                                                  .duration
                                                                  .inMilliseconds)
                                                          .round(),
                                                ),
                                              );
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            Text(
                              _fmt(s.duration),
                              style: const TextStyle(
                                fontSize: 11,
                                color: SpectaColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SpectaPlayerButton(
                          label: playing ? 'Pause' : 'Play',
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          autofocus: widget.isTv,
                          onTap: () {
                            _poke();
                            ref
                                .read(playbackSessionProvider.notifier)
                                .togglePlay();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final String m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final int h = d.inHours;
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }
}

/// The "Off" entry of the subtitle menu.
///
/// [PopupMenuButton] reports a `null` item value as a CANCELLED menu and calls
/// `onCanceled` instead of `onSelected`, so the entry cannot carry `null`
/// itself: without a real sentinel "Off" is silently unselectable and the
/// viewer can never turn subtitles back off.
const Object _subtitlesOff = Object();

/// Subtitle selector over the candidate's own track list.
class _SubtitleMenuButton extends ConsumerWidget {
  const _SubtitleMenuButton({required this.onPoke});

  final VoidCallback onPoke;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot s = ref.watch(playbackSessionProvider);
    final SubtitleTrack? selected = s.selectedSubtitle;

    return PopupMenuButton<Object>(
      tooltip: 'Subtitles',
      onOpened: onPoke,
      onSelected: (Object choice) {
        onPoke();
        ref
            .read(playbackSessionProvider.notifier)
            .selectSubtitle(choice is SubtitleTrack ? choice : null);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Object>>[
        PopupMenuItem<Object>(
          value: _subtitlesOff,
          child: Text(
            'Off',
            style: TextStyle(
              fontSize: 13,
              color: SpectaColors.textPrimary,
              fontWeight: selected == null ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        for (final SubtitleTrack t in s.availableSubtitles)
          PopupMenuItem<Object>(
            value: t,
            child: Text(
              t.label ?? t.language ?? 'Track',
              style: TextStyle(
                fontSize: 13,
                color: SpectaColors.textPrimary,
                fontWeight: identical(selected, t)
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpectaColors.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(SpectaMetrics.pillRadius),
          border: Border.all(color: SpectaColors.outline),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.subtitles_rounded,
              size: 16,
              color: SpectaColors.textPrimary,
            ),
            SizedBox(width: 6),
            Text(
              'CC',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SpectaColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Playback-speed selector (0.5x–2x), wired through the session's setRate.
class _SpeedMenuButton extends ConsumerWidget {
  const _SpeedMenuButton({required this.onPoke});

  final VoidCallback onPoke;

  static const List<double> _rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// `2.0` → `2x`: a trailing `.0` is noise on a remote-driven menu.
  static String _rateLabel(double rate) {
    final String value = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toString();
    return '${value}x';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double rate = ref.watch(playbackSessionProvider).rate;

    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      onOpened: onPoke,
      onSelected: (double r) {
        onPoke();
        ref.read(playbackSessionProvider.notifier).setRate(r);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
        for (final double r in _rates)
          PopupMenuItem<double>(
            value: r,
            child: Text(
              r == 1.0 ? 'Normal' : _rateLabel(r),
              style: TextStyle(
                fontSize: 13,
                color: SpectaColors.textPrimary,
                fontWeight: r == rate ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpectaColors.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(SpectaMetrics.pillRadius),
          border: Border.all(color: SpectaColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.speed_rounded,
              size: 16,
              color: SpectaColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              rate == 1.0 ? 'Speed' : _rateLabel(rate),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SpectaColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
