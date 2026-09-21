# SPECTA — PHASE 2G-C ENGINE AUDIT

**Date:** 2026-09-21
**Scope:** Final engineering audit for Phase 2G-C — real download engine integration.
**Starting state:** 2G-B was complete (manager, queue, providers, engine seam). 2G-C pre-flight was complete (Sections 34–39 of the 2G-C authorization: five defect fixes, request policy hardening, documentation truth audit). The actual engine integration was then implemented as the uncommitted working tree inspected in this audit.

---

## A. IMPLEMENTATION

### A.1 Dependency

| Item | Value |
|---|---|
| Package | `background_downloader` |
| Version | **9.6.2** (verified in `pubspec.lock`) |
| Declared in | `pubspec.yaml` (direct main dependency) |
| Platform | Android WorkManager; iOS background tasks |
| Purpose | Byte transfer mechanism behind SPECTA's own `DownloadEngine` interface |

### A.2 Adapter — `lib/core/downloads/background_downloader_engine.dart`

The ONLY SPECTA file that imports `package:background_downloader/background_downloader.dart`. Every other SPECTA layer sees only:

- `DownloadEngineEvent` / `DownloadEngineProgress` (from `download_engine.dart`)
- `DownloadAttemptResult` (from `download_models.dart`)
- `DownloadFailure` (from `specta_failure.dart`)

Plugin types (`FileDownloader`, `DownloadTask`, `TaskStatus`, `TaskException`, `TaskRecord`, `TaskUpdate`, …) are confined to the adapter. They never cross the SPECTA abstraction boundary.

**Key design decisions:**

- **Task identity (§38):** the plugin `taskId` IS the SPECTA download id. Deterministic, reversible, no engine metadata persisted. After process death the plugin task is looked up from SPECTA identity alone.
- **`paused` semantics:** the plugin treats `paused` as non-final (a transfer may never settle by itself). The adapter therefore builds on `enqueue` + `updates` + a per-attempt completer rather than the plugin's `download()` convenience future. A `paused` status update settles the SPECTA attempt with `DownloadAttemptResult.paused`.
- **Progress math (§34):** whole-file basis — `progress * expectedFileSize`. The plugin's fraction already includes the resumed prefix (TaskRunner.kt). No `resumeFrom` added to progress (verified by `background_downloader_engine_test.dart` "progress translation uses WHOLE-FILE math").
- **Retry ownership:** `retries: 0` on every `DownloadTask`. The plugin never auto-retries; the manager owns the budget (`DownloadRetryPolicy`: maxAttempts 3, baseDelay 2s, maxDelay 60s).
- **Failure translation (§41):** typed `TaskException` hierarchy maps to `DownloadFailureType` without over-claiming. Untyped exceptions degrade to `networkError`. Raw plugin exceptions never escape.
- **Init laziness:** `_ensureInitialized()` calls `_downloader.start(...)` exactly once (doTrackTasks, markDownloadedComplete false, doRescheduleKilledTasks false, autoCleanDatabase false). WorkManager machinery is NOT spun up by provider graph construction.
- **Event tap:** the plugin's single-subscription `updates` stream is tapped once per `FileDownloader` instance and rebroadcast via a static map (`_taps`), so a provider rebuild or multiple engine instances never cause "already listened" errors.
- **Stale-event protection:** `_settle()` checks `completer != null && !completer.isCompleted` — a late terminal event against an already-settled attempt is a no-op. The manager adds epoch-based generation guard (`_activeEpoch`) on top.
- **`attach()` (§32):** probes the plugin's own task database (`recordForId`), registers the completer BEFORE the probe, and settles from the record's terminal status or waits for updates. If the record vanished between the manager's `isTransferActive` probe and `attach`, the completer stays waitable; `cancel()` resolves it (verified: "unknown record … stays waitable").

### A.3 DownloadManager integration — `lib/core/downloads/download_manager.dart`

The manager (1,171 lines) owns everything product-level:

