import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/splash/splash_page.dart';
import 'theme/specta_theme.dart';
import 'theme/specta_theme_provider.dart';

/// Root widget of the SPECTA application.
///
/// One codebase serves both target platforms (Android phone and Android TV);
/// the layout family is resolved at runtime through the platform layer rather
/// than through separate app shells.
///
/// The approved launch flow is Splash (branding, man facing the city) →
/// Main App shell. The Phase 0 foundation screen remains available as
/// diagnostics under Settings.
class SpectaApp extends ConsumerWidget {
  const SpectaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SpectaThemePreset preset = ref.watch(spectaThemePresetProvider);

    return MaterialApp(
      title: 'SPECTA',
      debugShowCheckedModeBanner: false,
      // SPECTA is dark-first: content artwork is the visual anchor. The accent
      // palette follows the persisted theme preset (brand default cyan/teal).
      theme: SpectaTheme.dark(preset),
      darkTheme: SpectaTheme.dark(preset),
      themeMode: ThemeMode.dark,
      home: const SplashPage(),
    );
  }
}
