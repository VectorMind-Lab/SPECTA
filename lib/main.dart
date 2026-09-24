import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/application_bootstrap.dart';
import 'app/specta_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Platform-backed cryptography needs no call here: `cryptography_flutter`
  // is a Dart plugin, so Flutter's generated registrant installs it (and its
  // Ed25519 implementation) before main() runs. Calling its deprecated
  // `enable()` by hand is explicitly no longer necessary.

  // Phase 2E: bring the playback engine up with the application. Kept in a
  // guarded block: a native-library load failure must not prevent the app
  // from starting — the player reports such failures through its structured
  // failure model instead.
  try {
    MediaKit.ensureInitialized();
  } on Object catch (e) {
    debugPrint('media_kit init failed: $e');
  }

  // Riverpod owns the application's dependency graph from the first frame.
  runApp(const ProviderScope(child: SpectaStartup()));
}

/// Brings the application's core services up before the first screen.
///
/// See [applicationBootstrapProvider] for exactly what is constructed and why
/// it must be constructed at launch rather than lazily. The UI consumes those
/// same providers; nothing is duplicated and no screen owns their lifecycle.
class SpectaStartup extends ConsumerWidget {
  const SpectaStartup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(applicationBootstrapProvider);
    return const SpectaApp();
  }
}
