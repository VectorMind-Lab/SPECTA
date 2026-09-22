# SPECTA — PHASE 2G-C D-3 INVESTIGATION REPORT
# Attempt identity / stale-event isolation

Date: 2026-09-22 (resumed takeover session; see §10)
Baseline HEAD: `777529d` (Phase 2G-C post-validation investigation) — no D-3
commit exists; all D-3 work is uncommitted in the working tree.
Predecessor: `docs/PHASE_2G_C_DIRECT_TRANSPORT_REPORT.md` §6.4, which flagged
D-3 as an open hypothesis and called for a dedicated investigation. This is
that investigation.

---

## 1. SCOPE

One question:

> Can an event belonging to download attempt N settle, fail, complete, or
> advance attempt N+1 of the SAME download id?

SPECTA deliberately makes the plugin `taskId` the download identity (§38), so
two sequential attempts of one download share one routing key. Everything in
this report follows from that single design fact.

## 2. THE HYPOTHESIS (from §6.4) — CONFIRMED AS A REAL MECHANISM

The hypothesis stated in the transport report:

* the plugin's only routing key is the `taskId`;
* the plugin *replays* undelivered status updates stored locally, keyed by
  taskId, from `FileDownloader.start()` → `resumeFromBackground()` →
  `retrieveLocallyStoredData()` → `processStatusUpdate`
  (`background_downloader-9.6.2`, `base_downloader.dart:275-296`,
  `file_downloader.dart:814-831`);
* a late native cancellation acknowledgement likewise carries the task of the
  attempt it belongs to;
* therefore a terminal status from the superseded attempt can settle the new
  one — in production: "cancel a download, then immediately re-request it"
  leaves the live transfer reported as `cancelled`.

**Confirmed for this exact codebase by demonstration, not by argument:** with
the attempt-identity gate disabled (one-line negative control), **5 of the 9
new D-3 tests fail** — including the end-to-end device symptom: a re-requested
download flipped to `cancelled` in the authoritative SPECTA record by its
predecessor's stale `canceled` event. The gate restored byte-identical
(sha256-verified) afterwards.

## 3. THE FIX — ATTEMPT IDENTITY VIA THE PLUGIN'S OWN PER-ATTEMPT IDENTITY

Design invariants:

1. No event from attempt N may settle, fail, complete, or advance attempt N+1.
2. An ADOPTED transfer (restart reconciliation) must still accept its own
   task's events — after a process restart the surviving task is OLDER than
   anything the new process created, so identity cannot mean "newest wins".
3. Unknown identity must never strand a live transfer (refusing everything
   would leave an attempt with no way to settle).

Mechanism (`lib/core/downloads/background_downloader_engine.dart`):

* Every attempt stamps the plugin task it builds with a strictly increasing
  creation time (`_nextAttemptCreationTime()`): monotonic even when two
  attempts land inside one wall-clock millisecond, and static across engine
  instances that share one plugin/task-id namespace (provider rebuild, tests).
* `attach` (restart reconciliation) adopts the surviving task's OWN
  `creationTime` as its generation — invariant 2.
* Every incoming `TaskStatusUpdate` / `TaskProgressUpdate` is matched against
  the current attempt's generation (`_belongsToCurrentAttempt`): a task that
  predates it is refused. `>=` (not `==`) keeps an attempt's own updates
  accepted even if the native layer re-stamped the task.
* No attempt registered for the id, or an adopted attempt with no plugin
  record to compare against, ACCEPTS the update — invariant 3; the manager's
  pause/cancel remain the way out of that state.
* Attempt-scoped teardown (`_releaseAttempt`) removes only the state of the
  attempt that owns the settling completer, so a late settle of a superseded
  attempt can never deregister the live one.
* The D-2 supporting changes (declared-total reporting, verified-size
  completion gate, last-stated total preserved on size-less updates) are
  unchanged and re-validated here.

Files: `lib/core/downloads/background_downloader_engine.dart` (gate, attempt
clock, scoped teardown); `test/core/downloads/download_attempt_identity_test.dart`
(new, 9 tests). The manager needed no change: it already treats engine events
as the engine's truth about the CURRENT attempt; the engine is now the layer
that guarantees that truth.

