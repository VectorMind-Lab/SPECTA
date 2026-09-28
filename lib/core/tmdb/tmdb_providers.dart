import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/tmdb/tmdb_client.dart';
import 'package:specta/core/tmdb/tmdb_config.dart';
import 'package:specta/core/tmdb/tmdb_transport.dart';

/// Central build-time TMDB credential, supplied by the developer.
///
/// The value is injected at COMPILE time as a --dart-define. The recommended
/// way to supply it is the build script, which reads a git-ignored `.env` from
/// the project root and forwards each entry as a define:
///
///   .\tool\build_with_env.ps1                     # debug APK
///   .\tool\build_with_env.ps1 -Target appbundle -Release
///
/// Equivalent manual invocations:
/// `flutter run --dart-define=TMDB_API_KEY=<key>`
/// `flutter build apk --dart-define=TMDB_API_KEY=<key>`
///
/// `.env` is never bundled as an asset (it is git-ignored and absent from
/// `pubspec.yaml` assets); only the value reaches the compiler.
///
/// Empty when no define was supplied (local dev without catalogue access).
/// This constant is safe to commit: it carries no secret, only the define
/// lookup. The real key lives in the build invocation / CI secret, never in
/// source, assets, settings, logs, or the UI.
///
/// NOTE: a compiled binary CONTAINS the key, because that is what a compile-time
/// constant is. Treat any shipped APK as a secret-bearing artifact.
const String appTmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

/// The active, immutable [TmdbConfig], resolved once from the central
/// build-time credential. There is intentionally no setter, no persistence,
/// and no Settings entry point: users never supply TMDB credentials.
final Provider<TmdbConfig> tmdbConfigProvider = Provider<TmdbConfig>((Ref ref) {
  final String key = appTmdbApiKey.trim();
  if (key.isEmpty) return const TmdbConfig();
  return TmdbConfig(apiKey: key);
});

/// Provider for the transport layer, overridable in tests.
final Provider<TmdbTransport> tmdbTransportProvider = Provider<TmdbTransport>((
  Ref ref,
) {
  return DartIoTmdbTransport();
});

/// Provider for the [TmdbClient] tied to the current [TmdbConfig].
///
/// The persistent TTL cache is always injected in the app graph, so every
/// catalogue request is read-through cached. Tests that build a
/// [TmdbClient] directly can omit `cache` for uncached behaviour.
final Provider<TmdbClient> tmdbClientProvider = Provider<TmdbClient>((Ref ref) {
  final TmdbConfig config = ref.watch(tmdbConfigProvider);
  final TmdbTransport transport = ref.watch(tmdbTransportProvider);
  // The cache is an optimization, not a requirement: it resolves on first
  // use, so a client can be built where no database exists and still works
  // (uncached).
  return TmdbClient(
    config: config,
    transport: transport,
    cacheFactory: () => ref.read(metadataCacheDaoProvider),
  );
});
