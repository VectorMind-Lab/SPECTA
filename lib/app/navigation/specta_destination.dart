import 'package:flutter/material.dart';

/// Navigation destinations in the SPECTA app shell.
enum SpectaDestination {
  home(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  search(
    label: 'Search',
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
  ),
  library(
    label: 'Library',
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
  ),
  downloads(
    label: 'Downloads',
    icon: Icons.download_outlined,
    selectedIcon: Icons.download_rounded,
  ),
  extensions(
    label: 'Extensions',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension_rounded,
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  const SpectaDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