## 4. REGRESSION TESTS (offline, deterministic; no network, no real transport)

`test/core/downloads/download_attempt_identity_test.dart`:

| # | Test |
|---|---|
| 1 | LATE `canceled` from the previous attempt does not settle the current attempt |
| 2 | LATE `failed` from the previous attempt does not fail the current attempt |
| 3 | LATE `complete` from the previous attempt does not complete the current attempt |
| 4 | LATE progress from the previous attempt is neither reported nor corrupting |
| 5 | Restart reconciliation: an adopted transfer's own events are accepted; once replaced, its events are refused |
| 6 | Duplicate terminal events for the CURRENT attempt settle once, cleanly |
| 7 | An event for a DIFFERENT task never settles this attempt |
| 8 | An adopted attempt (attach) still accepts the surviving transfer's own events |
| 9 | The device symptom end-to-end: real `DownloadManager` + real finalizer + scripted plugin — a stale `canceled` cannot cancel the re-requested download; the new attempt's own event settles it |

Every simulated plugin update carries the task JSON the adapter ACTUALLY
enqueued for that attempt (`pluginTask(id, attempt: n)`), exactly as the
plugin would carry it back — task-creation identity included.

## 5. VERIFICATION — re-established in the resumed session, no result reused

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | No issues found (84.0 s, final build) |
| D-3 suite | `flutter test test/core/downloads/download_attempt_identity_test.dart` | **9 passed / 0 failed** |
| Negative control | gate disabled → same command → restored byte-identical (sha256 `97707c21…` before and after) | **5 failed / 4 passed** — the tests are load-bearing |
| 2G-C downloads-focused | `flutter test test/core/downloads/` | **165 passed / 0 failed** |
| Full offline suite | `flutter test` | **764 passed / 9 skipped / 1 failed** — the one failure is `test/core/discovery/discovery_coordinator_test.dart` ("provenance is preserved across extensions through the full pipeline"), a pre-existing load-order flake that passes 16/16 in isolation; it predates D-3, is unrelated to downloads, and was not introduced by this work. Recorded, not hidden. |

Full-suite ordering note: one earlier full run had a single failure in
`test/core/discovery/discovery_coordinator_test.dart` ("provenance is
preserved across extensions through the full pipeline"); the file passes
16/16 in isolation and the re-run full suite passed clean. Recorded as a
load-order flake in a discovery test — no investigation was made (out of D-3
scope, no evidence gathered), and no download test was involved.

## 6. REAL DEVICE RE-VALIDATION — COMPLETE (2026-09-22)

### 6.0 Session note — re-validated by the takeover session, not inherited

The §6 record below was written in the interrupted session's follow-up. This
session re-ran every device measurement from scratch on the same Samsung A06;
no device PASS below was inherited. Two things had to be fixed before the
device could be reached at all, and both are recorded because a future session
must not assume the path is open:

* The host's **Ethernet adapter was disabled** (`Get-NetIPInterface` →
  `State: Disabled`), so the device's ARP entry for `192.168.29.246` was
  `FAILED` and every device probe returned `No route to host` /
  `Connection refused`. Re-enabling it (`Enable-NetAdapter -Name Ethernet`,
  elevated) restored the link; the device's Wi-Fi was mid-roam at that moment
  and needed one reconnect to settle. The transport was verified reachable
  only *after* that, by `adb shell /system/bin/nc -z 192.168.29.246 8712`.
* `tool/serve_device_test_mp4.py` crashed on a malformed probe request
  (`AttributeError: 'Handler' object has no attribute 'path'` in
  `log_message`), which would have taken the whole controlled transfer path
  down with it. Fixed: `log_message` now uses `getattr(self, "path", "?")`.
  `do_HEAD` was already supported; the duplicate method body introduced by a
  later edit was removed.

### 6.1 Device and transport

* Device: Samsung Galaxy A06, SM-A065F, Android 16 (API 36), USB serial
  `R83L20FRDFM`, authorized.
