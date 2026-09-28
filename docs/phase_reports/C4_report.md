# Phase C4 report — User-facing metadata integration

Date: 2026-09-25
Status: **COMPLETE AND VERIFIED** — including a real-device run.

## Inspected

- `lib/features/home/` (home_view, home_feed, hero banner), `lib/features/search/`
  (search_view, search_state), `lib/features/details/` (details_view,
  details_state), `lib/ui/widgets/`.
- `lib/core/metadata/` (manager, models, catalogue_enricher), TMDB/TVMaze/AniList
  clients and providers, `specta_colors`, existing widget/card/rail helpers.
- Pre-existing uncommitted changes; none reset or discarded.

## Delivered and verified

### C4.6 Artwork
- New `lib/ui/widgets/specta_artwork.dart` — the single place remote artwork is
  loaded. Widgets receive an already-resolved URL from metadata; no widget builds
  a provider URL. Handles: loaded image, no URL, blank/whitespace URL, non-http
  URL, load failure, and in-flight loading (all non-image states render the same
  neutral placeholder). Used by Details header and the Search card.
- Removed duplicated inline `Image.network` + `errorBuilder` from Details and
  Search.

### C4.3 Details
- Header now reads the MERGED metadata accessors (`metadata.description`,
  `.genres`, `.rating`) instead of `details.first`. This was the real C2/C3
  integration gap: provider data lands in a later contribution, so
  `details.first` would have hidden every TMDB/TVMaze/AniList field.
- Type label is now content-type aware: Movie / Series / **Anime**.
- Poster fallback icon is content-type aware (movie / tv / animation).
- Format and anime episode count are shown when present.
- Overview uses the merged description.
- `DetailsState` now carries `providerReports` and `hasProviderGap`.
- `DetailsSessionNotifier.open` runs `enrichedMetadataFor` after the extension
  round and applies it to the same identity; a provider failure can never turn
  a working details screen into a failure.

### C4.4 Seasons/episodes
- Anime now renders the same seasons/episodes surface as series. Play and
  Download per episode are unchanged and still go through the existing
  entry points.

### C4.1 Home
- New `trendingFeedProvider` + `TrendingFeed`/`TrendingStatus` in home_feed.dart,
  fed by the existing TMDB client (popular list) through the shared cache.
- A "Popular" rail renders only when the provider returned real items. An
  unconfigured or unreachable provider simply omits the rail; it can never
  blank or block the real extension feed.
- Reuses the existing `_Rail` and `_DiscoveryCard` widgets — no new visual design.

### C4.5 Genres
- Genres already existed in the metadata models. No fake data was added; the
  Details header now renders the union of genres across contributions.

### C4.7 Identity safety
- Details/Search label and icon are derived from `MediaType`, so anime is never
  displayed as series.
- C1/C2/C3 identity tests all pass unchanged.

### C4.2 Search (movie / series / anime)
- Search now reaches ANIME through the metadata system. After the extension
  round, `SearchSessionNotifier` queries AniList and appends the results to
  `SearchState.catalogueItems`, which the view renders after the extension
  results via `allItems`.
