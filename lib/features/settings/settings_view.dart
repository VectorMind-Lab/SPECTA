import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Settings view for app configuration.
///
/// Placeholder for Phase 2+ implementation.
/// Will include theme selection, download settings, extension settings, etc.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.settings_rounded,
      message: 'Settings UI coming in Phase 2',
    );
  }
}