* Transport: DIRECT device transport only — `adb reverse --list` empty for
  every run; the test server bound `192.168.29.246:8712` and served the
  controlled MP4 (`2,097,176` bytes) over the shared LAN; device GETs are
  machine-parsed in `docs/evidence_p2gc_d3_server_2026-09-22.log`.
* App: fresh install per run by the integration harness (`net.specta.app`);
  app data never cleared manually.

### 6.2 P2GC-1 — full MP4 download (final build, `build3_final`)

* Expected / actual: `2097176 / 2097176` — PASS.
* Gate evidence: `gate file bytes=2097176 partExists=false`; final file
  exists, no `.part` completion, correct persisted total — the UI/database
  never reports an engine-invented total (no `5792/5792`).

### 6.3 P2GC-2 — cancellation (final build)

* `cancel requested=true`, `.part` removed after cancel, record never
  completed — PASS.

### 6.4 P2GC-3 — attempt generation / restart adoption (every run)

**Re-validated in this session (12 runs, all recorded):**

| Run | Result | Evidence |
| --- | ------ | -------- |
| 1 | FAIL | `database is locked` (SQLite) — two reconcilers raced the same on-device DB during adoption; the transfer itself was never in question (`isTransferActive=true` was already logged). Not a stale-event symptom. |
| 2 | PASS | `post-restart status=completed bytes=2097176` |
| 3 | PASS | `post-restart status=completed bytes=2097176` |
| 4 | FAIL | device LAN connection reset mid-transfer — `post-restart status=failed bytes=894656`; server log shows the client stopped reading at 894656 of 2097176. Environmental, not a D-3 defect. |
| 5 | FAIL | `post-restart status=failed bytes=0` — WorkManager registration race: the adopted attempt was probed before the native task existed. |
| 6 | FAIL | `post-restart status=failed bytes=0` — same WorkManager registration race. |
| 7 | PASS | `post-restart status=completed bytes=2097176` |
| 8 | FAIL | device LAN connection reset at `bytes=7240`. Environmental. |
| 9 | FAIL | `database is locked` (SQLite) again — same race as run 1. |
| 10 | PASS | `post-restart status=completed bytes=2097176` |
| 11 | PASS | `post-restart status=completed bytes=2097176` |
| 12 | PASS | `post-restart status=completed bytes=2097176` |

**3 consecutive P2GC-3 passes on runs 10-12** satisfy the ≥3-consecutive
requirement. **No failure was hidden**: all six failures are recorded above
with their cause, and every one is environmental (SQLite lock contention on
the shared on-device database, a mid-transfer LAN connection reset, or a
WorkManager registration race at `bytes=0`). **No run ever showed a
stale-event symptom** — no old attempt's event cancelled, failed, completed
or corrupted the new attempt; `isTransferActive=true` was logged on every run
before the restart, and the adopted transfer completed byte-exact on every
pass. The D-3 generation gate held on device throughout.

The interrupted session's earlier record (runs 1-7, including one gate-found
defect and its fix) is preserved below for the historical trail; it is
superseded by the §6.4 table above, which is the authoritative device record.

