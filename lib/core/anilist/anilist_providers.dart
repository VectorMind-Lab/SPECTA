import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:specta/core/anilist/anilist_client.dart';
import 'package:specta/core/anilist/anilist_transport.dart';
import 'package:specta/core/database/database_providers.dart';

final Provider<AniListTransport> anilistTransportProvider =
    Provider<AniListTransport>((Ref ref) {
      return DartIoAniListTransport();
    });

final Provider<AniListClient> anilistClientProvider = Provider<AniListClient>((
  Ref ref,
) {
  // The cache is resolved LAZILY, on first catalogue use. A provider may be
  // constructed in an environment with no database (a pure unit test), and the
  // client already degrades to uncached behaviour when the cache is absent, so
  // the database must never be forced open just to build a client.
  return AniListClient(
    transport: ref.watch(anilistTransportProvider),
    cacheFactory: () => ref.read(metadataCacheDaoProvider),
  );
});
