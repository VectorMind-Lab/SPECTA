import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// Standard SPECTA card container with consistent styling.
class SpectaCard extends StatelessWidget {
  const SpectaCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: SpectaColors.surface,
        borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
        border: Border.all(color: SpectaColors.outline),
      ),
      child: child,
    );
  }
}
