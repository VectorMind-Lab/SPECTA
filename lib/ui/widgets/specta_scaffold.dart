import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// Standard SPECTA page scaffold with consistent styling.
class SpectaScaffold extends StatelessWidget {
  const SpectaScaffold({
    required this.body,
    super.key,
    this.appBar,
    this.backgroundColor,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? SpectaColors.background,
      appBar: appBar,
      body: SafeArea(child: body),
    );
  }
}

/// SPECTA top bar with search and system status.
class SpectaTopBar extends StatelessWidget {
  const SpectaTopBar({super.key, this.showSearchBar = true});

  final bool showSearchBar;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: SpectaColors.surface,
        border: Border(
          bottom: BorderSide(color: SpectaColors.outline, width: 0.8),
        ),
      ),
      child: Row(
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.play_arrow_rounded, color: accent, size: 24),
              const SizedBox(width: 8),
              const Text(
                'SPECTA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: SpectaColors.textPrimary,
                ),
              ),
            ],
          ),
          if (showSearchBar)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: SpectaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: SpectaColors.outline),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: SpectaColors.textMuted,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search movies, series, genres...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: SpectaColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 16),
          const Icon(
            Icons.wifi_rounded,
            size: 20,
            color: SpectaColors.textMuted,
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.notifications_none_rounded,
            size: 20,
            color: SpectaColors.textMuted,
          ),
        ],
      ),
    );
  }
}
