import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Library view showing user's collected movies and series.
///
/// Placeholder for Phase 2+ implementation.
class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.video_library_rounded,
      message: 'Library functionality coming in Phase 2',
    );
  }
}
