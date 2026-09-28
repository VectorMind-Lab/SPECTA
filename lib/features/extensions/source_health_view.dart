library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../ui/widgets/specta_card.dart';
import '../../ui/widgets/specta_empty_state.dart';
import 'state/extensions_state.dart';
import 'source_health_row.dart';

/// Source Health: one row per node, showing what SPECTA has actually recorded.
///
/// ## What this screen refuses to do
///
/// It shows no streaming-site name, no path, and no source-supplied string of
/// any kind — only the node label, which SPECTA owns.
///
/// It does not compute a score. Every number maps from a fact that really
/// exists (see `SourceHealthMapping`); "No data yet" is shown INSTEAD of a
/// percentage whenever no success has ever been recorded, because a number
/// there would be invented.
///
/// It does not act. Nothing here disables, reorders or re-ranks a source.
/// Health is described, never enforced.
class SourceHealthView extends ConsumerWidget {
  const SourceHealthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExtensionsState state = ref.watch(extensionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SpectaCard(
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Source Health',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SpectaColors.textPrimary,
                  ),
                ),
              ),
              if (state.busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: () =>
                      ref.read(extensionsProvider.notifier).reload(),
                  icon: const Icon(Icons.refresh_rounded),
                  color: SpectaColors.textSecondary,
                  tooltip: 'Refresh',
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Shows what SPECTA has recorded. A source that has never been used '
            'reports no figure, because none exists yet.',
            style: TextStyle(fontSize: 11, color: SpectaColors.textMuted),
          ),
        ),
        Expanded(
          child: switch (state.status) {
            ExtensionsStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            ExtensionsStatus.failure => SpectaEmptyState(
              icon: Icons.error_outline_rounded,
              message: state.errorMessage ?? 'Source health is unavailable.',
              action: () => ref.read(extensionsProvider.notifier).reload(),
              actionLabel: 'Try again',
            ),
            ExtensionsStatus.ready when state.items.isEmpty =>
              const SpectaEmptyState(
                icon: Icons.insights_outlined,
                message: 'No sources are installed yet.',
              ),
            ExtensionsStatus.ready => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: state.items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) =>
                  SourceHealthRow(item: state.items[index]),
            ),
          },
        ),
      ],
    );
  }
}
