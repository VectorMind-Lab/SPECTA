import 'package:flutter/material.dart';

import 'home_page.dart';

/// Home view wrapper for the navigation shell.
///
/// Currently delegates to the existing HomePage from Phase 1.
/// Future phases will build the full home screen with hero banners,
/// trending content, continue watching, and personalized recommendations.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage();
  }
}
