import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Extensions management view.
///
/// Placeholder for Phase 2+ implementation.
/// Will show installed extensions, catalogue, and extension settings.
class ExtensionsView extends StatelessWidget {
  const ExtensionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.extension_rounded,
      message: 'Extensions UI coming in Phase 2',
    );
  }
}
