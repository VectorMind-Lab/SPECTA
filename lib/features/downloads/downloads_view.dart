import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Downloads view for the download queue and offline library.
///
/// The download manager foundation is implemented in Phase 2G. Until then
/// this screen states its real status instead of pretending to have a queue.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.download_outlined,
      message:
          'The download queue and offline playback arrive with the Phase 2 '
          'download foundation',
    );
  }
}
