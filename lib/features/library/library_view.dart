import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Library view for saved/favorite content and watch history.
///
/// The library/progress persistence layer is implemented in Phase 2F
/// (library / history / watch progress). Until then this screen states its
/// real status instead of pretending to have content.
class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.video_library_outlined,
      message:
          'Your library, watchlist and watch history arrive with the Phase 2 '
          'library & progress layer',
    );
  }
}
