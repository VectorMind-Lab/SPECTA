import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/specta_colors.dart';
import '../../app/theme/specta_theme_preset.dart';
import '../../app/theme/specta_theme_provider.dart';
import '../home/foundation_status.dart';
import '../settings/state/download_concurrency.dart';
import 'state/auto_update_state.dart';
import '../../ui/widgets/specta_card.dart';

/// The exact attribution sentence TMDB's terms of use require, reproduced
/// without alteration:
/// "You shall place the following notice prominently on your application..."
///
/// Public so the settings test can assert the required wording has not drifted,
/// since getting this string wrong is exactly the kind of silent regression that
/// no other test would catch.
const String tmdbAttributionNotice =
    'This product uses the TMDB API but is not endorsed or certified by TMDB.';

/// The address TMDB asks to be used when linking back to their site.
const String tmdbHomepageUrl = 'https://www.themoviedb.org';

/// SPECTA settings.
///
/// Implements the settings surfaces that exist today: appearance (theme
/// preset, persisted), downloads (concurrency, persisted), extensions
/// (auto-update, persisted), the foundation diagnostics reader that was the
/// Phase 0 home screen, and About & Credits (attribution for the third-party
/// services SPECTA depends on). Every control is wired to real state; no
/// control pretends to configure something that does not exist.
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
        SizedBox(height: 16),
        _AboutCreditsCard(),
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
                  colors: <Color>[preset.primaryAccent, preset.secondaryAccent],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isBrandDefault ? '${preset.label} (default)' : preset.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? preset.primaryAccent
                    : SpectaColors.textSecondary,
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
    final bool isDefault =
        concurrency == DownloadConcurrencyNotifier.defaultConcurrency;

    return _SettingsSection(
      icon: Icons.download_rounded,
      title: 'Downloads',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Concurrent downloads (max '
            '${DownloadConcurrencyNotifier.maxConcurrency})',
            style: const TextStyle(fontSize: 12, color: SpectaColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                '$concurrency',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SpectaColors.textPrimary,
                ),
              ),
              // E1/E3: show the CURRENT value's status, not just the number. The
              // "(default)" wording matches the theme chips so the two cards use
              // one consistent term. Only a real value is ever shown.
              if (isDefault)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    '(default)',
                    style: TextStyle(
                      fontSize: 12,
                      color: SpectaColors.textSecondary,
                    ),
                  ),
                ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
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
          // E1 + E2: this switch changes what SPECTA does on its own, so it
          // states its current value AND the consequence, in one plain line.
          // It reports only real state — no promise about a specific version.
          const SizedBox(height: 6),
          Text(
            autoUpdate
                ? 'On — SPECTA checks for newer versions of your extensions. '
                      'You choose what to install.'
                : 'Off — extensions stay on the version you installed.',
            style: const TextStyle(fontSize: 12, color: SpectaColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Attribution for the third-party services SPECTA uses.
///
/// ## Why this is a real, visible section rather than a buried link
///
/// TMDB's terms of use are specific, and the placement here is chosen to meet
/// them exactly rather than to hide the credit:
///
/// * *"You shall use the TMDB logo to identify your use of the TMDB APIs."*
///   The logo is the approved "Primary short (blue)" mark, fetched unmodified
///   from TMDB's own logos & attribution page by `tool/render_tmdb_logo.py`.
///   It is never recoloured, stretched, flipped or rotated.
/// * *"You shall place the following notice prominently on your
///   application..."* — the required sentence appears verbatim below.
/// * *"...the attribution must be within your application's 'About' or
///   'Credits' type section."* — which is exactly where this is, and why the
///   notice is a permanently visible line rather than something collapsed
///   behind a disclosure.
/// * *"Any use of the TMDB logo... shall be less prominent than the logo or
///   mark that primarily describes the application."* — SPECTA's own mark sits
///   above it and the logo is rendered small.
///
/// The API itself is described honestly as **metadata only**: TMDB does not
/// supply playback sources, and nothing here should imply that it does.
class _AboutCreditsCard extends StatelessWidget {
  const _AboutCreditsCard();

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return _SettingsSection(
      icon: Icons.info_outline_rounded,
      title: 'About & Credits',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 40,
                  height: 40,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) => const SizedBox(width: 40, height: 40),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'SPECTA',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.4,
                        color: SpectaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A login-free player for your own sources.',
                      style: TextStyle(
                        fontSize: 11,
                        color: SpectaColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: SpectaColors.outline, height: 1),
          const SizedBox(height: 14),

          const Text(
            'METADATA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: SpectaColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),

          // The approved mark, at its native aspect ratio. Width-constrained
          // only, so Flutter scales the height proportionally and the mark can
          // never be stretched.
          Image.asset(
            'assets/images/tmdb_logo.png',
            width: 150,
            filterQuality: FilterQuality.high,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                    Text(
                      'TMDB',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: accent,
                      ),
                    ),
          ),
          const SizedBox(height: 10),

          const Text(
            tmdbAttributionNotice,
            style: TextStyle(
              fontSize: 12,
              color: SpectaColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),

          // Shown as text, not as a button: SPECTA ships no URL launcher, and
          // a control that cannot open anything would be a decorative button.
          const SelectableText(
            tmdbHomepageUrl,
            style: TextStyle(
              fontSize: 12,
              color: SpectaColors.textMuted,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 10),
          Text(
            'TMDB supplies artwork, titles and descriptions. Playback sources '
            'come only from the extensions you install.',
            style: const TextStyle(
              fontSize: 11,
              color: SpectaColors.textMuted,
              height: 1.45,
            ),
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
