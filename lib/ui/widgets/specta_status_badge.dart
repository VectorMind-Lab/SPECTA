import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// Status indicator badge (e.g., "All Systems Online", "Degraded").
class SpectaStatusBadge extends StatelessWidget {
  const SpectaStatusBadge({
    required this.label,
    super.key,
    this.isPositive = true,
  });

  final String label;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = isPositive
        ? SpectaColors.success
        : SpectaColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
