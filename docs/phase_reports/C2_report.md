# Phase C2 report — Anime infrastructure

Date: 2026-09-25
Status: VERIFIED for the C2 scope. C3 and C4 were not started.

## Inspected

- `PROJECT_STATE.txt`, `README.md`, C1 phase reports.
- Existing catalogue clients: `lib/core/tmdb/`, `lib/core/tvmaze/`.
- `lib/core/errors/specta_failure.dart` and `specta_result.dart`.
- `lib/core/database/daos/metadata_cache_dao.dart` and the shared cache table.
- C1 identity model: `MediaType.anime`, `ExternalIds`, `MediaIdentity`,
  `DiscoveryItem`, `MetadataItem`, `ReferenceMetadata`.
- Discovery normalization/deduplication and the C1 test suite.
- Pre-existing uncommitted worktree changes; none were reset or discarded.

## Architecture decision

No second networking architecture was introduced. The AniList client mirrors the
established catalogue-client shape:

- an injectable transport interface with a `dart:io` implementation;
- `SpectaResult` everywhere, never a thrown exception;
- a dedicated structured failure type in the existing sealed `SpectaFailure`
  hierarchy;
- read-through caching through the existing `MetadataCacheDao`, namespaced by
  the `source` column.

No new pub dependency, no new HTTP package, and no provider-specific logic in
SPECTA core.

## Implemented

- `lib/core/anilist/anilist_transport.dart` — `AniListTransport` seam plus
  `DartIoAniListTransport` (POST, bounded deadline, sanitized failures).
- `lib/core/anilist/anilist_dto.dart` — `AniListMedia`, `AniListTitle`,
  `AniListStudio`, `AniListFormat`. Only fields SPECTA consumes are modelled.
  Wrong-typed or partial fields degrade to null/empty instead of throwing.
- `lib/core/anilist/anilist_client.dart` — `getMedia(id)` and `searchMedia`.
  Credential-free GraphQL POST, 15s deadline, structured status mapping,
  GraphQL `errors` detection, read-through cache.
- `lib/core/anilist/anilist_normalizer.dart` — maps AniList records into the C1
  `DiscoveryItem` / `MetadataItem` anime identity.
- `lib/core/anilist/anilist_providers.dart` — Riverpod wiring using the shared
  `metadataCacheDaoProvider`.
- `AniListFailure` / `AniListFailureType` added to `specta_failure.dart`,
  mirroring the TMDB/TVMaze discipline. No configuration or credential
  categories exist because AniList needs none.
- Provider-neutral optional fields added to existing models:
  `DiscoveryItem.externalIds`, `MetadataItem.format`, `MetadataItem.episodeCount`,
  `ReferenceMetadata.format`, `.episodeCount`, `.studios`.
- Added the new sealed failure subtype to the existing exhaustiveness switch in
  `test/core/downloads/download_models_test.dart`.

## Identity rules

- Anime identity is `anilist:<id>`, identity version 2, from C1.
- AniList scores (0-100) are converted to SPECTA's existing 0-10 scale.
- AniList duration (minutes) is converted to seconds.
- An anime result is never normalized into series or movie identity.
- Movie/series identity remains `normalized title|type|year` and is unchanged.
- A non-positive or missing AniList id is rejected; no id is ever guessed.

## Cache behavior

- Cache key: `media:<id>` and `search:<page>:<lowercased query>`, stored in the
  existing `metadata_cache` table with source `anilist`.
- TTL: the shared `MetadataCacheDao` TTL (30 days).

## Database changes

None. C2 required no schema change and no migration. It reuses the existing
`metadata_cache` table with a new `source` namespace value.

## Tests added

- `test/support/anilist_test_harness.dart` — fake transport and payload
  builders.
- `test/core/anilist/anilist_client_test.dart` — request shape, credential-free
  assertion, empty-query and non-positive-id short circuits, 404/429/5xx/other
  status mapping, retryability, transport failure, malformed JSON, GraphQL
  `errors`, unusable payload.
- `test/core/anilist/anilist_normalizer_test.dart` — DTO defensive parsing,
  wrong-typed fields, format handling, identity/version, and
  anime-vs-movie/series non-collision, plus movie/series dedup regression.
- `test/core/anilist/anilist_cache_test.dart` — cache reuse, namespace
  isolation, expiry, per-query/page keying, offline warm and cold behavior,
  unusable row, and no-cache behavior.

## Tests executed

Toolchain: `H:\flutter\bin\flutter.bat` (Flutter 3.47.4 / Dart 3.13.3).

- `dart format lib/core/anilist test/core/anilist test/support/anilist_test_harness.dart`: passed.
- `flutter analyze`: **No issues found!**
- `flutter test test/core/anilist ...` (C2 + C1 identity, discovery, metadata,
  TMDB, TVMaze, cache): **267 passed, 0 failed.**
- `flutter test test/core/anilist`: **34 passed.**
- `flutter test` (full suite): **1009 passed, 39 skipped, 0 failed.**

## Security considerations

- No API key, token, or credential is used or requested. AniList's public
  GraphQL endpoint needs none, and a test asserts none is sent.
- No secrets were added to source, tests, docs, or config.
- No provider-specific logic was added to SPECTA core.
- No extension sandbox control was weakened.
- No DRM, paywall, authentication, or access-control bypass.

## Known limitations

- The AniList client is infrastructure only. It is not yet called by Home,
  Search, Details, or source resolution; that is C3/C4 work.
- No live AniList network call was made. All client behavior is verified
  against an injected transport, so the GraphQL query itself has not been
  validated against the live API.
- AniList relations, studios beyond animation studios, and per-episode AniList
  data are not modelled; SPECTA does not need them yet.
- No Android build and no real-device validation were performed in C2.

## Remaining work

- C3/C4: wire anime identity and AniList metadata into Home, Search, Details,
  and source resolution.
- Optional: a live, opt-in AniList contract test, mirroring the existing
  opt-in Internet Archive live suite.

- Freshness: a fresh row answers with no network call.
- Stale/expired: the row is refetched and replaced.
- Failure: a non-2xx or unparseable response is never cached.
- Offline: a warm cache still serves the record; a cold cache returns a
  structured `networkError` that is retryable.
- A valid-JSON but structurally unusable cached row is treated as a miss.
- A cache read/write failure never fails the request.
