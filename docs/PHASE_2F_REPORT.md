# SPECTA — PHASE 2F REPORT

**Phase:** 2F — Library / History / Watch-Progress persistence
**Status:** COMPLETE — unit + widget + migration tests green, REAL DEVICE verified,
debug APK builds.
**Date:** 2026-09-19
**Depends on:** Phase 1 (extension foundation), 2A (UI shell), 2B (discovery),
2C (metadata), 2D (source manager), 2E (player integration).
**Authorized boundary:** 2F only. 2G (downloads) and 2H (extension catalogue)
were NOT started.

---

## 1. SCOPE

Phase 2F connects the seam Phase 2E deliberately left open:

```
Player
  ↓
PlaybackProgressSink          (the 2E seam, unchanged in role)
  ↓
PersistentPlaybackProgressSink (this phase)
  ↓
LibraryStore → LibraryDao → Drift / SQLite
  ↓
Continue Watching / History / Library
```

The player was NOT rewritten. The Source Manager was NOT touched. The extension
contract was NOT modified. No download, catalogue, or TMDB work was started.

The only change the player needed was the sink binding — the session still
reports honest, measured progress through one interface and does not know (or
care) where it lands.

---

## 2. DATABASE — SCHEMA v3

Schema version moved **2 → 3** with exactly one registered, additive migration
step (`SpectaMigrations._steps[3]`). No existing table was altered, so an
installed v2 database upgrades in place.

New table: **`watch_progress`** (one row per playback identity).

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | the playback identity (see §3) |
| `media_key` | TEXT | parent work's 2C metadata key |
| `media_type` | TEXT | `movie` / `series` |
| `title` | TEXT | display title |
| `subtitle_line` | TEXT? | e.g. `Season 1 · Episode 2` |
| `season_number` | INTEGER? | series episodes only |
| `episode_number` | INTEGER? | series episodes only |
| `position_ms` | INTEGER | last observed position |
| `duration_ms` | INTEGER? | when the engine reported one |
| `elapsed_ms` | INTEGER | measured watch time |
| `completed` | INTEGER | 1 when playback reached the end |
| `updated_at` | DATETIME | last report time |

Migration discipline was honoured: the v3 step is registered (not implicit), a
v2 → v3 upgrade test exists, and the fresh-database path (`createAll`) and the
upgrade path produce the same column names (snake_case of the Dart getters).

### Design decision — one table, two queries

Continue Watching and History are **ordered queries over the single
`watch_progress` table**, not a duplicated `watch_history` table:

* Continue Watching = `completed = 0 AND position_ms > 0`, newest first.
* History = every row, newest first.

An append-only event table would have duplicated exactly the state that already
exists (one authoritative row per playback identity) and would have required a
session-boundary hook the 2E sink does not define. For a single-device local
library the two queries answer "what did I watch, in what order" without
inventing a second source of truth. A `favorites/watchlist` table was also not
added: there is no UI affordance to add to a watchlist, so creating the table
would have been storage without a feature (recorded as a known limitation).

---

## 3. IDENTITY — EPISODES CANNOT COLLIDE

Progress is keyed by the **same evidence-based identity the player already
uses** — nothing new was invented:

* movie    → `<mediaKey>`                             (e.g. `Dune|movie|2024`)
* episode  → `<mediaKey>|s<S>e<E>`                    (e.g. `Show|series|2024|s1e2`)

`mediaKey` is the 2C canonical metadata key (normalized title | type | year),
and the season/episode numbers are part of the primary key. A completed Episode
2 therefore writes to a different row than Episode 1 — verified in the DAO
tests and on device (`test/.../library_dao_test.dart`, P2F-2).

`PlaybackRequest` (2E) was extended with optional `mediaKey`, `mediaType`,
`seasonNumber`, `episodeNumber`; `playback_entry.dart` fills them from
`MetadataItem` and the targeted `SeriesEpisode`. `retry()` preserves them, so a
retry keeps the same progress identity.

The known limitation inherited from 2C remains: the metadata key is
evidence-based, not a globally unique provider id (no TMDB), so two different
works with identical normalized `(title, type, year)` would share a row.

---

## 4. THE SINK EXTENSION

`PlaybackProgressSink.report` gained **optional** descriptive parameters
(`duration`, `mediaKey`, `mediaType`, `title`, `subtitleLine`, `seasonNumber`,
`episodeNumber`). The four original parameters are unchanged, so every existing
caller (including the 2E device test and the in-memory sink) compiles as-is.

`PersistentPlaybackProgressSink`:

* maps one report onto one `WatchProgress` row;
* serialises writes through a single future chain, so a 1-second tick can never
  interleave two upserts (last write wins);
* contains every failure — persistence can never affect playback or reach the
  UI;
* treats an empty `targetKey` as "no identity" and drops the report rather than
  guessing one;
* reports an unknown duration as `null`, never as a fake zero.

`playbackProgressSinkProvider` now returns the persistent sink by default
(bound to `libraryStoreProvider`). Tests override it with the in-memory sink to
stay hermetic.

---

## 5. UI — REAL DATA ONLY

* **Library** (`library_view.dart`) now reads `continueWatchingProvider` and
  `watchHistoryProvider`: a Continue Watching section (with progress bar and
  remaining time) and a History section (completed items marked "Watched"), plus
  an honest empty state. D-pad focusable via `SpectaFocusWrapper`.
* **Home** Continue Watching rail reads the real store and falls back to the
  design fixture only when the library is empty (the other rails remain
  fixtures, as documented in 2A).

A `libraryRevisionProvider` counter is bumped after each successful write so
read providers refresh; the player writes while the Library/Home is off screen,
so no polling is needed.

