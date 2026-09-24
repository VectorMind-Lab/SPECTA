import 'package:flutter/material.dart';

import '../../../app/theme/specta_colors.dart';
import '../../../ui/widgets/specta_badge.dart';
import '../../../ui/widgets/specta_button.dart';
import '../../../ui/widgets/specta_focus_wrapper.dart';

/// The Home hero: the first real discovery item of the latest feed.
///
/// It renders ONLY what it is given. There is no bundled celebrity artwork and
/// no fixture model: when the item has no cover the backdrop degrades to the
/// SPECTA gradient rather than showing a stock image that is not that title.
///
/// TV-safe: both actions and the prev/next affordances are D-pad focusable.
class HeroSpotlightBanner extends StatelessWidget {
  const HeroSpotlightBanner({
    required this.title,
    required this.typeLabel,
    required this.subtitle,
    super.key,
    this.coverUrl,
    this.primaryLabel = 'Play',
    this.onPrimary,
    this.onMoreInfo,
    this.onPrevious,
    this.onNext,
    this.currentIndex = 0,
    this.itemCount = 1,
  });

  /// The real item's title.
  final String title;

  /// `MOVIE` / `SERIES` — from the item's actual media type.
  final String typeLabel;

  /// Real secondary info (e.g. `2024`). Empty means no line is shown.
  final String subtitle;

  /// The item's real cover, when the provider supplied one.
  final String? coverUrl;

  /// Primary action label (`Play`).
  final String primaryLabel;

  final VoidCallback? onPrimary;
  final VoidCallback? onMoreInfo;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final int currentIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final bool showPager = itemCount > 1;

    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: SpectaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
        border: Border.all(color: SpectaColors.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The title's own artwork, when it has one; otherwise the SPECTA
            // gradient. Never a stock image standing in for a different title.
            if (coverUrl != null)
              Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) =>
                    const _HeroGradient(),
              )
            else
              const _HeroGradient(),

            // Left-to-right scrim for typography readability.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const <double>[0.0, 0.45, 0.85, 1.0],
                  colors: <Color>[
                    SpectaColors.background.withValues(alpha: 0.96),
                    SpectaColors.background.withValues(alpha: 0.82),
                    SpectaColors.background.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SpectaBadge(
                          label: typeLabel,
                          backgroundColor: accent.withValues(alpha: 0.18),
                          borderColor: accent.withValues(alpha: 0.5),
                          textColor: accent,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: SpectaColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: SpectaColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            SpectaFocusWrapper(
                              borderRadius: SpectaMetrics.buttonRadius,
                              onTap: onPrimary,
                              child: SpectaPrimaryButton(
                                label: primaryLabel,
                                icon: Icons.play_arrow_rounded,
                                onPressed: onPrimary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SpectaFocusWrapper(
                              borderRadius: SpectaMetrics.buttonRadius,
                              onTap: onMoreInfo,
                              child: SpectaSecondaryButton(
                                label: 'More Info',
                                icon: Icons.info_outline_rounded,
                                onPressed: onMoreInfo,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),

            if (showPager) ...<Widget>[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _PagerArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: onPrevious,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _PagerArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: onNext,
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < itemCount; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == currentIndex ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == currentIndex
                              ? accent
                              : SpectaColors.outlineBright,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroGradient extends StatelessWidget {
  const _HeroGradient();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF162544),
            Color(0xFF0C1322),
          ],
        ),
      ),
    );
  }
}

class _PagerArrow extends StatelessWidget {
  const _PagerArrow({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SpectaFocusWrapper(
      borderRadius: 20,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: SpectaColors.surface.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(color: SpectaColors.outline),
        ),
        child: Icon(icon, size: 20, color: SpectaColors.textPrimary),
      ),
    );
  }
}
