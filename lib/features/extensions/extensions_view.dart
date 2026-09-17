import 'package:flutter/material.dart';

import '../../ui/widgets/specta_empty_state.dart';

/// Extension Manager / Store view.
///
/// The extension runtime, capability enforcement and signature verification
/// exist since Phase 1 and run at startup; the user-facing install/manage UI
/// and the remote catalogue integration arrive in Phase 2H. Until then this
/// screen states its real status.
class ExtensionsView extends StatelessWidget {
  const ExtensionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpectaEmptyState(
      icon: Icons.extension_outlined,
      message:
          'The extension runtime is active; the install/manage UI and the '
          'remote catalogue arrive with Phase 2 extension-catalogue '
          'integration',
    );
  }
}
