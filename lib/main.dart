import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/specta_app.dart';
import 'core/extensions/manager/extension_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

/// Brings the extension subsystem up with the application.
///
/// Phase 1 ships no extension UI, so no screen displays the manager. It is
/// constructed here, through the same provider graph as the rest of the core,
/// so that the extension foundation is part of the running application rather
/// than library code that no entry point reaches. Keeping it out of the widget
/// tree below this point means the extension system stays independent of any
/// screen and can be exercised without the UI.
class SpectaStartup extends ConsumerWidget {
  const SpectaStartup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Constructs the registry, the controlled request API and the manager.
    ref.watch(extensionManagerProvider);
    return const SpectaApp();
  }
}
