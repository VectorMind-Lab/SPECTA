# SPECTA vs Zangetsu - Gap Analysis and Home Rails Spec

**Date:** 2026-09-29
**Scope:** Specification, then implementation of Option B. See "As built" for the shipped files and the gate result.
**Companion:** `ZANGETSU_UX_REFERENCE.md` in this folder.
**Method:** read of `docs/` plus direct reads of `lib/`. The analysis began in the `C:` working copy, which was subsequently found to be **5 slices stale** (head `cbcc18b`, slice 7, with 8 uncommitted files). All findings were re-verified and all implementation was performed in the code of record, `H:\dev\SPECTA`, branch `source-system-run`, head `f12903a` (slice 12).

## Summary

Most of what Zangetsu does, SPECTA either already has or has deliberately chosen not to do. AniList is not a missing feature - it is deeply integrated. The real gap is narrow: a handful of user-facing surfaces are absent, and one approved change (Home genre rails) is now specified below.

Measured baseline carried forward from `SOURCE_RUN_REPORT.md`: **1252 passed / 39 skipped / 0 failed**, `flutter analyze` clean (2026-09-28, slices 1-7). Slices 8-12 took the suite to **1287 passed / 39 skipped / 0 failed**; the 14 tests added by this work take it to **1301 passed / 39 skipped / 0 failed**. Current measured total is **1378 passed / 2 skipped / 0 failed** (2026-09-30, after the global `fetch()` bridge, the foreign-name alias table and the JSON-index routing fix) — see `SOURCE_RUN_REPORT.md` §14.

## Already built - do not rebuild

Verified present in `lib/`:

- Extension/Source system: node identity, v8-to-v9 persistence, reorder, true delete including `.js` unlink, source health.
- Catalogue and user repository index parser, plus SAF, URL and repository install routes.
- Player with source fallback (Phase 2E).
- Downloads engine with a verified byte-integrity gate (Phase 2G).
- Library and watch progress (Phase 2F).
- App identity: icon, splash, TMDB credit.
- Metadata: TMDB, TVMaze and **AniList**, wired through `CatalogueEnricher` into `MetadataManager`, with `MediaIdentity.anilistKey`.
- Six-destination shell: Home, Search, Library, Downloads, Sources, Settings.

## Decisions locked in this review

### 1. Zangetsu per-source detail screen - NOT to be copied

The public source card in SPECTA shows only a neutral node label (`Node 1`, `Node 2`, and so on). This is decision C, recorded earlier, and the Zangetsu source detail screen (source name, `Search this source`, per-source card rails such as `Latest`/`Netflix`) would reverse it.

**Resolution: Decision C stands. The Zangetsu source detail screen is a standing prohibition, recorded here so it is not re-proposed.**

### 2. Manga/Novel tabs - OUT OF SCOPE

Zangetsu declares `Manga` and `Novel` source tabs. In the captured build both are empty ("No sources installed"), and SPECTA `MediaType` carries only `movie` and `series`. There is no media-type axis to hang these tabs on.

**Resolution: out of project scope entirely. Removed from consideration.**

### 3. Genre rails - constraint found, Option B selected

Detail below, because this is the one item that had a hidden dependency.

## Grep-verified gaps in `lib/`

| Zangetsu feature | SPECTA status | Evidence |
|---|---|---|
| Auto Resolve sheet | **Absent.** `autoResolve` / `auto-resolve` return 0 hits. `SourceManager` ranks sources, but there is no per-title "try every source until one matches" surface and no per-title source override. | 0 hits |
| Trailer hero | **Absent.** `trailer` returns 0 hits. Home uses a static `HeroSpotlightBanner`. | 0 hits |
| Genre browsing | **Display-only.** Genre exists as a metadata field and renders as up to 6 chips on Details. There is no chip taxonomy page and no genre-filtered grid. | `details_view.dart` renders `genres.take(6)` |
| Schedule | **Absent, and the name means something else here.** Every `schedule` hit relates to download scheduling, not an airing schedule. | `download_manager`, `background_downloader_engine`, `download_retry_policy` |
| Details tab structure | **Absent.** Details is a single scroll: header, genres, then seasons/episodes. No Episodes/Cast/Relations/Details tab bar. | no tab widget in `details_view.dart` |
| Relations | **Absent.** 0 hits, despite AniList exposing relations natively. | 0 hits |
| Wrong title? | **Absent.** 0 hits, which is notable because `MediaIdentity.anilistKey` and `tmdb_provider_matcher` already perform the cross-provider identity mapping this affordance would correct. | 0 hits |
| My List (curated) | **Absent as a concept.** 0 hits for watchlist. `Library` is watch history and progress - adjacent, not equivalent. | 0 hits |

## Why genre rails are not UI-only

This was the one genuine conflict found, and it changes what "Option B" costs.

SPECTA catalogue clients expose **per-title lookups only**:

- `AniListClient`: `getMedia(int id)` and `searchMedia(String query)`. No discover or browse-by-genre endpoint.
- `TmdbClient`: `getPopularMovies`, `getPopularSeries`, `searchMulti`, plus details. No genre-filtered discover call.

Genre is populated by `CatalogueEnricher`, which resolves **one item at a time** via the `anilistKey` / `_matchTmdb` flow. Home `TrendingFeed` reads `getPopularMovies` and does not enrich, so **rail items carry no genres today**. Genres appear on Details only, because that is where enrichment runs.

