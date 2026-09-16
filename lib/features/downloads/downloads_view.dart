import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Downloads view showing offline content.
///
/// Placeholder for Phase 2+ implementation.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.download_rounded,
      message: 'Downloads functionality coming in Phase 2',
    );
  }
}
