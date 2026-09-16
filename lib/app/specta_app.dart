import 'package:flutter/material.dart';

import '../features/home/home_page.dart';
import 'theme/specta_theme.dart';

/// Root widget of the SPECTA application.
///
/// One codebase serves both target platforms (Android phone and Android TV);
/// the layout family is resolved at runtime through the platform layer rather
/// than through separate app shells.
class SpectaApp extends StatelessWidget {
  const SpectaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPECTA',
      debugShowCheckedModeBanner: false,
      // SPECTA is dark-first: content artwork is the visual anchor.
      theme: SpectaTheme.dark(),
      darkTheme: SpectaTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
