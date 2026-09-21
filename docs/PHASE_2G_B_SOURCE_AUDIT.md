# SPECTA — PHASE 2G-B FINAL SOURCE AUDIT
## Forensic Verification Before Phase 2G-C (2026-09-20)

Audit gate between 2G-B (download domain/orchestration) and 2G-C (real engine).
Every claim below was verified against the actual source, not the reports.
One genuine 2G-B defect was found and fixed (§I); everything else passed.

---

## A. Repository state

```text
branch:         master
HEAD:           7fcb0cc (INTERNET permission + investigation report)
working tree:   pre-audit CLEAN; now carries exactly two audit modifications
                (the §I defect fix + its regression test — see §M)
Flutter/Dart:   3.47.4 / 3.13.3
```

## B. Source files inspected (read in full)

- `lib/core/downloads/`: download_manager.dart (941→951 lines),
  download_models.dart (601), download_engine.dart (81), download_dao.dart
  (113), download_store.dart (26), download_retry_policy.dart (74),
  download_providers.dart (233), device_environment.dart (65)
- `lib/core/database/`: specta_database.dart, tables/downloads_table.dart,
  migrations.dart (v5 step verified), specta_failure.dart (failure section)
- Tests: all 6 files under `test/core/downloads/` (manager 38 tests, models,
  DAO, persistence-contract, providers, retry-policy) plus
  `test/support/fake_download_engine.dart`

## C. Persistence contract verification

| Requirement | Verdict | Evidence |
|---|---|---|
| Single source of truth | **PASS** | Manager's maps are declared mirrors; `store.upsert` is the only write path; `DownloadDao` is the only store impl |
| Survives restart (identity, state, order, attempts, failure, progress, paths, provenance, timestamps) | **PASS** | All map 1:1 onto `Downloads` columns; contract tests reopen a real SQLite file and reconstruct |
| Queue ordering from persistence | **PASS** | `DownloadDao.all()` orders by `createdAt` ASC in SQL; pump consumes in that order; restart-order test passes |
| No engine artifacts as identity/state | **PASS** | No task-ID/plugin-type column exists; `DownloadAttemptInput.downloadId` is SPECTA's identity, in-memory; engine never issues identity |
| URL never authoritative | **PASS** | No URL column; `sourceExtensionId`/`sourceReference` provenance only; the resolved URL lives only in `DownloadAttemptInput.url` (in-memory, attempt-scoped, documented "never persisted as identity") |
| `.part` path derived, not stored | **PASS** | `downloadPartPathFor(filePath)` — pure derivation; table comment documents the discipline |
| Persist-before-engine (§5) | **PASS** | `_pump()` upserts `downloading` before `_startAttempt`; `pause()` persists then asks the engine |
| Reconciliation seam without replacing authority | **PASS** | `engine.isTransferActive` consulted at startup; SPECTA record still wins (manager reclassifies when engine holds nothing) |
| Idempotency | **PASS** | Upsert PK = identity; duplicate-completion/cancel-after-complete paths guarded by state checks |
| Atomic logical updates | **PASS** | Each transition is one `copyWith` → one upsert (status+attempt+timestamps+failure together) |
| Progress coalescing (§10) | **PASS** | `DownloadProgressPersistPolicy` (256 KiB / 2 s), pure and unit-tested; transitions bypass it |
| Terminal non-resurrection (§11) | **PASS** | Two layers (§D below); `completed` has an empty transition set |

## D. DownloadManager verification

- **Queue** — FIFO via SQL `createdAt` ordering; deterministic; survives
  recreation (test: write → dispose → new manager → same order). The pump
  runs inside the serialized chain, so overlapping triggers (enqueue /
  completion / cancel / retry / resume) cannot double-start, exceed the
  limit, or interleave transitions. Duplicate-start test and
  repeated-pump-trigger tests pass.
- **Concurrency** — default 3, ceiling 9; `_clampConcurrency`: <1 → default 3,
  >9 → 9; **never unlimited**; `updateConcurrency` re-pumps; the manager (not
  the engine) is the sole authority (max-attempts counter tests prove the
  engine never sees more than the limit).
