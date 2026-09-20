# SPECTA — PHASE 2G-B REPORT
## Download Manager, Queue & Providers

Status: **COMPLETE (uncommitted work; no commit/push made, per the task rules).**
Head at completion: `4d7f4da` — unchanged from the 2F baseline.
Flutter/Dart: 3.47.4 / 3.13.3.

Baseline entering 2G-B: analyze clean; 557 passed, 9 skipped; real JS 566.
Baseline leaving 2G-B: analyze clean; **617 passed, 9 skipped, 0 failed**;
real JS **626 passed, 0 skipped, 0 failed**; Android debug APK build SUCCESS.

---

## 1. Implementation summary (all items exist AND are tested)

| Item | File | Detail |
|---|---|---|
| **DownloadManager** | `lib/core/downloads/download_manager.dart` (941 lines) | FIFO queue pump; concurrency 3 default / 9 max (clamping: ≤0 → default 3, >9 → 9); **persist-before-engine** ordering (Persistence Contract §5); chained-future serialization (no overlapping pumps); state-machine enforcement (no bypass); pause/resume/cancel/retry/remove; documented duplicate-request semantics; two-layer stale protection (attempt epoch + persisted-state guard); startup reconciliation through the engine seam; coalesced progress persistence; session source-recovery seam; storage pre-flight seam |
| **DownloadEngine interface** | `download_engine.dart` | SPECTA-owned: start/pause/cancel, sealed progress events, terminal attempt result kinds, `isTransferActive` reconciliation seam. **Zero third-party types.** |
| **Retry policy + clock** | `download_retry_policy.dart` | Bounded budget (3 attempts), exponential backoff 2s → cap 60s, injectable `DownloadClock` (virtual time in tests — no real waiting, ever) |
| **Riverpod providers** | `download_providers.dart` | Store binding, honest unconfigured engine seam (throws until 2G-C provides an adapter), revision-based per-status filters (all/queued/active/paused/completed/failed/cancelled), by-identity family, queue status, active count, overridable media-directory seam, persisted concurrency restore |
| **Fake engine / clock** | `test/support/fake_download_engine.dart` | Deterministic scripted outcomes, FIFO in-flight model for stale-result races, contract-violation throws, virtual-time clock |
| **Tests** | `test/core/downloads/` (6 files, ~4,700 lines total) | 60 new tests in 2G-B: manager 38, providers 9, retry policy 13 |

Also in `lib/core/downloads/`: `download_models.dart` (state machine, identity,
network policy, attempt input; `paused → queued` transition added and
documented for resume-at-capacity), `download_dao.dart`, `download_store.dart`,
`device_environment.dart` (from 2G-A).

### Bugs found & fixed during 2G-B

1. **Concurrency slot leak** — `_reconcileResult` early-returned on stale states
   without freeing the finished attempt's slot; the queue could deadlock at full
   concurrency forever. Restructured: the attempt always finishes when its
   terminal result arrives; only state application is guarded.
2. **Queue stall** — freeing a slot via `pause()`/`cancel()`/`remove()` never
   re-triggered the pump. All three now re-pump.
3. **Duplicate enqueue bypassing the machine** — the failed/cancelled requeue
   path skipped `canTransition`; aligned with machine-allowed transitions.
4. **`cancel()` honesty** — no `engine.cancel` call for queued jobs (no transfer
   exists to cancel).
5. **At-capacity marking** — the `waitingForSlot` marking pass ran inside the
   pump's `while` loop and never executed when already at capacity; moved after
   the loop.
6. Mechanical: Riverpod 3 family syntax (`FutureProvider.family` +
   `package:riverpod/misc.dart`), const-assert in the retry policy, and the
   `verdict.allowed` → `isAllowed` rename.

## 2. Behavior decisions (documented, tested)

- **Duplicate requests:** queued/active/paused/completed → no second record;
  failed → requeue while retry budget remains; cancelled → explicit re-request
  creates a fresh record (identity upsert).
- **Network policy:** the manager consults `NetworkPolicyVerdict`; when network
  state is unknown it is **conservative** — downloads are not silently started.
  Tests cover the blocked case explicitly.
- **Startup reconciliation:** a persisted `downloading` record after process
  death is NOT assumed active and NOT blindly failed; the engine seam
  (`isTransferActive`) is consulted, and without an engine the record is
  honestly reclassified `interrupted` and handled by the retry policy. Real
  engine reconciliation policy belongs to 2G-C.
- **Queue state visibility:** queued items beyond capacity are marked with an
  honest `waitingForSlot` reason instead of appearing silently stalled.

## 3. Verification

```text
flutter analyze:  No issues found
flutter test:     617 passed, 9 skipped, 0 failed   (baseline 557+9sk → +60, 0 regressions)
real JS tests:    626 passed, 0 skipped, 0 failed   (tool/run_tests_real_js.sh)
Android build:    flutter build apk --debug → SUCCESS
Device:           NOT RUN this phase (no device attached; no product path from
                  the UI reaches the manager yet — the engine seam intentionally
                  throws until 2G-C)
```

Phase 2F regression: none — the 2F watch-progress / resume-by-key / library /
history suites all pass unchanged within the totals above.

## 4. Explicit non-implemented items (phase boundary)

No real media downloading; no HTTP transfer; no `background_downloader`
dependency (pubspec unchanged — verified); no `.part` writing; no Range
requests; no real resume transfer; no WorkManager; no foreground service; no
native network/storage channels; no Android download notifications; no source
refresh implementation; no real engine reconciliation; no offline playback; no
HLS offline; no download UI; no device validation of real downloads.

## 5. Architecture verification

```
SPECTA Database (authoritative)
       ↓
DownloadManager          ← zero imports of any downloader package
       ↓
DownloadEngine interface ← SPECTA-owned, sealed, typed
       ↓
future adapter (2G-C)
```

1. `DownloadManager` does not depend on `background_downloader` — confirmed by
   pubspec and import audit.
2. No third-party downloader types leak into the domain.
3. SPECTA persistence remains authoritative (contract tests re-verified).
4. Streaming URLs are not authoritative download identity (no URL column is
   persisted; provenance only).
5. Engine state is not required to reconstruct SPECTA state.
6. Terminal states are protected from stale callbacks (attempt epoch +
   persisted-state guard, tested).
7. Queue/concurrency are controlled by SPECTA, not the engine.
8. The engine remains replaceable — the only engine implementation is the test
   fake.

## 6. Known risks / follow-up for 2G-C

- Real adapter contract surface vs `background_downloader`'s task model; an
  engine-reconciliation field may become necessary (schema change).
- `.part` transfer, Range/ETag validation semantics.
- Source refresh integration through SourceManager on expired URLs.
- Network-type changes mid-transfer; storage pre-flight accuracy on SD volumes.
- Progress persistence frequency tuning on real hardware.
- OEM background restrictions and notification policy.
- `device_environment` native channel (`net.specta.app/environment`) must be
  implemented for real network/storage gating.

## 7. Next phase

**2G-C** — `background_downloader` adapter behind `DownloadEngine`, real
progressive MP4 transfer, `.part` handling, Range resume, source
refresh/recovery via SourceManager, engine-state reconciliation.
Not started; awaits explicit authorization.

## 8. Verdict

```text
PHASE 2G-B: COMPLETE
SPECTA now owns the download domain and orchestration.
The future engine remains replaceable. No real downloading happens yet.
```
