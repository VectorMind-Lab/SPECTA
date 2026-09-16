import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database_providers.dart';
import '../runtime/controlled_runtime_api.dart';
import '../runtime/flutter_js_sandbox.dart';
import '../runtime/runtime_api.dart';
import '../verification/signature_verifier.dart';
import 'drift_extension_registry.dart';
import 'extension_manager.dart';
import 'extension_registry.dart';

/// The extension subsystem, wired the same way the rest of SPECTA's core is:
/// plain Riverpod providers over the shared Drift database.
///
/// This is the whole of the Phase 1 integration. There is no extension screen
/// and no catalogue; the point is that the extension foundation is constructed
/// as part of the application's dependency graph instead of sitting in
/// libraries that no build ever reaches.
///
/// Nothing here is Flutter-UI aware. The only Flutter import is `foundation`,
/// used for debug-only log output.

/// Extension metadata persistence.
///
/// Uses the existing `SpectaDatabase`, so extensions live in the same SQLite
/// file as everything else. No second database is introduced.
final Provider<ExtensionRegistry> extensionRegistryProvider =
    Provider<ExtensionRegistry>((Ref ref) {
      return DriftExtensionRegistry(ref.watch(spectaDatabaseProvider));
    });

/// The controlled request boundary every extension network call passes
/// through.
///
/// Log output goes to `debugPrint`, and only in debug builds: extension logs
/// are diagnostics, not user-facing content.
final Provider<ControlledExtensionRuntimeApi> extensionRuntimeApiProvider =
    Provider<ControlledExtensionRuntimeApi>((Ref ref) {
      final ControlledExtensionRuntimeApi api = ControlledExtensionRuntimeApi(
        logSink: (ExtensionLogLevel level, String message) {
          if (kDebugMode) {
            debugPrint('[extension/${level.code}] $message');
          }
        },
      );
      ref.onDispose(api.dispose);
      return api;
    });

/// The single entry point consumers use to work with extensions.
///
/// Constructing this builds a registry, the controlled request API and the
/// manager, and does no I/O — the database opens lazily on first use.
final Provider<ExtensionManager> extensionManagerProvider =
    Provider<ExtensionManager>((Ref ref) {
      return ExtensionManager(
        registry: ref.watch(extensionRegistryProvider),
        runtimeApi: ref.watch(extensionRuntimeApiProvider),
        sandboxFactory: FlutterJsSandbox.new,
        // Verification against SPECTA's published public key.
        verifier: SignatureVerifier.instance,
      );
    });
