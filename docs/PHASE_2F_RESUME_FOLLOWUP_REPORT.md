# SPECTA — PHASE 2F RESUME-BY-KEY FOLLOW-UP REPORT

**Scope:** make persisted Continue Watching / Library / History items re-open
through the existing playback pipeline.
**Status:** COMPLETE — analyze clean, 503 tests + 512 with the real JS bridge,
3/3 REAL DEVICE, debug APK builds.
**Date:** 2026-09-19
**Base:** commit `2988cf3` (Phase 2F)
**Boundary:** this follow-up only. Phase 2G (downloads) and 2H (catalogue) were
NOT started, and no architecture was redesigned.

---

## 1. PROBLEM

Phase 2F persisted watch progress correctly, and Library/Home displayed it, but
an item could not be *opened*: there was no reliable way to turn a persisted
identity back into a `MetadataItem` + `DiscoveryItem` for `startPlayback`.

## 2. FORENSIC FINDINGS

Baseline: git clean at `2988cf3`, `flutter analyze` clean, 475 passed / 9
skipped / 0 failed. No unexpected work.

**Current durable identity.** `MetadataItem.key` (and therefore
`WatchProgress.mediaKey`) is produced by
`MetadataManager.identityKey(normalizedTitle, type, year)`:

```
<keyTitle(normalizedTitle)>|<type.code>|<year or "none">
```

where `keyTitle` lowercases, replaces every non-`\w`/space character with a
space, collapses whitespace and trims. `type.code` is `movie`/`series`; the
year part is digits or `none`.

This identity is **deterministic** and — importantly — **self-describing**: the
`|` separator can never occur inside a part because `keyTitle` strips it, so
the key can be parsed back exactly. It survives process restart because it is
stored, and it is safe for resume because it is reproducible.

**The broken boundary.** `MetadataManager.metadataFor` requires a
`DiscoveryItem` — i.e. the work's **discovery references** (extensionId + the
extension-internal URL it expects back through `details(url)`). Phase 2F
persisted the key but **not** the references, so `metadataFor` could not be
re-run. The only alternative was a title search, which is a heuristic that can
resolve the wrong media. That was the break.

**Playback path (actual):**

```
Home / Library item
  ↓  (previously: nothing — no handler)
resumeWatchProgress
  ↓  rebuild DiscoveryItem from the stored key + stored references
MetadataManager.metadataFor  → canonical MetadataItem
  ↓  select the exact SeriesEpisode (season AND episode number)
startPlayback  (UNCHANGED 2E entry)
  ↓  SourceSession → SourceManager → SourceValidator → SourceRanker → SourcePool
PlaybackSessionNotifier.open(..., startPosition)
  ↓
Phase 2E MediaKit player
  ↓
PersistentPlaybackProgressSink → watch_progress
```

## 3. SOLUTION (smallest safe)

**Persist the exact discovery provenance, and reconstruct the identity from the
key — no new identity system, no title search, no stored source URLs.**

1. **Schema v4 — `media_references(media_key, ordinal, extension_id,
   reference_url)`.** One additive, registered migration step. It stores the
   references discovery already produced (reusing the discovery layer's
   `DiscoveryReference` — no second reference model). `saveReferences` REPLACES
   a work's set, so a work always resolves through the references its most
   recent playback actually used.
2. **`discoveryItemFor(progress, references)`** parses the self-describing key
   back into `(normalizedTitle, type, year)` and rebuilds the `DiscoveryItem`.
   Because `keyTitle` is idempotent on an already-normalized title, the
   metadata layer reproduces the **same** key — verified by a round-trip test.
3. **`resumeWith(...)`** loads provenance, rebuilds the item, re-runs the
   metadata layer, selects the episode, and calls the caller-supplied starter —
   in production the unchanged `startPlayback`.
4. **`startPlayback` now stores provenance** (`item.references` under
   `metadata.key`) and accepts an optional `startPosition`.
5. **`PlaybackRequest.startPosition`** + a one-time seek in the session, applied
   when the first candidate first becomes playable (so a fallback still gets
   the seek, and media is flowing before the seek is issued).

### Alternatives considered

* **Re-discover by title** — no schema change, but a heuristic that can resolve
  the wrong media and depends on search returning the item. Rejected as unsafe.
* **Store a metadata JSON blob** — explicitly discouraged, and would duplicate
  state the metadata layer already owns. Rejected.
* **New identity system / provider ids (e.g. TMDB)** — a separate architectural
  task, not a follow-up. Rejected here (documented boundary).

### Why it is safe

* Identity is reproduced exactly, not approximated.
* Provenance is preserved, and sources are always re-resolved through the
  current SourceManager — no stale URL is ever reused.
* The episode is matched on **season AND episode number**, so S1E2 can never
  resolve to S1E1 or S2E1.
* Failure is structured and honest — nothing is fabricated or crashed into.

