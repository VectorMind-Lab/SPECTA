import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Query text being typed in the search surface.
///
/// The search/discovery pipeline (Phase 2B) consumes this; until it lands the
/// field is live UI but results cannot be produced yet.
class SpectaSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final NotifierProvider<SpectaSearchQueryNotifier, String>
spectaSearchQueryProvider =
    NotifierProvider<SpectaSearchQueryNotifier, String>(
      SpectaSearchQueryNotifier.new,
    );

/// Search view for discovering movies and series.
///
/// The input surface is live and holds the query in
/// [spectaSearchQueryProvider]; the search/discovery pipeline that produces
/// results from extensions is implemented in Phase 2B.
class SearchView extends ConsumerWidget {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(spectaSearchQueryProvider);
    final SpectaSearchQueryNotifier notifier = ref.read(
      spectaSearchQueryProvider.notifier,
    );

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            onChanged: notifier.setQuery,
            decoration: InputDecoration(
              hintText: 'Search movies, series...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => notifier.setQuery(''),
                    ),
            ),
          ),
        ),
        Expanded(
          child: SpectaEmptyState(
            icon: Icons.travel_explore_rounded,
            message: query.isEmpty
                ? 'Search across enabled extensions — the discovery pipeline '
                    'arrives with the Phase 2 search layer'
                : 'No results can be produced yet — the extension search '
                    'pipeline arrives with the Phase 2 search layer',
          ),
        ),
      ],
    );
  }
}