---

## 6. BOUNDARIES HONOURED

* No 2G downloads, no download queue/worker/tables.
* No 2H catalogue, no `SPECTA-Extensions`, no runtime GitHub access.
* No schema change beyond the one additive v3 step.
* No new dependency.
* Extensions get **no** database access; the library remains a SPECTA core
  responsibility.
* Source validation and ranking are untouched; the player still consumes the
  2D pool and never re-ranks.
* No DRM/access-control/authentication bypass.

---

## 7. FILES

Added:

- `lib/core/database/tables/watch_progress_table.dart`
- `lib/core/library/watch_progress.dart`
- `lib/core/library/library_store.dart`
- `lib/core/library/library_dao.dart`
- `lib/core/library/library_providers.dart`
- `test/core/library/library_dao_test.dart`
- `test/core/playback/persistent_progress_sink_test.dart`
- `test/features/library/library_view_test.dart`
- `integration_test/phase2f_device_verification_test.dart`
- `docs/PHASE_2F_REPORT.md`
- `docs/evidence_p2f_device_run_2026-09-19.log`

Modified:

- `lib/core/database/migrations.dart` (schemaVersion 3 + registered step 3)
- `lib/core/database/specta_database.dart` (register the table)
- `lib/core/database/specta_database.g.dart` (regenerated by build_runner)
- `lib/core/playback/playback_progress_sink.dart` (extended seam + persistent impl)
- `lib/features/playback/playback_session_state.dart` (sink binding + identity)
- `lib/features/playback/playback_entry.dart` (pass identity)
- `lib/features/library/library_view.dart` (real data)
- `lib/features/home/home_view.dart` (real Continue Watching)
- `test/core/database/specta_database_test.dart` (schema v3 + v2→v3 upgrade test)
- `test/features/home/home_page_test.dart`, `test/features/playback/playback_session_state_test.dart`,
  `test/features/playback/playback_view_test.dart` (hermetic sink/store overrides)
- `PROJECT_STATE.txt`, `docs/PROJECT_STATE.txt`

Deleted: none.

---

## 8. TESTS

```
flutter analyze                          → No issues found
flutter test                             → 475 passed, 9 skipped, 0 failed
bash tool/run_tests_real_js.sh           → 484 passed, 0 skipped, 0 failed
flutter test integration_test/phase2f_device_verification_test.dart -d R83L20FRDFM
                                         → 2/2 passed, 0 failed
```

New Phase 2F coverage:

* **`library_dao_test.dart`** — round-trip, in-place update (one row per
  identity), episode collision safety (s1e1 vs s1e2), Continue Watching
  filtering/ordering, History ordering incl. completed, remove/clear, and a
  duration-free row reporting `fraction == null` rather than a fake value.
* **`persistent_progress_sink_test.dart`** — report → row mapping, serialised
  rapid writes (last wins), empty key dropped, storage failure contained without
  blocking later writes, missing title tolerated, `onChanged` fired.
* **`specta_database_test.dart`** — schema version 3 and a **v2 → v3 upgrade
  test** that opens a database built with the real v2 DDL, verifies the
  pre-existing settings row survives, and that `watch_progress` is usable.
* **`library_view_test.dart`** — empty state, real Continue Watching + History
  rendering, completed marked, episode line shown.

---

## 9. DEVICE VERIFICATION

```
Harness   flutter test integration_test/phase2f_device_verification_test.dart -d R83L20FRDFM
Device    Samsung SM-A065F (Galaxy A06), Android 16 (API 36)
Result    2/2 PASS

P2F-1  on-device PRAGMA user_version = 3
       settings_entries reachable after upgrade
       watch_progress reachable after upgrade
P2F-2  persistent sink wrote real progress to the device database
       continue watching rows present: [__p2f_test__|movie|2026,
                                        __p2f_test__|series|2026|s1e2]
       verification rows removed
```

Raw log: `docs/evidence_p2f_device_run_2026-09-19.log`. The migration ran
against the real installed database, not a fresh in-memory one. Verification
rows are namespaced `__p2f_test__` and removed at the end.

---

## 10. BUILD

```
flutter build apk --debug → SUCCESS
build/app/outputs/flutter-apk/app-debug.apk
277,511,502 bytes — 2026-09-19 03:48 (Gradle assembleDebug 165.0 s)
```

---

## 11. KNOWN LIMITATIONS

* Library/Home items **display** progress but do not **resume**: opening one
  would require a metadata-by-key lookup the architecture does not have yet
  (metadata is in-memory until a later phase). Recorded honestly rather than
  faked with a title search.
* No watchlist/favorites table or UI (no affordance exists to populate one).
* History is a per-identity view over `watch_progress`, not an append-only event
  log; re-watching updates the same row's `updated_at`.
* The evidence-based metadata identity can collide for identical normalized
  `(title, type, year)` — inherited from 2C, no global provider id exists.
* Latent inconsistency noted (not introduced, not fixed here): the Phase 1
  migration DDL writes `DEFAULT CURRENT_TIMESTAMP` for DATETIME columns while
  Drift stores integer timestamps. It never fires because Drift always supplies
  those columns explicitly; the new `watch_progress.updated_at` has no SQL
  default at all, so 2F is unaffected. Flagged for a future hygiene pass.
* Library latency: reads happen when the surface is built and refresh on write;
  there is no background sync.

---

## 12. NEXT BOUNDARY

Phase 2G (download foundation) or a 2F follow-up (resume-by-key) — only on
explicit authorization. 2G, 2H, `SPECTA-Extensions`, and TMDB remain NOT
started.