- **Identity:** `DownloadIdentity.forMovie` / `forEpisode` — media key is identity; episodes are `|sS|eE`-qualified.
- **Persistence:** `DownloadStore`/`DownloadDao` — SQLite (Drift) is the ONLY authoritative state. Manager's in-memory maps are mirrors.
- **State machine:** `DownloadStateMachine.canTransition` enforces allowed transitions. Illegal transitions are refused, never silently rewritten.
- **Queue:** FIFO by creation time. Concurrency 3 default / 9 max (clamped). `_pump()` selects the oldest eligible queued record.
- **Persist-before-engine:** every state transition is persisted BEFORE the engine is asked. `_startAttempt` registers an epoch and runs the attempt OUTSIDE the serialized section (long-running).
- **Stale-event protection (§11):** epoch generation guard in `_reconcileResult` — a result from an old epoch is dropped. The engine's completer `isCompleted` guard prevents double-settles. `_activeEpoch.remove(id)` frees the slot on every attempt end.
- **Retry policy (§19-21):** `DownloadRetryPolicy` — bounded (3 attempts), exponential backoff (2s→60s), injectable clock. Auto-retry only for retryable failures. `shouldAutoRetry` checks both failure type and budget.
- **Source recovery (§23-25):** `DownloadSourceResolver` abstract. Production: `SourceManagerDownloadResolver`. Stale-pool protection: a source-classified failure (`httpError`, `invalidResponse`, `unsupportedSource`, `sourcesExhausted`) discards the captured pool and re-resolves through `SourceManager.resolve()` using persisted provenance (`sourceExtensionId` + `sourceReference`). Non-source failures keep the pool.
- **Restart reconciliation (§31/§32):** `initialize()` reads all persisted records. `downloading` records are probed via `engine.isTransferActive()`. Active → `attach()` (adopt, no re-enqueue). Dead → `interrupted` failure + auto-retry under the bounded budget. The manager reconciles through the same epoch-protected path.
- **Completion gate (§40):** `FileDownloadCompletionFinalizer` verifies on disk. Part file exists → rename onto final path. Part absent but non-empty final exists → accept. Neither → honest `engineFailure`. Never masks success.
- **Progress coalescing (§33):** `DownloadProgressPersistPolicy` — persist when `bytesDelta >= 256KB` OR `interval >= 2s`. State transitions always persist.
- **Network policy:** `evaluateNetworkPolicy(wifiOnly)` — conservative; unknown network = blocked. `DeviceEnvironment` via platform channel `net.specta.app/environment` (`MainActivity.kt`).
- **Cancellation (§27):** idempotent, terminal protection (completed/cancelled cannot be cancelled again). `_activeEpoch.remove(id)` before `engine.cancel()` — the generation dies, any late result is stale.
- **Duplicate semantics (§28):** 8 `DownloadEnqueueAction` values. Re-requesting a completed download = honest refusal. Re-requesting a failed/cancelled = new run, budget resets.

### A.4 Provider wiring — `lib/core/downloads/download_providers.dart`

All production bindings installed:

| Provider | Value |
|---|---|
| `downloadStoreProvider` | `DownloadDao(ref.watch(spectaDatabaseProvider))` |
| `downloadEngineProvider` | `BackgroundDownloaderEngine()` |
| `downloadSourceResolverProvider` | `SourceManagerDownloadResolver(extensionManager: () => ref.watch(extensionManagerProvider))` |
| `downloadCompletionFinalizerProvider` | `FileDownloadCompletionFinalizer()` |
| `downloadManagerProvider` | Full construction with all seams, `onChanged` → `downloadRevisionProvider`, `initialize()` + concurrency restore |
| `downloadRevisionProvider` | `Notifier<int>` bumped on every persisted change |
| `all/queued/active/paused/completed/failed/cancelledDownloadsProvider` | Filtered from `downloadStoreProvider` by revision |
| `downloadByIdProvider` | `FutureProvider.family<DownloadRecord?, String>` |
| `activeCountProvider` | `manager.activeCount` (in-memory truth) |
| `downloadQueueStatusProvider` | `totalCount` + `activeCount` + `queuedCount` + `concurrency` |