- **State machine** — every transition in `DownloadStateMachine._allowed`
  verified against the prompt's list; `paused → queued` is documented
  (resume-at-capacity fairness); all invalid transitions rejected; the
  exhaustive-switch model test covers the full matrix; terminal protection
  (`completed`/`cancelled` vs stale events) tested.
- **Stale-event protection** — two layers confirmed in source: (1) attempt
  epoch (`_activeEpoch[id] != epoch` → ignore); (2) persisted-state guard
  (result must land on the state it claims: `completed` only onto
  `downloading`, `paused` only onto `paused`, etc.). Critically, the epoch
  slot is freed BEFORE the state guard so a stale result can never leak a
  concurrency slot (the 2G-B fix, verified intact).
- **Retry** — budget 3 (`shouldAutoRetry` = retryable && attemptsUsed < 3);
  exponential 2 s base, hard cap 60 s, shift clamped 0..30 (no overflow);
  injectable `DownloadClock`; tests use virtual time (zero real waiting);
  auto path keeps the budget, manual retry/enqueue resets it deliberately;
  requeue re-checks the record is STILL `failed` (no retry after
  cancel/remove/complete).
- **Restart** — `initialize()` asks the engine for each persisted
  `downloading` record; engine-active → left for 2G-C adoption; engine
  without the transfer → honest `interrupted` failure → bounded auto-retry;
  then `_pump()` resumes scheduling. No blind assumptions either way.
- **User actions** — pause (persist→engine), resume (slot-aware; queued when
  at capacity), cancel (idempotent, terminal-protected, engine called only
  when an attempt exists, re-pumps), remove (idempotent, returns existence
  honestly, cancels a live attempt, forgets the session pool, re-pumps).

## E. DownloadEngine verification

`abstract interface class DownloadEngine` — SPECTA-owned, sealed event set,
one terminal `DownloadAttemptResult` per `start`, pause/cancel by SPECTA
identity, `isTransferActive` reconciliation seam. Zero third-party types
(pubspec verified: no downloader dependency). The contract is realistic for
`background_downloader`: start/pause/cancel map directly; progress maps to
the event stream; task-IDs can stay inside the adapter (the adapter holds the
taskID→downloadId map; no schema change is forced). 2G-C note: pause/resume
mapping is the one place where `background_downloader`'s task model may
require an adapter-side `resumeFrom` re-start rather than a true pause — the
interface already supports this honestly (`resumeFrom` is in the input).

## F. Database verification

- Schema v5; `Downloads` registered in `SpectaDatabase`; `SpectaMigrations`
  v4→v5 step creates the table additively.
- Migration test builds the real v4 schema with raw DDL, inserts real rows
  (settings/watch_progress/media_references), stamps `user_version = 4`,
  opens through the real database, verifies data survives verbatim, and
  proves `downloads` usable through `DownloadDao`. Fresh-install path also
  tested.
- DAO: single-row `insertOnConflictUpdate` on the identity PK; SQL-only
  ordering; defensive code decoding (`fromCode` fallbacks, never a crash on
  one bad row). Generated `specta_database.g.dart` is consistent with the
  table (analyzer + codegen reproducibility previously verified).
- Store binding: `DownloadDao` provided via `downloadStoreProvider`;
  tests use real file-backed SQLite through the same provider graph.

## G. Provider verification

All eleven exist and were behavior-tested (not existence-tested): store
binding, engine seam (honest throw — nothing reads the manager in the
shipping app), revision counter (bumped by `onChanged` after every persisted
change), media-directory seam, manager (restore of persisted concurrency,
clamped), all/queued/active/paused/completed/failed/cancelled filters,
by-identity family, `activeCount` (documented as in-memory attempt truth, NOT
persisted `downloading` rows), queue status (counts + concurrency). Filters
derive from the real store; no fabricated state. Awaiting `.future`
determinism is enforced in tests.

## H. Test-quality verification

