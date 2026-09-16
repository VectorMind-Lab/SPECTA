import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// Primary SPECTA button with accent background.
class SpectaPrimaryButton extends StatelessWidget {
  const SpectaPrimaryButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: SpectaColors.background,
        padding: padding,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: fontSize + 4),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary SPECTA button with outline style.
class SpectaSecondaryButton extends StatelessWidget {
  const SpectaSecondaryButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: SpectaColors.textPrimary,
        side: const BorderSide(color: SpectaColors.outline),
        padding: padding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpectaMetrics.buttonRadius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: fontSize + 4),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
