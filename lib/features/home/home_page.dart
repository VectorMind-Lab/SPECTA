import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform/form_factor.dart';
import '../../app/theme/specta_theme.dart';
import '../settings/state/download_concurrency.dart';
import 'foundation_status.dart';

/// Phase 0 foundation screen — deliberately temporary.
///
/// SPECTA has no content pipeline yet, so this screen reports the state of the
/// foundation instead of pretending to be a working catalogue. Every value it
/// shows is read back from the layer it describes. Real discovery/recently
/// added/library surfaces replace it once those phases exist.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SpectaFormFactor formFactor = ref.watch(formFactorProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: formFactor.isLargeScreen ? 920 : 640,
            ),
            child: ListView(
              padding: const EdgeInsets.all(SpectaMetrics.gutter),
              children: const <Widget>[
                _Header(),
                SizedBox(height: 24),
                _FoundationStatusCard(),
                SizedBox(height: 16),
                _DownloadConcurrencyCard(),
                SizedBox(height: 16),
                _RoadmapCard(),
                SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SpectaFormFactor formFactor = ref.watch(formFactorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('SPECTA', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Movies and series. Login-free, ad-free, extension-based.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            const _Chip(label: 'Phase 0 — foundation'),
            _Chip(label: 'Layout: ${formFactor.name}'),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: SpectaColors.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _FoundationStatusCard extends ConsumerWidget {
  const _FoundationStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FoundationStatusItem>> status = ref.watch(
      foundationStatusProvider,
    );

    return _SectionCard(
      title: 'Foundation self-check',
      subtitle: 'Read back from SQLite and the storage layer.',
      child: status.when(
        data: (List<FoundationStatusItem> items) => Column(
          children: <Widget>[
            for (final FoundationStatusItem item in items) _StatusRow(item),
          ],
        ),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (Object error, StackTrace stackTrace) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Unavailable: $error',
            style: const TextStyle(color: SpectaColors.failure),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.item);

  final FoundationStatusItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Text(
              item.label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              item.value,
              style: const TextStyle(color: SpectaColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadConcurrencyCard extends ConsumerWidget {
  const _DownloadConcurrencyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int concurrency = ref.watch(downloadConcurrencyProvider);
    final DownloadConcurrencyNotifier notifier = ref.read(
      downloadConcurrencyProvider.notifier,
    );

    return _SectionCard(
      title: 'Downloads',
      subtitle:
          'Concurrent downloads are capped at '
          '${DownloadConcurrencyNotifier.maxConcurrency}.',
      child: Row(
        children: <Widget>[
          Text('$concurrency', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 16),
          IconButton.filledTonal(
            onPressed: concurrency > DownloadConcurrencyNotifier.minConcurrency
                ? () async => notifier.set(concurrency - 1)
                : null,
            icon: const Icon(Icons.remove),
            tooltip: 'Fewer concurrent downloads',
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: concurrency < DownloadConcurrencyNotifier.maxConcurrency
                ? () async => notifier.set(concurrency + 1)
                : null,
            icon: const Icon(Icons.add),
            tooltip: 'More concurrent downloads',
          ),
        ],
      ),
    );
  }
}

class _RoadmapCard extends StatelessWidget {
  const _RoadmapCard();

  /// Stated plainly so the foundation is never mistaken for the product.
  static const List<String> _pending = <String>[
    'Extension runtime and sandbox',
    'Official extension catalogue and signature verification',
    'Metadata manager',
    'Source resolution, validation, ranking and selection',
    'MediaKit player surface',
    'Download manager and offline playback',
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Not implemented yet',
      subtitle: 'Phase 0 builds the foundation only.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String item in _pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '•  $item',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpectaMetrics.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