The tests exercise real behavior: real SQLite files (write→close→reopen),
max-attempts counters over the fake engine, FIFO in-flight scripting for
stale-result races, virtual-time backoff, provider graphs overridden only at
the three seams (db path, engine, environment). No constant-only assertions
found; where test expectations initially contradicted documented behavior
(2G-B session), the TESTS were corrected to the architecture, not the
architecture to the tests. One test-quality gap was found in THIS audit: the
duplicate-requeue tests never varied the pool, which is exactly how the §I
defect survived — closed by the new regression test.

## I. Defects found

**1 defect found, fixed, and regression-tested:**

- **Location:** `DownloadManager.enqueue`, requeue branch
  (`failed`/`cancelled` → `queued`).
- **Problem:** the branch persisted the requeued record but never called
  `session.remember(request.id, request.pool)` — unlike the new-record path.
- **Impact:** a user re-requesting a failed/cancelled download caused the
  next attempt to consume the FIRST request's stale pool (or no pool at all
  when the first enqueue never started an attempt, e.g. `unsupportedSource`
  → attempt fails `sourcesExhausted` with the user's fresh resolution inputs
  ignored). SPECTA state stayed consistent, but recovery silently reused
  dead resolution inputs — a genuine correctness gap against the recovery
  seam's intent ("recovery re-resolves through SPECTA's existing layers"
  with the user's current inputs).
- **Fix:** remember the fresh request's pool in the requeue branch (2 lines,
  mirroring the new-record path).
- **Test added:** `re-request after failure re-resolves against the FRESH
  pool, not the stale one captured at first enqueue` — fails a download
  against a dead server, re-requests with a different mirror URL, asserts
  `engine.startedInputs.last.url == freshUrl`. Fails without the fix, passes
  with it.

No other Phase 2G-B defects found.

## J. 2G-C readiness

**READY FOR PHASE 2G-C.**

The approved architecture is implemented as specified, the persistence
contract holds at source level in every clause, the engine interface is
adapter-realistic, the one correctness defect in the recovery path is fixed
and test-proven, and the full validation suite is green.

## K. Remaining risks for 2G-C (from source, not guesswork)

1. **Reconciliation field:** `background_downloader`'s taskID must live
   inside the adapter (taskID→downloadId map). If a future engine cannot
   hold that mapping durably itself, an explicit nullable reconciliation
   column becomes necessary — a schema decision to take only when proven
   (per the 2G-A decision).
2. **Pause/resume mapping:** the adapter may implement pause as
   settle+`resumeFrom` restart; the interface already expresses this, but
   byte-identity of "paused" bytes must be verified on device.
3. **Progress semantics:** `bytesOnDisk`/`totalBytes` are sufficient; the
   adapter must report bytes actually flushed, not buffered.
4. **Range/ETag validation** is not yet representable (no checksum field) —
   fine for V1, worth revisiting when real transfers exist.
5. **Failure expressiveness** is adequate (`networkError`/`timeout`/
   `serverError`/`httpError`/`invalidResponse`/`storage*`/`interrupted`/
   `engineFailure`); the adapter must map platform exceptions honestly into
   these rather than over-using `engineFailure`.
6. **Session resolver** (`SessionDownloadSourceResolver`) is 2G-B-honest but
   means post-restart attempts fail `sourcesExhausted` until 2G-C implements
   real re-resolution through the SourceManager — expected, documented, and
   already covered by tests.
7. Native `device_environment` channel still missing → conservative network/
   storage gating on device until implemented (2G-D scope).

## L. Exact validation results

```text
flutter analyze:  No issues found
flutter test:     618 passed, 9 skipped, 0 failed   (+1 new regression test)
real JS tests:    627 passed, 0 skipped, 0 failed   (tool/run_tests_real_js.sh)
Android build:    flutter build apk --debug → SUCCESS
```

## M. Git state

```text
No commit, no push (per §18).
Pre-audit tree:           CLEAN (HEAD 7fcb0cc)
This audit's changes:     lib/core/downloads/download_manager.dart (§I fix),
                          test/core/downloads/download_manager_test.dart (§I test)
Pre-existing work:        none was dirty; nothing destroyed
```

## N. Stop

Stopping here per the stop condition: no `background_downloader`, no adapter,
no real transfer, no 2G-C work started. Awaiting explicit authorization.
