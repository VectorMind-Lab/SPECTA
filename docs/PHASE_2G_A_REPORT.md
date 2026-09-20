# SPECTA — PHASE 2G-A REPORT
## Download Architecture Evaluation & Foundation Stabilization

Status: **COMPLETE (uncommitted work, preserved in the working tree).**
Head at completion: `4d7f4da` (`fix(phase2f): add durable resume by media key`) — unchanged;
no commit and no push was made during 2G-A, per the task's stop condition.

Baseline entering 2G-A: flutter analyze clean; 503+9 skipped; real JS 512 passed.
Baseline leaving 2G-A: flutter analyze clean; 557 passed, 9 skipped; real JS 566 passed.

---

## 1. What was found (forensic audit)

The working tree contained pre-existing uncommitted Phase 2G-looking work:
schema v5 migration files, `lib/core/database/tables/downloads_table.dart`, and
an untracked `lib/core/downloads/` directory. The audit classified this as
**PARTIAL_PHASE_2G_WORK**: the persistence shape was legitimate and aligned with
the SPECTA architecture, but had four defects and zero 2G-specific tests.

## 2. Corrections completed

1. **Failure model (4.1)** — `DownloadFailureType` + `DownloadFailure` moved from
   `download_models.dart` into `lib/core/errors/specta_failure.dart`, beside every
   other `SpectaFailure` subtype (`ExtensionFailure`, `PlaybackFailure`,
   `StorageFailure`, `CapabilityFailure`). Same constructor shape and
   `toDiagnostics()` convention. `SpectaFailure` remains **sealed**; download
   failures now participate in its exhaustiveness guarantee (proven by a test
   switching over all subtypes). Nothing was weakened.
2. **Network policy naming (4.2)** — `NetworkPolicyVerdict.allowed` getter renamed
   to `isAllowed` (the enum constant `allowed` is untouched); all references updated.
3. **Analyzer issues (4.3)** — unused import removed; initializing-formal lints
   fixed; no lints suppressed. `download_dao.dart` gained the required
   `specta_failure.dart` import after the failure-model move.
4. **Migration (4.4)** — stale `schemaVersion == 4` assertions updated to v5 **and**
   a real v4→v5 migration test added: the exact on-disk v4 schema is built with raw
   DDL, real settings/watch_progress/media_references rows are inserted,
   `user_version = 4` is stamped, the real `SpectaDatabase` opens and migrates, and
   the rows are verified to survive verbatim before the `downloads` table is proven
   usable through `DownloadDao`. A separate fresh-install test proves the
   `createAll()` path produces the same usable table. Existing migration history
   untouched.

## 3. Persistence Contract

The user-authored Persistence Contract was audited clause-by-clause (§1–§13) and
implemented at every layer that exists without a manager/engine:

- **§1 Single source of truth** — `DownloadStore`/Drift is the only persistence.
- **§2 Survives restart** — every required fact maps to a persisted column. The
  one genuine gap found and fixed: the `.part` path was documented intent with no
  code. Added the pure helper `downloadPartPathFor(filePath)` (derived, never stored).
- **§3 No engine artifacts** — no engine/task IDs exist anywhere in the model.
- **§4 Source URL rule** — no streaming URL is persisted; provenance only.
- **§5–§11 (manager obligations)** — persist-before-engine, reconciliation,
  idempotency, atomic updates, progress coalescing, terminal non-resurrection are
  assigned to 2G-B and are precisely restated there.
- **§12 Contract tests** — 7 persistence-contract tests run against a **real
  SQLite file** (write → close → reopen → reconstruct): all six states survive
  recreation with attempt/failure/progress/timestamps; identity + display
  metadata + provenance + paths reconstruct with **no engine artifact**; queue
  ordering (FIFO) survives; duplicate identity stays one record across
  recreation; single-upsert atomicity; terminal records cannot be resurrected
  (`completed`/`cancelled` have no outgoing transitions); repeated store
  initialization is safe.

## 4. Download architecture decision (approved by the user)

Evaluated: custom downloader / Flutter download packages / native Android
(WorkManager, DownloadManager, Media3) / hybrid. **Recommendation, accepted:**

```
SPECTA DownloadManager        (SPECTA-owned: queue, state, retry, identity)
        ↓
DownloadEngine interface      (SPECTA-owned abstraction)
        ↓
background_downloader adapter (replaceable engine, 2G-C)
```

- **MP4-only for V1.** Progressive MP4 downloads as a normal file, playable
  offline through the existing MediaKit path. HLS offline downloading is
  explicitly **future work** — an `.m3u8` URL is not a downloadable movie file.
- The engine is replaceable; SPECTA state is not.

## 5. Test results

```text
flutter analyze:  No issues found
flutter test:     557 passed, 9 skipped (real-engine group, no JS bridge on PATH), 0 failed
real JS tests:    tool/run_tests_real_js.sh → 566 passed, 0 skipped, 0 failed
```

New 2G-A coverage (~47 tests): download identity (movie/episode key format
equality with the 2F key shape, collision impossibility, `isEpisode`), the full
state-machine transition matrix, failure-model integration, network-policy
naming/behavior, file-stem derivation, schema v5, the real v4→v5 migration, and
the persistence contract.

## 6. Device environment channel

`device_environment.dart` declares the intended native channel
(`net.specta.app/environment`) but the native side is deliberately deferred.
Everything it returns is nullable; the download stack must treat
unknown network/storage conservatively until the channel exists (2G-D).

## 7. Final verdict

```text
FOUNDATION READY FOR DOWNLOAD IMPLEMENTATION
```

No DownloadManager, engine, package, UI, or commit was created in 2G-A.