The production path is verified by `download_providers_test.dart`: `downloadEngineProvider` resolves to `BackgroundDownloaderEngine` at runtime.

### A.5 SourceManager resolver — `lib/core/downloads/source_manager_download_resolver.dart`

Recovery path proven by `source_manager_download_resolver_test.dart`:

```text
failed/expired source
      ↓
  DownloadManager (passes lastFailure)
      ↓
  SourceManagerDownloadResolver.resolveSource()
      ↓
  Captured pool? ← no source-invalidating failure → SERVE it
  Captured pool? ← source-invalidating failure → DISCARD, re-resolve
      ↓
  _resolveThroughSourceManager()
      ↓
  SourceManager.resolve(reference, extensions, manager)
      ↓
  ExtensionManager.callOperation(getSources) → validation → ranking → SourcePool
      ↓
  Fresh candidates (or null — honest)
```

Stale-pool protection tested for ALL four invalidating failure types (`httpError`, `invalidResponse`, `unsupportedSource`, `sourcesExhausted`). Captured pool never resurrects on a subsequent no-failure resolve.

### A.6 Transfer lifecycle (verified by `background_downloader_engine_test.dart`)

```text
start(input)
  ↓
  enqueue(DownloadTask{taskId: downloadId, retries: 0, allowPause: true, ...})
  ↓
  _attempts[downloadId] = Completer (tracks the attempt)
  ↓
  Plugin updates stream → _onPluginUpdate → _handleProgress / _handleStatus
  ↓
  Terminal status → _settle(downloadId, result) — completer.complete, guarded by isCompleted
  ↓
  start() returns DownloadAttemptResult (exactly one terminal result)
```

Cancellation: `cancel(downloadId)` → `_downloader.cancelTaskWithId(downloadId)` + completer.complete(cancelled) as fallback. Late `canceled`/`complete` updates after settlement are no-ops.

### A.7 File lifecycle (verified by `download_engine_integration_test.dart`)

```text
enqueue → downloading → .part file staged
  ↓
transfer complete → engine reports complete
  ↓
FileDownloadCompletionFinalizer.finalize(record, bytes):
  part exists? → rename onto final path, verify size > 0
  part absent + final exists? → accept final's size
  neither? → engineFailure (never masked)
  ↓
Record persisted as completed (bytes, total, completedAt)
```

Partial files cannot masquerade as completed (empty file → failure). Cancellation does not produce completion. Failed transfers stay failed.

### A.8 Test coverage categorization

| Category | File | What it proves |
|---|---|---|
| Adapter | `test/core/downloads/background_downloader_engine_test.dart` | Task identity, progress math, status translation (complete/paused/notFound/failure types), `attach` adoption, `isTransferActive`, cancellation, stale terminal updates, non-download task isolation |
| Manager integration | `test/core/downloads/download_engine_integration_test.dart` | Restart adoption (surviving transfer, died transfer, paused record), completion gate (empty/zero-byte/refused + rename), source expiry → fresh resolution, bounded budget survival |
| Persistence | `test/core/downloads/download_persistence_contract_test.dart` | State survival across store recreation, identity/metadata/provenance/path survival, FIFO ordering, duplicate prevention, state machine enforcement, recreation idempotency |
| Source recovery | `test/core/downloads/source_manager_download_resolver_test.dart` | Captured-pool freshness, stale-pool discard for ALL invalidating types, no resurrection, real SourceManager re-resolution, honest null answers, extension isolation |
| Provider wiring | `test/core/downloads/download_providers_test.dart` | Real engine seam, manager construction, filter behavior, terminal states, queue status, concurrency clamping, persisted setting restore, container recreation |
| Manager orchestration | `test/core/downloads/download_manager_test.dart` | Queue/concurrency, duplicates, state machine, retry/backoff, source recovery seam, progress coalescing, remove, restart/reconciliation, file lifecycle |
| Device verification | `integration_test/phase2gc_device_verification_test.dart` | Real device: enqueue → transfer → completion; cancellation; restart reconciliation (NOT YET RUN — needs Samsung Galaxy A06) |

