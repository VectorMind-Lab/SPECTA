# Phase C3 report — TMDB and TVMaze integration

Date: 2026-09-25
Status: VERIFIED for the C3 scope. C4 was not started.

## Inspected (C3.1)

- `lib/core/tmdb/`: client, transport, config, DTOs, media identity, normalizer,
  providers, provider matcher.
- `lib/core/tvmaze/`: client, transport, DTOs, providers.
- `lib/core/errors/specta_failure.dart` (TMDB/TVMaze failure subtypes).
- `lib/core/database/daos/metadata_cache_dao.dart` and the shared cache table.
- `lib/core/metadata/`: manager, models, normalizer, `MetadataService`.
- `lib/core/settings/specta_setting_keys.dart`, `lib/features/settings/settings_view.dart`.
- Existing tests: TMDB (client/config/DTO/normalizer/matcher), TVMaze client,
  metadata, C1/C2 suites.
- Pre-existing uncommitted worktree changes; none were reset or discarded.

### Key audit finding

TMDB and TVMaze were **already fully implemented and tested, but completely
unwired**: `MetadataManager` only called extension `details()`, and nothing
referenced `tmdbClientProvider`, `tvmazeClientProvider`, `TmdbNormalizer`, or
`TmdbProviderMatcher`. So C3 is the **connection and fallback layer**, not new
clients. Nothing was duplicated.

## Credential handling (C3.2)

- Source: build-time `--dart-define=TMDB_API_KEY` (`appTmdbApiKey` in
  `tmdb_providers.dart`). Unchanged.
- Never persisted in the database, never read from an asset or extension,
  never logged, never given to an extension runtime, and there is **no**
  Settings entry point. A pre-existing test asserts Settings offers no TMDB
  credential control.
- On storage security: the credential is **not stored at all** — it lives in
  the compiled binary, so masking is never relied upon as if it were
  encryption. `TmdbConfig.maskedKey` is diagnostics-only and is not shown in
  the UI.
- States verified by test: configured, unconfigured, blank, invalid/rejected
  (401), unavailable (network/5xx).

## Implemented

- `lib/core/metadata/catalogue_enricher.dart` — provider-neutral enrichment:
  - `ProviderOutcome` — `matched`, `noMatch`, `notConfigured`,
    `networkFailure`, `malformed`, `notApplicable`, `failed`.
  - `ProviderReport` — one per provider, with optional contribution and the
    structured failure explaining the outcome.
  - `EnrichmentResult` — enriched item plus reports and `fallbacksUsed`.
  - `CatalogueEnricher.enrich(...)` — consults providers in fallback order,
    isolates every failure, and never throws.
- `MetadataItem.withEnrichment(...)` plus `description`/`genres`/`rating`
  accessors: enrichment is **additive only** and never mutates `key`, `type`,
  `year`, `canonicalId` or `identityVersion`.
- `MetadataService` optionally carries `tmdb`/`tvmaze` and exposes
  `enrichedMetadataFor(item)`; `metadataServiceProvider` wires both existing
  provider clients. The existing `metadataFor` path is unchanged.

## Fallback rules (C3.5, C3.6)

1. **Movie** → TMDB only. TVMaze publishes no movie catalogue, so it is never
   consulted and is reported as `notApplicable`.
2. **Series** → TMDB first; TVMaze only when TMDB produced nothing.
3. **Anime** → never enriched. AniList owns anime identity; a TMDB or TVMaze
   answer must never rename or re-identify anime.
4. A failing provider is isolated; enrichment still returns the extension
   metadata and records the failure as data.
5. No identity is ever minted: with `base == null` no provider is contacted, so
   a provider can never create a work that does not already exist.

## Identity stability (C3.3, C3.4, C3.7)

- Movie identity remains `the matrix|movie|1999` (evidence key, version 1).
- Series identity remains `breaking bad|series|2008` (evidence key, version 1).
- Anime identity remains `anilist:16498`, version 2, untouched by C3.
- Strict media-type agreement: a movie request never accepts a series answer.
- Year matching uses a ±1 year tolerance; beyond that the result is reported
  as `noMatch` rather than merged.
- `TmdbProviderMatcher` already implemented extension<->identity matching with
  its own passing tests and was left unchanged. The relationship
  "metadata identity + extension discovery = source resolution" is untouched:
  enrichment is not reachable from `SourceManager` or `getSources()`.


## Cache (C3.8)

No new cache. TMDB and TVMaze already read/write the shared `metadata_cache`
table namespaced by `source` (`tmdb`, `tvmaze`), with the existing 30-day TTL,
stale refetch, failure-never-cached and no-cache-wired behaviours, all covered
by their pre-existing passing tests. C3 added no parallel cache. Offline
behaviour is covered at the client level: a warm cache still serves a result; a
cold cache returns a retryable `networkFailure` that enrichment isolates.

## Database changes

None. C3 required no schema change and no migration.

## Tests added

`test/core/metadata/catalogue_enricher_test.dart`:
- Credential: unconfigured, blank, rejected key (401), and an assertion that
  the key never appears in a failure, endpoint or report text.
- Movie and series enrichment; extension data still winning.
- Movie never accepts a series answer; a distant year is `noMatch`.
- Empty results → `noMatch`; malformed body → `malformed`.
- TVMaze never consulted for movies (`notApplicable`).
- Series falls back to TVMaze; `fallbacksUsed` recorded.
- TVMaze not consulted when TMDB answered; network failure isolated.
- Rate limiting vs empty results stay distinguishable.
- Anime never enriched; identity and identity version preserved.
- `base == null` contacts no provider and creates no identity.
- Enrichment is additive and never overwrites extension artwork or title.

## Tests executed

Toolchain: `H:\flutter\bin\flutter.bat` (Flutter 3.47.4 / Dart 3.13.3).

- `dart format` on all C3 files: passed.
- `flutter analyze`: **No issues found!**
- C3 + regression subset (metadata, TMDB, TVMaze, AniList, C1, C2, discovery,
  identity, metadata cache): **285 passed, 0 failed.**
- `flutter test` (full suite): **1027 passed, 39 skipped, 0 failed.**

## Security considerations

- No credential was requested, pasted, hardcoded or committed. The only key
  literal in the repo is an obviously fictional test value.
- Failures record the endpoint **path** only, never the full URI, so a key
  travelling as a query parameter can never leak into logs or diagnostics.
- No provider-specific playback logic; providers cannot supply sources.
- No extension sandbox change; no DRM/paywall/auth/access-control bypass.

## Known limitations

- No live TMDB or TVMaze network call was made, so behaviour is verified
  against injected transports rather than the live APIs.
- Enrichment uses search-based matching. It does not yet fetch full TMDB
  season/episode structure, which the existing `TmdbNormalizer` and
  `getSeasonDetails` support; wiring that into the details screen is UI work
  and is left to a later phase.
- No Android build and no real-device validation were performed in C3.

## Remaining work

- C4: wire enrichment (and anime/AniList identity) into Home, Search and
  Details presentation, and the extension matcher into source resolution.
