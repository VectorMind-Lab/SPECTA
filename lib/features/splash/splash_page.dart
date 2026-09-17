import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation/specta_app_shell.dart';
import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/database/database_providers.dart';
import '../../ui/widgets/specta_button.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import 'splash_state.dart';

/// The official SPECTA launch & splash experience.
///
/// Faithfully translates the supplied visual composition:
/// - Glowing neon SPECTA identity & "YOUR WORLD. YOUR CONTENT. FREE."
/// - The Man Facing the City artwork overlooking the futuristic glowing skyline
/// - "MORE SOURCES. MORE POSSIBILITIES."
/// - Bottom feature pillars (Secure, Fast, Multi-Source, Extensions, Phone & TV)
/// - Seamless animated transition to the main application shell
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
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    if (widget.autoTransition) {
      _timer = Timer(widget.transitionDelay, () {
        if (mounted) {
          _navigateToApp();
        }
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
      unawaited(
        SplashState.markSplashSeen(ref.read(settingsStoreProvider)),
      );
    } on Object {
      // Diagnostics only; the flow continues regardless.
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          return const SpectaAppShell();
        },
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
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
          // Background artwork & atmosphere
          _buildBackgroundArtwork(context, formFactor),

          // Foreground Content Overlay
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: formFactor.isLargeScreen
                      ? _buildTvSplashContent(context, accent)
                      : _buildPhoneSplashContent(context, accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundArtwork(
    BuildContext context,
    SpectaFormFactor formFactor,
  ) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Glowing radial gradient from bottom
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 0.4),
                  radius: 1.2,
                  colors: <Color>[
                    Color(0xFF0F2238),
                    Color(0xFF080B11),
                  ],
                ),
              ),
            ),
          ),

          // The Man Facing City Artwork image
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * 0.72,
            child: Opacity(
              opacity: 0.88,
              child: Image.asset(
                'assets/images/man_facing_city_pure.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),

          // Gradient overlay for seamless readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0.0, 0.35, 0.7, 1.0],
                  colors: <Color>[
                    SpectaColors.background,
                    SpectaColors.background.withValues(alpha: 0.65),
                    Colors.transparent,
                    SpectaColors.background.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSplashContent(BuildContext context, Color accent) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 20),

        // Glowing S Logo & Brand
        _buildBrandHeader(accent, isCompact: false),

        const Spacer(),

        // Brand message: "MORE SOURCES. MORE POSSIBILITIES."
        _buildTaglineCard(accent),

        const SizedBox(height: 24),

        // Action / Enter Button
        SpectaFocusWrapper(
          borderRadius: 28,
          onTap: _navigateToApp,
          child: SpectaPrimaryButton(
            label: 'Enter SPECTA',
            icon: Icons.play_arrow_rounded,
            onPressed: _navigateToApp,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTvSplashContent(BuildContext context, Color accent) {
    return Row(
      children: <Widget>[
        // Left Column: Brand & Tagline
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildBrandHeader(accent, isCompact: false, isLeftAligned: true),
              const SizedBox(height: 28),
              _buildTaglineCard(accent, isLeftAligned: true),
              const SizedBox(height: 36),
              SpectaFocusWrapper(
                autofocus: true,
                borderRadius: 28,
                onTap: _navigateToApp,
                child: SpectaPrimaryButton(
                  label: 'Start Watching',
                  icon: Icons.play_arrow_rounded,
                  onPressed: _navigateToApp,
                  fontSize: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Spacer(flex: 4),
      ],
    );
  }

  Widget _buildBrandHeader(
    Color accent, {
    required bool isCompact,
    bool isLeftAligned = false,
  }) {
    return Column(
      crossAxisAlignment: isLeftAligned
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        // Glowing App Icon
        Container(
          width: isCompact ? 64 : 84,
          height: isCompact ? 64 : 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.5),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/specta_logo_glow.png',
              fit: BoxFit.cover,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) {
                return Container(
                  color: SpectaColors.surfaceElevated,
                  child: Icon(Icons.play_arrow_rounded, size: 40, color: accent),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // SPECTA Typography
        Text(
          'SPECTA',
          style: TextStyle(
            fontSize: isCompact ? 28 : 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 4.0,
            color: SpectaColors.textPrimary,
            shadows: <Shadow>[
              Shadow(
                color: accent.withValues(alpha: 0.6),
                blurRadius: 16,
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'YOUR WORLD. YOUR CONTENT.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: accent,
          ),
        ),

        const SizedBox(height: 4),

        const Text(
          'FREE.',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.0,
            color: SpectaColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTaglineCard(Color accent, {bool isLeftAligned = false}) {
    return Column(
      crossAxisAlignment: isLeftAligned
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          'MORE SOURCES',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
            color: accent,
            shadows: <Shadow>[
              Shadow(
                color: accent.withValues(alpha: 0.4),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'MORE POSSIBILITIES',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
            color: SpectaColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
