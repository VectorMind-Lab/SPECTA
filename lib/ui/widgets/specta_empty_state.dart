import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';

/// Empty state placeholder for lists/sections with no content.
class SpectaEmptyState extends StatelessWidget {
  const SpectaEmptyState({
    required this.message,
    super.key,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.actionLabel,
  });

  final String message;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 64,
                color: SpectaColors.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: SpectaColors.textMuted,
                ),
              ),
              if (action != null && actionLabel != null) ...<Widget>[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: action,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: SpectaColors.background,
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
