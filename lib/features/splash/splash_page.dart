import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation/specta_app_shell.dart';
import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/database/database_providers.dart';
import 'splash_state.dart';

/// The SPECTA launch experience.
///
/// A single, centred brand reveal: the app mark settles into place, a highlight
/// sweeps across it, and the wordmark follows. Nothing else is on screen — the
/// previous version layered a stock "man facing the city" illustration, a
/// feature-pillar block and an "Enter SPECTA" button over the brand, which made
/// the first frame busy and the brand itself quiet. The launch frame is now
/// only the brand, on SPECTA's own canvas colour.
///
/// It also hands off seamlessly to the NATIVE launch window, which draws the
/// same mark on the same colour before Flutter's first frame
/// (`android/app/src/main/res/drawable/launch_background.xml`), so there is one
/// continuous image rather than a flash followed by a different screen.
///
/// The splash still auto-advances ([SplashState.autoTransitionDelay]) and still
/// records that the flow completed. Both are unchanged behaviour.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({
    super.key,
    this.autoTransition = true,
    this.transitionDelay = SplashState.autoTransitionDelay,
  });

  final bool autoTransition;
  final Duration transitionDelay;

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  /// Long enough to read as deliberate, short enough that the user is not
  /// waiting on a choreography. The auto-transition timer below is always
  /// longer than this, so the reveal finishes before the hand-off begins.
  static const Duration _revealDuration = Duration(milliseconds: 2100);

  late final AnimationController _controller;

  /// The mark settling in.
  late final Animation<double> _markOpacity;
  late final Animation<double> _markScale;
  late final Animation<double> _glow;

  /// The highlight travelling across the mark, as a 0..1 progress value that
  /// the shader maps onto its own coordinate space.
  late final Animation<double> _sweep;

  /// The wordmark and tagline, which follow the mark.
  late final Animation<double> _wordOpacity;
  late final Animation<double> _wordOffset;
  late final Animation<double> _taglineOpacity;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _revealDuration);

    _markOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.38, curve: Curves.easeOut),
    );
    _markScale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.52, curve: Curves.easeOutCubic),
      ),
    );
    _glow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.7, curve: Curves.easeOut),
    );
    _sweep = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.62, curve: Curves.easeInOut),
    );
    _wordOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.34, 0.72, curve: Curves.easeOut),
    );
    _wordOffset = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.34, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
    );

    _controller.forward();

    if (widget.autoTransition) {
      _timer = Timer(widget.transitionDelay, () {
        if (mounted) _navigateToApp();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _navigateToApp() {
    // Record that the launch flow completed (best-effort; a storage failure
    // must never trap the user on the splash).
    try {
      unawaited(SplashState.markSplashSeen(ref.read(settingsStoreProvider)));
    } on Object {
      // Diagnostics only; the flow continues regardless.
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => const SpectaAppShell(),
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) => FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 420),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SpectaFormFactor formFactor = ref.watch(formFactorProvider);
    final Color accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: SpectaColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildAmbientGlow(accent),
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildMark(accent, formFactor),
                      SizedBox(height: formFactor.isLargeScreen ? 36 : 28),
                      _buildWordmark(formFactor),
                      SizedBox(height: formFactor.isLargeScreen ? 14 : 10),
                      _buildTagline(accent),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A soft halo behind the whole composition, so the mark is not floating on
  /// a flat field. Fixed and subtle: the reveal carries the motion, not this.
  Widget _buildAmbientGlow(Color accent) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 0.9,
            colors: <Color>[
              accent.withValues(alpha: 0.10),
              SpectaColors.background,
            ],
          ),
        ),
      ),
    );
  }

  /// The app mark: SPECTA's own icon with a highlight sweeping across it.
  Widget _buildMark(Color accent, SpectaFormFactor formFactor) {
    final double edge = formFactor.isLargeScreen ? 168 : 124;
    final double radius = edge * 0.24;

    return Opacity(
      opacity: _markOpacity.value,
      child: Transform.scale(
        scale: _markScale.value,
        child: Container(
          width: edge,
          height: edge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.34 * _glow.value),
                blurRadius: 52,
                spreadRadius: 6,
              ),
            ],
          ),
          child: ShaderMask(
            // srcATop paints the highlight only where the icon is already
            // opaque, so the sweep follows the mark's own rounded silhouette
            // instead of drawing a bright band across its transparent corners.
            blendMode: BlendMode.srcATop,
            shaderCallback: (Rect bounds) {
              // Travels from fully off the left edge to fully off the right.
              final double travel = -0.7 + (_sweep.value * 1.9);
              return LinearGradient(
                begin: Alignment(travel - 0.35, -1),
                end: Alignment(travel + 0.35, 1),
                colors: <Color>[
                  const Color(0x00FFFFFF),
                  Colors.white.withValues(alpha: 0.42),
                  const Color(0x00FFFFFF),
                ],
                stops: const <double>[0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              // Never a fallback glyph standing in for the brand: if the asset
              // is missing the reveal simply shows the wordmark alone.
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordmark(SpectaFormFactor formFactor) {
    return Opacity(
      opacity: _wordOpacity.value,
      child: Transform.translate(
        offset: Offset(0, _wordOffset.value),
        child: Text(
          'SPECTA',
          style: TextStyle(
            fontSize: formFactor.isLargeScreen ? 46 : 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
            height: 1.0,
            color: SpectaColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildTagline(Color accent) {
    return Opacity(
      opacity: _taglineOpacity.value,
      child: Column(
        children: <Widget>[
          Text(
            'YOUR WORLD. YOUR CONTENT.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.2,
              color: accent.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'FREE.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 4.0,
              color: SpectaColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