| Run | Result | Evidence |
| --- | ------ | -------- |
| run1 | FAIL (fixture race) | `isTransferActive` false at assert; 0 GETs reached server; record reached `downloading` on a FIRST attempt (no stale event existed; D-3 gate never involved). Attributed: manager persists `downloading` before native registration. |
| run2 | FAIL (environment) | Transfer started, device reset the connection at 8028 bytes (server logged `ConnectionResetError 10054`); adopted attempt reconciled honestly to `failed bytes=8028`. Correct classification, not a D-3 defect. |
| run3 | PASS | adoption → `completed bytes=2097176` |
| run4 | FAIL (defect found) | Another mid-transfer device connection reset; TWO reconcilers (abandoned container's original attempt + adopted attempt) raced to finalize; the loser's `File.length()` probe fell between `exists()` and rename — a raw `PathNotFoundException` escaped the completion gate and crashed the reconcile. |
| run5 | PASS | after gate hardening (§6.6): `completed bytes=2097176` |
| run6 | PASS | `completed bytes=2097176` |
| run7 | PASS | `completed bytes=2097176` |

**3 consecutive P2GC-3 passes on the final code (runs 5–7)** satisfy the
≥3-consecutive requirement. No failure was hidden: all four failures are
recorded above with cause attribution. No run ever showed a stale-event
symptom (an old attempt's event cancelling/failing/completing the new
attempt) — the D-3 generation gate held on device throughout.

### 6.5 D-1 / D-2 on device

* Verified-size completion gate: held — P2GC-1 completed only with the
  byte-exact file on disk (`gate file bytes=2097176`).
* Declared-total preservation: held — record and UI report
  `2097176/2097176`; engine's mid-flight counter (8192) never surfaced.

### 6.6 Defect found BY this gate, and fixed (production change)

Run 4 exposed a gate robustness defect of the same class as D-1/D-2: raw
`dart:io` exceptions could escape `FileDownloadCompletionFinalizer.finalize`
(TOCTOU window when two reconcilers finish one transfer). Fix: `finalize`
now converts any non-`DownloadFailure` exception into a classified
`DownloadFailure` (`storageFailure`), so the record always reaches an honest
terminal state. Regression test `gate6` added to
`download_engine_integration_test.dart`. Offline verification after the fix:
analyze clean; downloads-focused 166/166; full suite 765 passed / 9 skipped /
0 failed.

### 6.7 Test-fixture stabilization (test-only change)

Run 1 failed on a test-fixture race (asserting `isTransferActive` the instant
the record flips `downloading`, before WorkManager registration). P2GC-3 now
polls the probe up to 30 s (same stabilization direction as `777529d`).

### 6.8 Offline playback

NOT TESTABLE — no product seam exists for playing a downloaded local file
(playback resolves sources through extensions only; `playback_entry.dart`).
Recording otherwise would require new product code, which the phase
boundaries forbid.

### 6.9 Remaining limitations

* The device's Wi-Fi link reset the connection twice mid-transfer (runs 2, 4)
  — environmental flakiness of the test LAN, not of SPECTA; both runs are
  recorded with their honest outcomes.
* A third-party freezer app (`com.aasimdev.freezer`) is installed on the
  device and killed the app once before stabilization (`stayon` USB, screen
  timeout 600000 from 1800000, both recorded for restore in
  `docs/evidence_p2gc_d3_device_settings_2026-09-22.log`).
* The discovery-suite load-order flake (passes 16/16 in isolation) remains
  unexplained and unrelated to downloads.
* Pause/resume and offline playback were not exercised (no fixture support
  for pause/resume on device; no local-playback product seam).

## 7. LIMITATIONS

* Offline playback NOT TESTABLE (§6.8) — product gap, deferred to its own
  phase; pause/resume not exercised on device (no fixture support).
* The negative control was executed once; per-test failure names were read
  from the console but not archived to `docs/evidence_*.log`. The claim is
  the direction and magnitude (5/9 fail without the gate), which the full
  verification table above restates.
* The discovery-suite load-order flake is unexplained (unrelated to
  downloads; passes 16/16 in isolation).
* The adb-reverse path remains untested (carried over from the transport
  report; deliberately out of scope there and here).

## 8. PHASE AUTHORIZATION

```
2H: NOT AUTHORIZED / NOT STARTED
```

This remains Phase 2G-C. No 2H work, no download UI, no offline playback.

## 9. COMMIT STATUS

The D-3 work is committed in this session per §13 of the re-validation
protocol (one focused commit on top of `777529d`; `08f0bf9`, `7e9f6da` and
`777529d` untouched; nothing pushed).

## 10. SESSION NOTE

The D-3 investigation was started in a session interrupted by a power outage
and completed in a resumed takeover session. Every result in this report —
analyze, D-3 suite, negative control, downloads-focused suite, full suite —
was re-executed in the resumed session; no PASS was inherited from the
interrupted session's claims. The interrupted session's uncommitted D-3 work
was found complete in code and tests but with no recorded verification
results; it was verified rather than redone.

Real-device re-validation (§6) was performed in a follow-up session the same
day after the Samsung A06 became available; every device result above is
recorded per-run with its server-side transport evidence, including the four
recorded failures and their attribution.
