import 'package:flutter/material.dart';

import '../../../app/theme/specta_colors.dart';
import '../../../ui/widgets/specta_badge.dart';
import '../../../ui/widgets/specta_button.dart';
import '../../../ui/widgets/specta_focus_wrapper.dart';
import '../models/media_item.dart';

/// Hero spotlight banner showcasing featured movie or series.
class HeroSpotlightBanner extends StatelessWidget {
  const HeroSpotlightBanner({
    super.key,
    required this.item,
    this.onPlay,
    this.onMoreInfo,
    this.onPrevious,
    this.onNext,
    this.currentIndex = 0,
    this.itemCount = 5,
  });

  final MediaItem item;
  final VoidCallback? onPlay;
  final VoidCallback? onMoreInfo;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final int currentIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;

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
            // Backdrop Image (fallback to sample asset or gradient)
            Image.asset(
              'assets/images/mock_hero_banner.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) {
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
              },
            ),

            // Deep Left Gradient for typography readability
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

            // Content Overlay
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              child: Row(
                children: <Widget>[
                  // Left Content Column
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            SpectaBadge(
                              label: item.qualityBadge,
                              backgroundColor: accent.withValues(alpha: 0.18),
                              borderColor: accent.withValues(alpha: 0.5),
                              textColor: accent,
                            ),
                            const SizedBox(width: 8),
                            SpectaBadge(
                              label: item.type == MediaType.movie
                                  ? 'MOVIE'
                                  : 'SERIES',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: SpectaColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${item.genreText} · ${item.year}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: SpectaColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            SpectaFocusWrapper(
                              borderRadius: SpectaMetrics.buttonRadius,
                              onTap: onPlay,
                              child: SpectaPrimaryButton(
                                label: 'Play',
                                icon: Icons.play_arrow_rounded,
                                onPressed: onPlay,
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

            // Left Navigation Arrow
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: SpectaFocusWrapper(
                  borderRadius: 20,
                  onTap: onPrevious,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SpectaColors.surface.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: SpectaColors.outline),
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),

            // Right Navigation Arrow
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: SpectaFocusWrapper(
                  borderRadius: 20,
                  onTap: onNext,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SpectaColors.surface.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: SpectaColors.outline),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: SpectaColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Carousel Pagination Dots
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
                        boxShadow: i == currentIndex
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