A genre rail therefore requires one of two approaches:

| Option | Cost | Fits the no-new-architecture constraint? |
|---|---|---|
| A. Add genre-filtered discover to the TMDB/AniList clients | New endpoints, caching, error paths, tests | **No** - this is new architecture |
| B. Group existing rail items client-side by genre after enrichment | Reuses `CatalogueEnricher` unchanged; grouping is presentation-only | **Yes** |

**Decision: Option B.** No new fetch path. Genre data comes from `CatalogueEnricher` as it already exists.

## Approved design - Home genre rails (Option B)

### Behaviour

1. Existing Home providers (`homeFeedProvider`, `trendingFeedProvider`) keep their current items and rendering. They are not modified.
2. Those items are passed through the **existing** `CatalogueEnricher` to obtain per-title genre data.
3. Results are grouped **client-side by genre**, purely at the presentation layer.
4. A genre rail renders **only when it holds 5 or more enriched items**. (Approved threshold: 5.)
5. Any genre holding 1 to 4 items is dropped silently. Anything under 2 never renders under any circumstances.
6. Genre rails are capped in count and rendered after the preserved sections, so Home stays mobile-first and does not become crowded.

### Constraints

- **Preserve** Continue Watching, New on SPECTA and Popular. No edits to those providers, and no change to their order.
- **No new fetch path.** No discover/browse endpoints are to be added to `AniListClient` or `TmdbClient`.
- **Budgeted and non-blocking.** Enrichment is limited and must never stall the Home render. A slow or failing provider degrades to fewer or zero genre rails, not to a broken Home.
- **Honest degradation.** No placeholder genres and no invented genres when enrichment is unavailable.
- **Restraint.** No recommendation system, no ranking changes, no new architectural layer.

### Risks to manage during implementation

- **N metadata calls.** Enrichment is one call per title, so it needs a hard cap, and the failure of any single title must not fail the batch. This is handled inside the existing enricher error handling, not new architecture.
- **Genres may legitimately be sparse or uneven.** With a threshold of 5, some sessions will correctly show zero genre rails. That is the rule working, not a bug. It should not be reported as a failure later.

## Correction found during implementation - genre data is cheaper than this spec predicted

The analysis above assumed rail items carry no genres, so Option B had to enrich every item through `CatalogueEnricher` at one metadata call per title, with an N-call budget as its main risk.

**That assumption was wrong, and the truth is better than the spec.**

- `TmdbMediaSummary` already carries `genreIds`, parsed from TMDB's `genre_ids` on the `/movie/popular` and `/tv/popular` list responses.
- `TmdbNormalizer.toDiscoveryItem` **drops** them. That is why rail items looked genre-less - the data was being discarded one layer beneath the UI, not missing.
- The only genuinely absent piece was an id-to-name mapping. `TmdbMediaDetails.genres` does carry names, but only on the detail endpoints, so using it would have cost one request per title - re-introducing exactly the N-call problem.

**Resolution:** a local `TmdbGenres` table (protocol constants, not content - TMDB's own documented ids and wording, so no judgement about any title is encoded) plus grouping over the `genre_ids` already in hand. This **designs the N-call risk out** rather than budgeting for it.

Two consequences, recorded honestly:

1. `genre_ids` is confirmed present in the DTO and confirmed parsed, but is **not** confirmed populated for every response TMDB returns in the field. If a response omits it, that item contributes nothing and the rail is simply absent - the honest degradation this spec required.
2. Because no per-item call is made, the concurrency cap this spec called "the only real engineering risk" is **not required**. There is nothing to cap.

`/tv/popular` is now requested alongside `/movie/popular`, so the pool covers series as well as movies. `/movie/popular` is normally already warm, because `trendingFeedProvider` requests the same page through the same read-through cache. Existing client method on an existing endpoint - **not a new fetch path**.

## As built

| File | Change |
|---|---|
| `lib/core/tmdb/tmdb_genres.dart` | New. TMDB genre id to name. Movie and TV namespaces merged into one map - every id the two share carries the same name in both, so a single lookup is unambiguous. Unknown ids resolve to null and contribute nothing, rather than rendering as a raw number. |
| `lib/features/home/home_genre_rails.dart` | New. `GenreRail`, `GenreRails` (pure `from()` grouping; floor 5, cap 4) and `homeGenreRailsProvider`. |
| `lib/features/home/home_view.dart` | Genre rails rendered after Popular, reusing the existing `_Rail` and `_DiscoveryCard`. The provider is watched with the same "unresolved or failed contributes nothing" discipline as Popular, and is included in `nothingToShow` and in pull-to-refresh. No existing provider, rail or their order was modified. |
| `test/features/home/home_genre_rails_test.dart` | New. 14 tests over the pure grouping logic: the floor, unknown ids, multi-genre items, movie/series pooling, dedup by discovery key, ordering, the cap, and empty input. |

Gate: `flutter analyze` clean on all four files. Full `flutter test`: **1301 passed / 39 skipped / 0 failed**, skips unchanged. Nothing has been committed.


## Status

**Implemented and verified, uncommitted.** Decision C (the per-source detail screen prohibition) and the Manga/Novel exclusion both stand, untouched by this change. Both risks listed above are now resolved: the N-call risk no longer exists, and the sparse-genre behaviour is expected, deliberate, and documented so it is not later misread as a defect.
