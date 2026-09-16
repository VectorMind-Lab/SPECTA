import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Search view for discovering movies and series.
///
/// Placeholder for Phase 2+ implementation.
class SearchView extends StatelessWidget {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.search_rounded,
      message: 'Search functionality coming in Phase 2',
    );
  }
}