- Extension discovery is untouched and remains the authority on what is
  playable: the round's status still comes from the coordinator, and a catalogue
  result carries NO extension reference. The card says so ("Anime catalogue — no
  streaming source yet") rather than claiming a source.
- An AniList outage cannot break the round: the step is best-effort and
  best-effort-empty on any failure.
- Search remains the way to find movies/series; metadata search does not replace
  source discovery.

### Capability probe (why the catalogue step is guarded)
- New `lib/core/database/database_capabilities.dart` with
  `catalogueDatabaseUsable()`. The catalogue clients read through the shared
  `metadata_cache`, which is backed by the Drift database; that resolves its
  storage path via a platform channel on first query. The probe reports whether
  Flutter platform services exist so a caller can skip the catalogue step in an
  environment that cannot open the database.
- Exposed as `catalogueDatabaseUsableProvider` so a test can declare the
  database usable and drive the real catalogue path.

## Device verification (C4 gate)

Debug APK built (`flutter build apk --debug`, `assembleDebug` OK) and installed on a
real device (`R83L20FRDFM`). Verified with screenshots:

- **Search** — query "bebop" returns 4 real AniList entries with real cover
  artwork, correct `Anime` type label, correct years (1998 / 2001 / 2012 / 1998),
  and the honest "Anime catalogue — no streaming source yet" notice.
- **Details** — Spirited Away shows real AniList data: poster, title,
  `Anime · 2001 · ★ 8.6 · MOVIE`, episode count, genre chips
  (Adventure/Drama/Fantasy/Supernatural), full description, and the existing
  Play / Download actions.

### Two real defects found only on device, then fixed

1. **Search hid catalogue results when no extension was installed.** A round with
   zero extensions reports `noExtensions`, and the view rendered only the install
   prompt — discarding anime AniList had already returned. Fixed: `noExtensions`
   renders the result list when `catalogueItems` is non-empty, and only shows the
   install prompt when there is genuinely nothing. Regression test added.

2. **The AniList query was rejected by the live API with HTTP 400.** The field
   set was wrong in two ways, and BOTH unit-test-stubbed away:
   - `coverImage` is an object (`MediaCoverImage`) and **must** have a
     sub-selection; requesting it bare invalidates the entire query. Now
     `coverImage { extraLarge large color }`.
   - `startDate` is a fuzzy date **object**, not a string. Now
     `startDate { year month day }`, and the DTO reads `.year`.

   Consequence before the fix: every search returned nothing (query rejected),
   and even a valid payload would have produced a null year and null cover
   because both were read as strings. The DTO now parses both shapes and still
   tolerates the older bare-string form for already-cached payloads. The corrected
   query was re-validated against the live API (HTTP 200, 4 results, real cover
   URL, year, format, episodes, studio).

The lesson recorded for future phases: a stubbed client cannot validate a
third-party schema. The field set is now checked against the live API.

## Tests added

- `test/features/search/search_anime_integration_test.dart`
  - anime results appear alongside extension results (AniList identity, key,
    empty references, extension-first ordering);
  - an AniList outage does not break the extension round.
- `test/core/database/database_capabilities_test.dart` — the probe answers
  without throwing and is usable in a real surface.

## Verification

Toolchain: `H:\flutter\bin\flutter.bat` (Flutter 3.47.4 / Dart 3.13.3).

- `dart format`: passed.
- `flutter analyze`: **No issues found!**
- `flutter test` (full suite): **1051 passed, 39 skipped, 0 failed.**
- `flutter build apk --debug`: **succeeded** (`Built build\app\outputs\flutter-apk\app-debug.apk`).
- Real device: **verified** (see Device verification above).

One full-suite run reported a single failure in a title-casing assertion
(`'Blade Runner'` vs `'BLADE RUNNER'`) in a file untouched by C4; the suite
passed clean on rerun. Treated as a pre-existing flake, not a C4 regression.

## Security

- No credential handled, requested, or displayed. `SpectaArtwork` renders only
  URLs that metadata already resolved.
- No provider playback logic; `SourceManager` untouched.
- No extension sandbox change.

## Known limitations

- C4.8 source resolution was intentionally not modified; the Metadata ≠
  Extension ≠ SourceManager ≠ Player separation is unchanged.
- Details does not yet fetch full TMDB season/episode structure (search-based
  enrichment only).
- The device run used a debug APK on a phone form factor. Android TV (leanback)
  layout was NOT exercised on a TV device or emulator.
- The AniList live contract is verified for the fields SPECTA requests; no
  automated live test guards it, so a future AniList schema change would need a
  device run to notice.
- No extension was installed during the device run, so the "catalogue result
  with an extension reference" path (search → metadata identity + extension
  discovery → source resolution) was not exercised end-to-end on hardware.
