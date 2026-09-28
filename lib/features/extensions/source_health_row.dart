import 'package:flutter/material.dart';

import '../../app/theme/specta_colors.dart';
import '../../core/extensions/identity/extension_health.dart';
import '../../core/extensions/manager/extension_lifecycle_service.dart';
import '../../ui/widgets/specta_card.dart';

/// One node's recorded health, by label only.
///
/// Public because it lives in its own file; it is an implementation detail of
/// [SourceHealthView] and is not part of any public surface.
class SourceHealthRow extends StatelessWidget {
  const SourceHealthRow({required this.item, super.key});

  final ManagedExtension item;

  @override
  Widget build(BuildContext context) {
    final SourceHealthDisplay display = item.healthDisplay;
    return SpectaCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.nodeLabel ?? 'Node',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SpectaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  SourceHealthMapping.describe(item.healthState),
                  style: const TextStyle(
                    fontSize: 12,
                    color: SpectaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detailLine(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpectaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            display.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _colorFor(display),
            ),
          ),
        ],
      ),
    );
  }

  /// Version, state and the real activity facts. No site name, no path.
  String _detailLine() {
    final int failures = item.health.recentFailureCount;
    return <String>[
      'v${item.version}',
      item.enabled ? 'On' : 'Off',
      failures == 0
          ? 'no recent failures'
          : '$failures recent failure${failures == 1 ? '' : 's'}',
      if (item.lastSuccessAt != null)
        'last worked ${_formatDate(item.lastSuccessAt!)}',
    ].join('  ·  ');
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static Color _colorFor(SourceHealthDisplay display) => switch (display) {
        SourceHealthDisplay.working => SpectaColors.success,
        SourceHealthDisplay.degraded => SpectaColors.warning,
        SourceHealthDisplay.unavailable => SpectaColors.warning,
        SourceHealthDisplay.off => SpectaColors.textMuted,
        SourceHealthDisplay.unsupported => SpectaColors.failure,
        // "No data yet" is a statement about missing data, not a bad score, so
        // it is never drawn in the failure colour.
        SourceHealthDisplay.noDataYet => SpectaColors.textMuted,
      };
}