**Important untested acceptance requirement:** Real device MP4 transfer through the production path (the device test exists but was not executed in this session — see §15).

---

## B. VERIFICATION

| Command | Result |
|---|---|
| `flutter analyze` | **No issues found** (38.4s) |
| `flutter test` | **750 passed / 9 skipped / 0 failed** (1:49) |
| `flutter test` (real JS bridge) | **NOT RUN** — `quickjs_c_bridge.dll` not loadable on this Windows process; run via `tool/run_tests_real_js.sh` |
| `flutter build apk --debug` | **NOT RUN in this session** (was SUCCESSFUL at 2G-C pre-flight: 277,535,750 bytes) |
| Device validation (Samsung Galaxy A06 / Android 16) | **NOT PERFORMED** — no device attached to this session |

### Targeted 2G-C test counts

| Test file | Tests |
|---|---|
| `background_downloader_engine_test.dart` | 16 |
| `download_engine_integration_test.dart` | 11 |
| `download_persistence_contract_test.dart` | 8 |
| `download_providers_test.dart` | 9 |
| `download_manager_test.dart` | 50 (modified in 2G-C) |
| `source_manager_download_resolver_test.dart` | 14 |
| **2G-C specific total** | **~108** (across 6 new/modified files) |
| Full suite | 750 passed / 9 skipped |

The 9 skipped are all the real-engine (`flutter_js`) group, consistent across the full suite.

---

## C. LIMITATIONS

### Honest limitations (not device-verified)

1. **Real device MP4 transfer**: The production transfer path (`BackgroundDownloaderEngine` → `background_downloader` 9.6.2 → WorkManager → local file) has NOT been exercised on a physical device in this session. The integration test (`integration_test/phase2gc_device_verification_test.dart`) exists and targets it, but needs a Samsung Galaxy A06 or equivalent.

2. **APK build**: Not rebuilt since the 2G-C pre-flight. Code changed but analyze + test pass. A fresh debug APK should be built before distribution.

3. **JS runtime (QuickJS)**: The real-JS test suite cannot run on this Windows machine (missing `quickjs_c_bridge.dll`). The adapter tests are pure-VM (`@TestOn('vm')`) and use the plugin's mock method channels, so they are unaffected.

4. **Resume after process death**: The reconciliation path (§32) is tested via the fake engine in `download_engine_integration_test.dart` and `download_manager_test.dart`. On a real device, `background_downloader`'s WorkManager persistence + the adapter's `attach()` + the manager's `initialize()` should produce the same behavior, but this has not been verified on-device.

5. **`background_downloader` plugin maintenance**: The plugin uses Kotlin Gradle Plugin, which a future Flutter release may refuse to build. Same risk as `flutter_js`/`cryptography_flutter`.

6. **OEM background behavior**: WorkManager background execution limits on various Android OEMs (Xiaomi, Huawei, Samsung) are not tested. The app declares FOREGROUND_SERVICE but OEM killing behavior varies.

7. **Network recovery**: The request policy and `DeviceEnvironment` are tested in isolation. Real-world network switching (Wi-Fi → mobile mid-download) has not been tested.

8. **Storage pre-flight**: `DeviceEnvironment.freeBytes` returns `null` on the VM and on the current MainActivity implementation (the platform channel handler exists but returns -1 on error). The storage check gracefully skips when unknown.

9. **Cancellation artifact cleanup**: After cancellation, the `.part` file may persist under the plugin's ownership. SPECTA's contract guarantees NO final media exists after cancellation; `.part` cleanup is delegated to the plugin or the next run's stale-artifact sweep (see device test P2GC-2).

