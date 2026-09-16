import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// Compact status or metadata badge.
class SpectaBadge extends StatelessWidget {
  const SpectaBadge({
    required this.label,
    super.key,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.fontSize = 11,
  });

  final String label;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = backgroundColor ?? SpectaColors.surfaceElevated;
    final Color fgColor = textColor ?? SpectaColors.textSecondary;
    final Color borderClr = borderColor ?? SpectaColors.outline.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderClr),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: fgColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
