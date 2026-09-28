import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/downloads/downloads_view.dart';
import '../../features/extensions/extensions_view.dart';
import '../../features/home/home_view.dart';
import '../../features/library/library_view.dart';
import '../../features/search/search_view.dart';
import '../../features/settings/settings_view.dart';
import '../../features/settings/state/auto_update_state.dart';
import '../../ui/widgets/specta_focus_wrapper.dart';
import '../../ui/widgets/specta_scaffold.dart';
import '../../ui/widgets/specta_status_badge.dart';
import '../platform/form_factor.dart';
import '../theme/specta_colors.dart';
import 'specta_destination.dart';
import 'specta_nav_label_layout.dart';
import 'specta_navigation_state.dart';

/// The central responsive application shell for SPECTA.
///
/// Adapts seamlessly between Android Phone (Bottom Navigation Bar)
/// and Android TV / Large Screen (Sidebar Navigation Rail + TV Focus).
class SpectaAppShell extends ConsumerStatefulWidget {
  const SpectaAppShell({super.key});

  @override
  ConsumerState<SpectaAppShell> createState() => _SpectaAppShellState();
}

class _SpectaAppShellState extends ConsumerState<SpectaAppShell> {
  @override
  Widget build(BuildContext context) {
    final SpectaFormFactor formFactor = ref.watch(formFactorProvider);
    final SpectaDestination activeDestination = ref.watch(
      spectaNavigationProvider,
    );

    return Scaffold(
      backgroundColor: SpectaColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top Bar
            SpectaTopBar(
              showSearchBar: activeDestination != SpectaDestination.search,
            ),

            // Content Area
            Expanded(
              child: formFactor.isLargeScreen
                  ? _buildLargeScreenLayout(context, activeDestination)
                  : _buildPhoneLayout(context, activeDestination),
            ),
          ],
        ),
      ),
      bottomNavigationBar: formFactor.isLargeScreen
          ? null
          : _buildPhoneBottomNav(context, activeDestination),
    );
  }

  Widget _buildLargeScreenLayout(
    BuildContext context,
    SpectaDestination activeDestination,
  ) {
    return Row(
      children: <Widget>[
        // Left Sidebar / Navigation Rail
        _buildTvSidebar(context, activeDestination),

        // Main content destination
        Expanded(child: _destinationView(activeDestination)),
      ],
    );
  }

  Widget _buildPhoneLayout(
    BuildContext context,
    SpectaDestination activeDestination,
  ) {
    return _destinationView(activeDestination);
  }

  Widget _destinationView(SpectaDestination destination) {
    return switch (destination) {
      SpectaDestination.home => const HomeView(),
      SpectaDestination.search => const SearchView(),
      SpectaDestination.library => const LibraryView(),
      SpectaDestination.downloads => const DownloadsView(),
      SpectaDestination.extensions => const ExtensionsView(),
      SpectaDestination.settings => const SettingsView(),
    };
  }

  Widget _buildTvSidebar(
    BuildContext context,
    SpectaDestination activeDestination,
  ) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: SpectaColors.surface,
        border: Border(
          right: BorderSide(color: SpectaColors.outline, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Destination Items
          for (final SpectaDestination destination in SpectaDestination.values)
            _buildSidebarItem(
              destination: destination,
              isSelected: destination == activeDestination,
              accent: accent,
            ),

          const Spacer(),

          // Auto Update Card (as shown in reference mockup). The switch is
          // wired to the persisted auto-update setting. width: infinity keeps
          // the card filling the sidebar; shrink-wrapping it would starve the
          // inner Row and overflow on narrow layouts.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SpectaColors.surfaceElevated,
              borderRadius: BorderRadius.circular(SpectaMetrics.cardRadius),
              border: Border.all(color: SpectaColors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Auto Update',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: SpectaColors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      width: 36,
                      child: Transform.scale(
                        scale: 0.7,
                        child: Switch(
                          value: ref.watch(autoUpdateExtensionsProvider),
                          onChanged: (bool value) async => ref
                              .read(autoUpdateExtensionsProvider.notifier)
                              .setEnabled(value),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Extensions & Sources',
                  style: TextStyle(fontSize: 10, color: SpectaColors.textMuted),
                ),
                const SizedBox(height: 8),
                const SpectaStatusBadge(
                  label: 'All Systems Online',
                  isPositive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required SpectaDestination destination,
    required bool isSelected,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SpectaFocusWrapper(
        borderRadius: 8,
        onTap: () {
          ref
              .read(spectaNavigationProvider.notifier)
              .selectDestination(destination);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                isSelected ? destination.selectedIcon : destination.icon,
                size: 20,
                color: isSelected ? accent : SpectaColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                destination.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? accent : SpectaColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneBottomNav(
    BuildContext context,
    SpectaDestination activeDestination,
  ) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final ThemeData theme = Theme.of(context);
    final int destinationCount = SpectaDestination.values.length;

    // NavigationBar gives every destination an equal share of the bar and
    // paints each label at its intrinsic width, so the labels are sized here to
    // the share they actually get. See SpectaNavLabelLayout for why a fixed
    // size is not enough.
    final double labelFontSize = SpectaNavLabelLayout.fontSizeFor(
      slotWidth: MediaQuery.sizeOf(context).width / destinationCount,
      labels: <String>[
        for (final SpectaDestination destination in SpectaDestination.values)
          destination.label,
      ],
      textDirection: Directionality.of(context),
      scaledLabelSize: MediaQuery.textScalerOf(context)
          .scale(SpectaNavLabelLayout.maxFontSize),
    );

    return Container(
      decoration: BoxDecoration(
        color: SpectaColors.surface.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: SpectaColors.outline, width: 0.8),
        ),
      ),
      child: Theme(
        data: theme.copyWith(
          navigationBarTheme: theme.navigationBarTheme.copyWith(
            labelTextStyle: WidgetStateProperty.resolveWith((
              Set<WidgetState> states,
            ) {
              final bool selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: labelFontSize,
                letterSpacing: 0,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : SpectaColors.textMuted,
              );
            }),
          ),
        ),
        child: NavigationBar(
          selectedIndex: activeDestination.index,
          onDestinationSelected: (int index) {
            ref.read(spectaNavigationProvider.notifier).selectByIndex(index);
          },
          backgroundColor: Colors.transparent,
          indicatorColor: accent.withValues(alpha: 0.2),
          elevation: 0,
          height: 62,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: <Widget>[
            for (final SpectaDestination destination
                in SpectaDestination.values)
              NavigationDestination(
                icon: Icon(
                  destination.icon,
                  size: 20,
                  color: SpectaColors.textMuted,
                ),
                selectedIcon: Icon(
                  destination.selectedIcon,
                  size: 22,
                  color: accent,
                ),
                label: destination.label,
              ),
          ],
        ),
      ),
    );
  }
}
