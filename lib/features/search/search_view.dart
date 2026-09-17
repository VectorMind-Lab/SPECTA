import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_colors.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/extensions/contract/result_models.dart';
import '../../ui/widgets/specta_empty_state.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import '../details/details_state.dart';
import '../details/details_view.dart';
import 'search_state.dart';

/// Query text being typed in the search surface.
///
/// Kept as the single query provider (2A foundation); the session notifier
/// consumes it rather than a competing provider existing.
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
/// Live query field (debounced) → [SearchSessionNotifier] → Phase 2B
/// discovery pipeline → unified SPECTA results. Works with touch and D-pad:
/// the text field keeps focus while results update below, so focus is never
/// lost or trapped after a search completes.
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  Timer? _debounce;
  String _lastSubmitted = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final String query = _controller.text;
    ref.read(spectaSearchQueryProvider.notifier).setQuery(query);

    // Rapid query changes collapse into one round per 400 ms quiet period;
    // the session notifier's generation guard rejects any round that still
    // lands out of order.
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      ref.read(searchSessionProvider.notifier).reset();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (query.trim() == _lastSubmitted) return;
      _lastSubmitted = query.trim();
      ref.read(searchSessionProvider.notifier).submit(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SearchState state = ref.watch(searchSessionProvider);
    final String query = ref.watch(spectaSearchQueryProvider);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _controller,
            focusNode: _fieldFocus,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search movies, series...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        ref
                            .read(searchSessionProvider.notifier)
                            .reset();
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: switch (state.status) {
            SearchStatus.idle => const SpectaEmptyState(
                icon: Icons.travel_explore_rounded,
                message: 'Search across your enabled extensions',
              ),
            SearchStatus.loading => const Center(
                child: CircularProgressIndicator(),
              ),
            SearchStatus.results ||
            SearchStatus.partialFailure =>
              _ResultList(state: state),
            SearchStatus.empty => const SpectaEmptyState(
                icon: Icons.search_off_rounded,
                message: 'No results found',
              ),
            SearchStatus.allFailed => const SpectaEmptyState(
                icon: Icons.cloud_off_rounded,
                message:
                    'Search failed — your extensions could not be reached. '
                    'Check your connection and try again.',
              ),
            SearchStatus.noExtensions => const SpectaEmptyState(
                icon: Icons.extension_off_rounded,
                message:
                    'No search-capable extensions are installed and enabled. '
                    'Install one from the Extensions screen.',
              ),
          },
        ),
      ],
    );
  }
}

/// Unified discovery results with an honest partial-failure notice.
class _ResultList extends StatelessWidget {
  const _ResultList({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return Column(
      children: <Widget>[
        if (state.status == SearchStatus.partialFailure)
          Material(
            color: SpectaColors.warning.withValues(alpha: 0.12),
            child: ListTile(
              dense: true,
              leading: Icon(Icons.warning_amber_rounded,
                  size: 18, color: SpectaColors.warning),
              title: Text(
                'Some extensions failed to respond; showing available '
                'results',
                style: TextStyle(fontSize: 12, color: SpectaColors.textSecondary),
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: state.items.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              return _DiscoveryCard(item: state.items[index], accent: accent);
            },
          ),
        ),
      ],
    );
  }
}

/// One unified discovery item.
class _DiscoveryCard extends ConsumerWidget {
  const _DiscoveryCard({required this.item, required this.accent});

  final DiscoveryItem item;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isLarge = MediaQuery.sizeOf(context).width >= SpectaBreakpoints.television;
    final double posterSize = isLarge ? 84 : 64;

    return SpectaFocusWrapper(
      borderRadius: SpectaMetrics.cardRadius,
      onTap: () {
        // Phase 2C: open the canonical details surface for this item. The
        // details session (not the card) owns the metadata request, so a
        // stale card tap can never render fabricated data.
        ref.read(detailsSessionProvider.notifier).open(item);
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (BuildContext _) => const DetailsView()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SpectaColors.surface,
          borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
          border: Border.all(color: SpectaColors.outline),
        ),
        child: Row(
          children: <Widget>[
            // Poster / fallback
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: posterSize,
                height: posterSize * 1.5,
                color: SpectaColors.surfaceElevated,
                child: item.cover != null
                    ? Image.network(
                        item.cover!,
                        fit: BoxFit.cover,
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) =>
                            _fallback(accent),
                      )
                    : _fallback(accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SpectaColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      item.type == MediaType.movie ? 'Movie' : 'Series',
                      if (item.year != null) '${item.year}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SpectaColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Provenance: how many extensions discovered this work.
                  Text(
                    item.isCrossExtension
                        ? 'Found on ${item.references.length} extensions'
                        : 'Found on 1 extension',
                    style: TextStyle(
                      fontSize: 11,
                      color: accent.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              item.type == MediaType.movie
                  ? Icons.movie_rounded
                  : Icons.tv_rounded,
              size: 20,
              color: SpectaColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(Color accent) {
    return Icon(
      item.type == MediaType.movie ? Icons.movie_rounded : Icons.tv_rounded,
      size: 28,
      color: accent.withValues(alpha: 0.35),
    );
  }
}