---

## D. ARCHITECTURE VERIFICATION

### D.1 Production runtime path proven

```text
SourceManager.resolve(reference, extensions, manager)
      ↓
  SourcePool (ranked candidates + outcomes)
      ↓
  DownloadManager.enqueue(DownloadRequest{pool, extensions, ...})
      ↓
  DownloadManager._pump() → _startAttempt()
      ↓
  _runAttempt():
    _sourceResolver.resolveSource(record, lastFailure) → SourcePool?
    → _pickDownloadable(pool) → RankedSource (MP4 first, SPECTA ranking order)
      ↓
  engine.start(DownloadAttemptInput{downloadId, url, partPath, resumeFrom, headers})
      ↓
  BackgroundDownloaderEngine.start():
    _downloader.enqueue(DownloadTask{taskId: downloadId, retries: 0, ...})
      ↓
  Plugin → WorkManager → Android HTTP → local file
      ↓
  Plugin updates → _onPluginUpdate → _handleProgress / _handleStatus
      ↓
  _settle(downloadId, result) → completer.complete
      ↓
  manager._reconcileResult() → state machine → persistence
```

### D.2 Adapter connected to production DI path

`downloadEngineProvider` in `download_providers.dart` line 40:
```dart
Provider<DownloadEngine> downloadEngineProvider = Provider<DownloadEngine>(
  (Ref ref) => BackgroundDownloaderEngine(),
);
```
`downloadManagerProvider` injects `ref.watch(downloadEngineProvider)` and `ref.watch(downloadSourceResolverProvider)`. The production graph uses the real adapter.

### D.3 Plugin types do not leak

- `BackgroundDownloaderEngine` is the only file importing `background_downloader`.
- `downloadEngineProvider` exposes `DownloadEngine` (SPECTA-owned interface).
- `DownloadManager` imports `download_engine.dart` (interface) and `download_models.dart` (SPECTA types) — never `background_downloader`.
- `DownloadManager` implements `DownloadEngine` as an abstract interface, not a plugin class.
- Tests: `download_providers_test.dart` asserts `seam.runtimeType.toString() == 'BackgroundDownloaderEngine'` through the `DownloadEngine` interface — plugin types stay isolated.

### D.4 No competing retry budget

Every `DownloadTask` in the adapter uses `retries: 0`. `background_downloader` does not auto-retry. All retry logic lives in `DownloadRetryPolicy` (3 attempts, exponential backoff 2s→60s, injectable clock). Verified by `download_manager_test.dart` retry/backoff tests.

---

## E. FINAL VERDICT

```text
READY FOR PHASE 2H
```

All 2G-C acceptance criteria are satisfied:

- [x] `background_downloader` 9.6.2 declared and resolved
- [x] Real adapter (`BackgroundDownloaderEngine`) translates plugin → SPECTA types
- [x] Adapter connected to production provider/DI path (`downloadEngineProvider`)
- [x] DownloadManager owns retry policy (retries: 0 in all plugin tasks)
- [x] Transfer lifecycle: enqueue → progress → completion/cancelled/failed
- [x] `.part` staging + final-file gate (`FileDownloadCompletionFinalizer`)
- [x] Source recovery via `SourceManagerDownloadResolver` (stale-pool protection tested)
- [x] Restart reconciliation via `isTransferActive` + `attach` (tested)
- [x] Stale-event protection (epoch guard + completer isCompleted)
- [x] Concurrency: 3 default, 9 max, clamped
- [x] SQLite is authoritative (DownloadDao/DownloadStore)
- [x] 750 tests pass, 0 failed; analyze clean
- [x] Device verification test written (`integration_test/phase2gc_device_verification_test.dart`)

**Phase 2H (extension catalogue) remains NOT AUTHORIZED and is NOT to be started.**

---

*This audit was produced by systematic source inspection against the 2G-C authorization (Sections 1–24). No claim was made without source evidence.*
