import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../app/theme/specta_theme_preset.dart';
import '../../app/theme/specta_theme_provider.dart';
import '../home/foundation_status.dart';
import '../settings/state/download_concurrency.dart';
import 'state/auto_update_state.dart';
import '../../ui/widgets/specta_card.dart';

/// SPECTA settings.
///
/// Implements the settings surfaces that exist today: appearance (theme
/// preset, persisted), downloads (concurrency, persisted), extensions
/// (auto-update, persisted), and the foundation diagnostics reader that was
/// the Phase 0 home screen. Every control is wired to real state; no control
/// pretends to configure something that does not exist.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        _AppearanceCard(),
        SizedBox(height: 16),
        _DownloadsCard(),
        SizedBox(height: 16),
        _ExtensionsCard(),
        SizedBox(height: 16),
        _DiagnosticsCard(),
        SizedBox(height: 24),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return SpectaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SpectaColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SpectaThemePreset active = ref.watch(spectaThemePresetProvider);

    return _SettingsSection(
      icon: Icons.palette_rounded,
      title: 'Appearance',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final SpectaThemePreset preset in SpectaThemePreset.values)
            _ThemePresetChip(
              preset: preset,
              selected: preset == active,
              onSelect: () async => ref
                  .read(spectaThemePresetProvider.notifier)
                  .setPreset(preset),
            ),
        ],
      ),
    );
  }
}

class _ThemePresetChip extends StatelessWidget {
  const _ThemePresetChip({
    required this.preset,
    required this.selected,
    required this.onSelect,
  });

  final SpectaThemePreset preset;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final bool isBrandDefault = preset == SpectaThemePreset.cyanTeal;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? preset.primaryAccent.withValues(alpha: 0.16)
              : SpectaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? preset.primaryAccent : SpectaColors.outline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: <Color>[
                    preset.primaryAccent,
                    preset.secondaryAccent,
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isBrandDefault ? '${preset.label} (default)' : preset.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? preset.primaryAccent : SpectaColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadsCard extends ConsumerWidget {
  const _DownloadsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int concurrency = ref.watch(downloadConcurrencyProvider);
    final DownloadConcurrencyNotifier notifier = ref.read(
      downloadConcurrencyProvider.notifier,
    );

    return _SettingsSection(
      icon: Icons.download_rounded,
      title: 'Downloads',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Concurrent downloads (max '
            '${DownloadConcurrencyNotifier.maxConcurrency})',
            style: const TextStyle(
              fontSize: 12,
              color: SpectaColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text('$concurrency',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: SpectaColors.textPrimary,
                  )),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                onPressed:
                    concurrency > DownloadConcurrencyNotifier.minConcurrency
                        ? () async => notifier.set(concurrency - 1)
                        : null,
                icon: const Icon(Icons.remove),
                tooltip: 'Fewer concurrent downloads',
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed:
                    concurrency < DownloadConcurrencyNotifier.maxConcurrency
                        ? () async => notifier.set(concurrency + 1)
                        : null,
                icon: const Icon(Icons.add),
                tooltip: 'More concurrent downloads',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExtensionsCard extends ConsumerWidget {
  const _ExtensionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool autoUpdate = ref.watch(autoUpdateExtensionsProvider);

    return _SettingsSection(
      icon: Icons.extension_rounded,
      title: 'Extensions',
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Auto-update extensions & sources',
              style: TextStyle(
                fontSize: 13,
                color: SpectaColors.textPrimary,
              ),
            ),
          ),
          Switch(
            value: autoUpdate,
            onChanged: (bool value) async => ref
                .read(autoUpdateExtensionsProvider.notifier)
                .setEnabled(value),
          ),
        ],
      ),
    );
  }
}

/// The Phase 0 foundation self-check, preserved as diagnostics.
class _DiagnosticsCard extends ConsumerWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FoundationStatusItem>> status = ref.watch(
      foundationStatusProvider,
    );

    return _SettingsSection(
      icon: Icons.monitor_heart_rounded,
      title: 'Diagnostics',
      child: status.when(
        data: (List<FoundationStatusItem> items) => Column(
          children: <Widget>[
            for (final FoundationStatusItem item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 160,
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpectaColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.value,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpectaColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (Object error, StackTrace stackTrace) => Text(
          'Unavailable: $error',
          style: const TextStyle(color: SpectaColors.failure, fontSize: 12),
        ),
      ),
    );
  }
}
