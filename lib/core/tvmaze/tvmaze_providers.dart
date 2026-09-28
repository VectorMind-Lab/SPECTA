import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:specta/core/database/database_providers.dart';
import 'package:specta/core/tvmaze/tvmaze_client.dart';
import 'package:specta/core/tvmaze/tvmaze_transport.dart';

/// Riverpod wiring for the credential-free TVMaze source.
///
/// There is deliberately NO config provider next to this one: TVMaze needs no
/// key, no account and no token, so there is nothing to configure and nothing
/// that can be missing. The client therefore keeps working even when the
/// build-time TMDB define is absent, which is exactly the fallback this source
/// exists to provide.

/// Transport boundary, overridable in tests.
final Provider<TvmazeTransport> tvmazeTransportProvider =
    Provider<TvmazeTransport>((Ref ref) {
      return DartIoTvmazeTransport();
    });

/// The [TvmazeClient], with the shared persistent TTL cache injected so every
/// TVMaze request is read-through cached just like TMDB's.
final Provider<TvmazeClient> tvmazeClientProvider = Provider<TvmazeClient>((
  Ref ref,
) {
  // Same rule as TMDB: the cache resolves on first use, so building a client
  // never forces the database open and a missing cache simply means uncached.
  return TvmazeClient(
    transport: ref.watch(tvmazeTransportProvider),
    cacheFactory: () => ref.read(metadataCacheDaoProvider),
  );
});