## 4. IDENTITY COLLISION (reported, not hidden)

The 2F limitation stands: two *different* works with identical normalized
`(title, type, year)` share a key, and would therefore share one
`watch_progress` row and one reference set — the **last-played provenance
wins**. This is inherent to the 2C evidence-based identity and is unchanged by
resume: resume resolves strictly through the stored key + references of that
row, never by title, so it cannot pick a work that was not already conflated by
persistence itself. A stricter identity (provider ids) is a separate
architectural task and was NOT attempted here. Recorded as a known limitation.

## 5. DATABASE

* **Before:** schema v3 — `watch_progress` (2F).
* **After:** schema v4 — plus `media_references`.
* **Migration required: yes** — registered additive step `4`; fresh-DB
  (`createAll`) and upgrade paths produce identical column names. Existing
  `watch_progress` data is untouched. A v2 → v4 upgrade test verifies
  pre-existing settings survive and both new tables are usable.

Items persisted before this follow-up have no stored references, so they fail
resume **honestly** ("can no longer be resolved") until played again — no fake
resolution.

## 6. TESTS

```
flutter analyze           → No issues found
flutter test              → 503 passed, 9 skipped, 0 failed
tool/run_tests_real_js.sh → 512 passed, 0 skipped, 0 failed
device test (SM-A065F)    → 3/3 passed, 0 failed
flutter build apk --debug → SUCCESS
```

New coverage (`test/features/playback/resume_entry_test.dart`,
`test/core/library/library_dao_test.dart`, session + view tests):

* identity reconstruction for a movie, and the key round-trip;
* `none`-year round-trip; malformed identity refused (wrong part count,
  non-numeric year, unknown type);
* episode selection S1E1 / S1E2 / S2E1 kept distinct, and a vanished episode;
* resume position: stored position resumed, completed restarts, zero → no seek;
* the session seeks exactly once, only when playable, and on a fallback too;
* provenance is handed fresh to the pipeline (no stored source URL);
* honest failures: no provenance, metadata null, metadata throwing — none call
  the starter;
* the Library tile tap surfaces the honest failure message;
* `media_references` store/order/replace/per-key isolation on device.

## 7. DEVICE

```
Harness  flutter test integration_test/phase2f_device_verification_test.dart -d R83L20FRDFM
Device   Samsung SM-A065F, Android 16 (API 36)
Result   3/3 PASS
P2F-1  on-device PRAGMA user_version = 4; settings_entries, watch_progress and
       media_references all reachable after the migration
P2F-2  persistent sink wrote + read real progress; episode identity preserved
P2F-3  durable resume provenance round-tripped on device
```
Log: `docs/evidence_p2f_resume_device_run_2026-09-19.log`.

## 8. BUILD

`flutter build apk --debug` → SUCCESS, `build/app/outputs/flutter-apk/app-debug.apk`,
277,535,750 bytes, 2026-09-19 04:21 (Gradle assembleDebug 209.1 s).

## 9. FILES CHANGED

Added: `lib/core/database/tables/media_references_table.dart`,
`lib/features/playback/resume_entry.dart`,
`test/features/playback/resume_entry_test.dart`,
`docs/PHASE_2F_RESUME_FOLLOWUP_REPORT.md`,
`docs/evidence_p2f_resume_device_run_2026-09-19.log`.

Modified: `lib/core/database/{migrations,specta_database,specta_database.g}.dart`,
`lib/core/library/{library_store,library_dao}.dart`,
`lib/features/playback/{playback_entry,playback_session_state}.dart`,
`lib/features/library/library_view.dart`, `lib/features/home/home_view.dart`,
`integration_test/phase2f_device_verification_test.dart`,
`test/core/database/specta_database_test.dart`,
`test/core/library/library_dao_test.dart`,
`test/core/playback/persistent_progress_sink_test.dart`,
`test/features/playback/playback_session_state_test.dart`,
`test/features/library/library_view_test.dart`,
`test/support/in_memory_library_store.dart`, `PROJECT_STATE.txt`,
`docs/PROJECT_STATE.txt`, `README.md`, `docs/README.md`.

Deleted: none.

## 10. SECURITY

No schema data is exposed to extensions; no source URLs are persisted; no new
dependency; no credentials; no runtime GitHub access; no `SPECTA-Extensions`.
Extension/foundation boundaries untouched.

## 11. KNOWN LIMITATIONS

* Identity collision (see §4) — pre-existing, unchanged.
* Resume requires stored provenance; pre-follow-up rows fail honestly until
  replayed.
* Resume re-fetches metadata/sources every time (by design): it is slower than a
  cached open but never serves stale sources.
* No watchlist/favorites (unchanged from 2F).

## 12. NEXT BOUNDARY

Phase 2G (download foundation) — NOT started, needs explicit authorization.
Phase 2H (extension catalogue) — NOT started.
