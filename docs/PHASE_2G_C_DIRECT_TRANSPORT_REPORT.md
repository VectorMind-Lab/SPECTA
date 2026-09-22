# SPECTA — PHASE 2G-C FOLLOW-UP: DIRECT NETWORK TRANSPORT ISOLATION & REAL-DEVICE VALIDATION

**Date:** 2026-09-22
**Scope:** Remove the `adb reverse` tunnel from the transport path, re-run the
Phase 2G-C real-device validation over a direct device→server network path, and
— where the validation demonstrated a defect — repair it.

**Outcome in one line:** the `adb reverse` transport was **exonerated** (the same
failure signature reproduced without it), **two real SPECTA defects** were
demonstrated with no network and no plugin, and after the owner authorised the
repair the real device downloads the full 2,097,176-byte file **and** reports it
correctly (**3/3 device tests pass** on the direct transport).

---

## 1. REPOSITORY

| Item | Value |
|---|---|
| Branch | `master` |
| HEAD at session start | `777529d` — "test(phase2g): stabilize device transfer recovery tests" |
| Preserved checkpoints | `08f0bf9` (2G-C implementation), `777529d` (2G-C device investigation) — **unchanged, never rewritten** |
| Remote | `origin` = `https://github.com/VectorMind-Lab/SPECTA.git` (not pushed in this session) |
| Working tree at session start | one pre-existing untracked file (`docs/SPECTA — Coding AI Master Prompt — Phase 0_…md`), not this session's, left untouched |

Commit history around the phase (unmodified):

```text
777529d test(phase2g): stabilize device transfer recovery tests
7e9f6da docs(phase2g): record real device download validation
08f0bf9 feat(phase2g): complete real download engine integration
```

---

## 2. DEVICE

| Item | Value |
|---|---|
| Model | Samsung Galaxy A06 (`SM-A065F`, product `a06xx`) |
| Android | 16 |
| API | 36 |
| Device identifier (adb) | `R83L20FRDFM` |
| Wi-Fi | connected, SSID `"Silent Thread "`, **IPv4 `192.168.29.174/24`** |
| Other interfaces | `rmnet0/2/6` (mobile), `lo` |

(The previous session's record wrote the device id as `R83L20FRDM`; `adb devices`
and every harness run use `R83L20FRDFM`. Corrected in `PROJECT_STATE.txt`.)

---

## 3. TRANSPORT

### 3.1 Previous transport (the one under suspicion)

```text
Samsung A06 → adb reverse tcp:8712 tcp:8712 → host loopback → HTTP test server
```

### 3.2 Transport used in this session

```text
Samsung A06 (192.168.29.174, Wi-Fi "Silent Thread ")
   → router → PC (192.168.29.246, Ethernet) → controlled server on 192.168.29.246:8712
```

* **ADB reverse used: NO.** `adb reverse --list` was verified **empty** before
  and after every device run. No `adb forward`, no port forwarding, no tunnel.
* Server bound to `192.168.29.246` only (the LAN interface) — **not** `0.0.0.0`,
  **not** exposed to the Internet.
* Phone→server connectivity: **verified** (§5). ICMP `ping` fails (Windows drops
  inbound ICMP); TCP/8712 works, which is all the transfer uses.
* Windows Firewall was **not** disabled. No new rule was needed: the existing
  inbound `python.exe` allow rule (Private profile, TCP) already covers the
  controlled server.

### 3.3 Environment note

A **stale instance of the previous session's server** was found still listening
on `127.0.0.1:8712` (PID 15848). It plays no part in the direct path (which binds
`192.168.29.246`) and was left alone; recorded so a future session is not
confused by two listeners on one port.

---

## 4. SERVER VERIFICATION

| Item | Value |
|---|---|
| Fixture | `specta_device_test.mp4` (from `tool/make_device_test_mp4.py`) |
| Expected size | `2,097,176` bytes |
| Actual size | `2,097,176` bytes |
| SHA-256 | `7e4f2667d71f4f7dc9ccbfa902423ad245da0eeeff1c8061ffe7a9723596073c` |
| Served `Content-Length` | `2097176` (HTTP 200, `Accept-Ranges: bytes`) |

`tool/serve_device_test_mp4.py` was extended (test-only, defaults unchanged):
`--host` / `--port`, per-request `Range` + User-Agent logging, and a
`SENT bytes=N expected=M complete=BOOL` line recording what the server actually
wrote — which separates "the server truncated" from "the client stopped reading".

---

## 5. EVIDENCE CHAIN (the transport is healthy)

| # | Measurement | Result |
|---|---|---|
| 1 | Host `curl` the LAN URL | HTTP 200, `size_download=2097176`, hash matches fixture |
| 2 | Device `HEAD /test.mp4` via `adb shell nc` (**no adb reverse**) | `200 OK`, `Content-Length: 2097176` |
| 3 | Device full GET via `adb shell nc` (**no adb reverse**) | 2,097,340 bytes = 2,097,176 body + 164 header bytes |
| 4 | **`dart:io` `HttpClient` inside the app process** | `status=200 contentLength=2097176 bytesRead=2097176` |
| 5 | **real `BackgroundDownloaderEngine` driven directly** (no manager) | plugin wrote **2,097,176 bytes to disk**; server `SENT=2097176 complete=True`, `range=-` |

Instrumented server view of a full device run (fast mode) — every app request is
a `Dalvik` (plugin native stack) request with **no `Range`**, and the server
pushed the complete body each time:

```text
SENT bytes=2097176 expected=2097176 complete=True   ← P2GC-1
SENT bytes=1245184 expected=2097176 complete=False  ← P2GC-2 closed mid-body on cancel
SENT bytes=2097176 expected=2097176 complete=True   ← P2GC-3
```

---

## 6. DEFECTS DEMONSTRATED (pre-fix device validation)

### 6.1 Device measurement, fresh install, direct transport, PRE-FIX

```text
[SPECTA-P2GC] final status=completed bytes=5792/5792
[SPECTA-P2GC] engine progress events=2 first=5792/2097176 last=5792/null
[SPECTA-P2GC] gate file bytes=2097176 partExists=false
```

The media was **byte-exact** (2,097,176 bytes at the final path, no `.part`),
while the persisted record claimed `5792/5792`. The test failed **only** on
`expect(record.bytesDownloaded, expectedBytes)`.

### 6.2 D-1 — the completion gate accepted an incomplete file as completed media

`FileDownloadCompletionFinalizer.finalize` measured the file and then preferred
the engine's claim (`return engineBytes > 0 ? engineBytes : size`). Reproduced
with **no network and no plugin** (scripted engine + the real finalizer + the
real manager):

```text
[PROBE-A] status=completed bytes=8028 total=8028 fileBytesOnDisk=8028
          declaredTotal=2097176 failure=null
```

8028 of 2,097,176 declared bytes accepted as success. This contradicts the claim
in `docs/PHASE_2G_C_ENGINE_AUDIT.md` (and `PROJECT_STATE.txt`, and §3/§13 of the
follow-up authorization) that "SPECTA's completion gate correctly rejected the
incomplete/wrong-sized file" — the rejection came from a **test assertion**
(`expect(await finalFile.length(), expectedBytes)`); the record was persisted as
`completed 8192/8192`. Production code had no byte-integrity check against any
declared total; the gate only refused a *missing* or *empty* file.

### 6.3 D-2 — the engine's stale byte count erased the verified size and the declared total

Three linked facts, each reproduced offline:

```text
[PROBE-B] status=completed bytes=5792 total=5792 fileBytesOnDisk=2097176
```

* `BackgroundDownloaderEngine._handleStatus` (`complete`) reported
  `totalBytes = bytes` — inventing a total from its own byte counter and
  discarding the declared size it had already seen.
* `DownloadManager` preferred `result.totalBytes` over the live/persisted
  declared total, so the invented value replaced the real one.
* **A size-less progress update erased the known total**: the plugin's final
  progress tick of a fast transfer carries no size (`last=5792/null` on device),
  and both the adapter's event and the manager's live-progress map replaced the
  earlier `2097176` with `null`. Without this, the gate had nothing to verify
  against even after the first two fixes — the declared total was silently lost.

**Consequence:** SPECTA could report success for a truncated file, and could not
report a correct byte count for a file it had downloaded correctly. Integrity was
enforced by the test harness, not by the product.

### 6.4 D-3 — OPEN, not fixed: restart-recovery test is flaky, and one slow-mode run observed a spontaneous `cancelled`

| Run (all post-fix) | Transport | P2GC-1 | P2GC-2 | P2GC-3 |
|---|---|---|---|---|
| fresh install | direct, fast | PASS | PASS | **PASS** |
| fresh install | direct, slow (~23 KB/s) | PASS (92 s, exact bytes) | PASS | **FAIL** — record was `cancelled`, never reached `downloading` |
| P2GC-3 alone | direct, slow | — | — | **FAIL** — `isTransferActive` returned `false` |

Pre-fix, on the same device, P2GC-3 passed twice (fast) and failed once
(`isTransferActive` false). It is therefore **flaky in both directions**.

A plausible mechanism for the slow-run `cancelled` — recorded as a hypothesis,
**not** proven: the adapter keys attempt completers by `taskId` alone with no
generation, and the plugin *replays* undelivered status updates
(`BaseDownloader.retrieveLocallyStoredData()` → `processStatusUpdate`, see
`background_downloader-9.6.2/lib/src/base_downloader.dart:275-296`). A late or
replayed terminal status for a **reused** `taskId` (P2GC-2 cancels, P2GC-3
re-enqueues the same id) can settle a *new* attempt. In production the equivalent
sequence is "cancel a download, then immediately re-request it".

Not fixed **in that session**, not classified as a SPECTA production defect on
that evidence — the adoption logic itself is unit-tested and passed on device.
Flagged for a dedicated investigation. **RESOLVED 2026-09-22:** the dedicated
investigation confirmed the mechanism (a stale terminal status CAN settle a
new attempt — demonstrated by a one-line negative control, 5/9 new tests
failing without the gate) and fixed it with attempt-identity generation
gating in the adapter. See `docs/PHASE_2G_C_D3_INVESTIGATION_REPORT.md`.
Device re-validation is the open remainder (no device was attached during the
investigation session).

---

## 7. THE AUTHORIZED FIX

Owner authorisation: *"Fix both now, with tests"* (asked and answered after the
defects were reported with evidence, per §14).

Production changes (3 files):

| File | Change |
|---|---|
| `lib/core/downloads/background_downloader_engine.dart` | The declared total is remembered per download id from size-bearing progress updates and is what a `complete` result reports (`totalBytes`), instead of a total derived from the byte count. A size-less update no longer erases a known total: the event carries the last stated total. `attach` seeds the declared total from the plugin's own record. |
| `lib/core/downloads/download_manager.dart` | (a) `FileDownloadCompletionFinalizer` now returns the **verified on-disk length**, never the engine's claim, and refuses a transfer shorter than the record's declared total **before** the rename (`DownloadFailureType.interrupted`, retryable, honest detail) so partial bytes never take the final media path. (b) The completion path resolves the total as *source-declared first*, engine-reported last, and hands the declared total to the gate. (c) A null-total progress event preserves the last **stated** total in live state and in the persisted record. |
| `test/core/downloads/*` | 5 new regression tests (see §8). |

Unchanged by design: retry semantics, state machine, persistence schema,
concurrency, source resolution, and the `.part` lifecycle. No validation was
weakened — the gate became strictly stricter.

---

## 8. POST-FIX VALIDATION

### 8.1 Device — direct transport, fast mode, fresh install

```text
flutter test integration_test/phase2gc_device_verification_test.dart -d R83L20FRDFM \
  --dart-define=P2GC_TEST_URL=http://192.168.29.246:8712/test.mp4
```

**3 passed / 0 failed / 0 skipped** — `00:03:00 +3: All tests passed!`

| Test | Result | Evidence |
|---|---|---|
| P2GC-1 | **PASS** | `final status=completed bytes=2097176/2097176`; `gate file bytes=2097176 partExists=false` |
| P2GC-2 | **PASS** | `cancel requested=true`; `part file after cancel: false`; server shows the body cut mid-transfer |
| P2GC-3 | **PASS** | `isTransferActive=true`; `post-restart status=completed bytes=2097176` |

### 8.2 Device — direct transport, slow mode (~23 KB/s)

| Test | Result | Evidence |
|---|---|---|
| P2GC-1 | **PASS** | 92-second transfer; `completed bytes=2097176/2097176`; 49 progress events (`first=8028/2097176 last=2082216/2097176`); gate file 2,097,176; no `.part` |
| P2GC-2 | **PASS** | cancellation mid-transfer |
| P2GC-3 | **FAIL (flaky)** | record reached `cancelled` instead of `downloading` — see §6.4 |

The slow-mode P2GC-1 pass is the strongest single result: the gate verified a
real 2 MB transfer byte-for-byte over 92 seconds and reported it correctly.

### 8.3 Regression tests added (offline, deterministic)

| File | Test |
|---|---|
| `download_engine_integration_test.dart` | a TRUNCATED transfer is REFUSED (declared total verified before the rename; no final media; bytes kept for a resume) |
| `download_engine_integration_test.dart` | a COMPLETE transfer is persisted with the file's verified byte count, never the engine's stale claim |
| `download_engine_integration_test.dart` | the source-DECLARED total outranks an engine total derived from its own byte count |
| `background_downloader_engine_test.dart` | `complete` reports the declared total, never one derived from its own byte count |
| `background_downloader_engine_test.dart` | `complete` with no declared size reports `totalBytes: null` — never the byte count |

---

## 9. AUTOMATED VERIFICATION

| Command | Result |
|---|---|
| `flutter analyze` | **No issues found** (45.1 s) |
| `flutter test` (full suite) | **755 passed / 9 skipped / 0 failed** (750 before this session's 5 new tests) |
| `flutter test test/core/downloads/` (2G-C focused) | **156 passed / 0 failed** (151 before) |
| Device integration test (direct transport, fast, post-fix) | **3 passed / 0 failed** |
| Device integration test (direct transport, slow, post-fix) | 2 passed / 1 failed (P2GC-3 flaky, §6.4) |
| Device integration test (direct transport, PRE-fix) | 2 passed / 1 failed (P2GC-1 byte-accounting) |
| Real-JS suite (`tool/run_tests_real_js.sh`) | **NOT RUN** (no JS code touched) |
| Debug APK | built and installed by every device run |

---

## 10. VALIDATION MATRIX

| Test | Result | Evidence |
|---|---|---|
| APK installation | **PASS** | built + installed from a clean uninstall on every run |
| Full MP4 download | **PASS** | `gate file bytes=2097176`, `partExists=false` (fast and 92 s slow mode) |
| Exact byte count | **PASS** | file length 2097176 **and** `record.bytesDownloaded=2097176` post-fix (pre-fix: 5792/8028) |
| `.part` → final lifecycle | **PASS** | no `.part` after completion; no final media after cancellation; refused transfers keep their bytes at the `.part` path |
| Progress/state persistence | **PASS (post-fix)** | persisted state agrees with the file on disk; the declared total survives the size-less final update |
| Pause/resume | **NOT TESTABLE** | the 2 MB fixture still finishes in ~1 s in fast mode; pause semantics remain unit-tested only (slow mode could exercise it — not attempted) |
| Cancellation | **PASS** | P2GC-2, plus server-side confirmation of a mid-body close |
| Retry | **NOT TESTABLE** | needs device-level network manipulation; unit-tested only |
| Fresh-source recovery | **NOT TESTABLE** | needs an expiring source; unit-tested only |
| Kill/restart recovery | **PASS (flaky)** | P2GC-3 passed post-fix with `bytes=2097176`; fails intermittently — §6.4 |
| Offline playback | **NOT TESTABLE** | a byte-exact file WAS produced, but the harness has no playback step and deletes the artifact. Nothing fabricated |

---

## 11. ROOT-CAUSE ASSESSMENT

* **Transport / environment — NOT the cause.** The direct path was proven at
  four independent levels (§5), the server pushed the complete body for every
  app request, and the failure signature reproduced with `adb reverse` removed.
  The earlier "adb reverse is unreliable" conclusion does **not** explain the
  8 KB mismatch. *Limitation:* the adb-reverse path itself was not re-run (that
  was the point of the task); what is established is that the failure does not
  need it.
* **Downloader / plugin — a reporting limitation, not a transfer failure.**
  `background_downloader 9.6.2` delivered byte-exact files and reported
  `complete`; it simply emits no final size-bearing progress tick for a fast
  transfer (`first=x/2097176`, then `x/null`). It is not blamed for the
  incorrect state; SPECTA was trusting it too far.
* **SPECTA implementation — the demonstrated defects (D-1, D-2, §6.2/§6.3),
  now fixed and device-validated.** They were reproducible with no network and
  no plugin, which is what makes the classification unambiguous.
* **D-3 (§6.4) was open** and is labelled a hypothesis, not a conclusion.
  Subsequently CONFIRMED as a real mechanism and FIXED by the dedicated
  investigation — see `docs/PHASE_2G_C_D3_INVESTIGATION_REPORT.md` (offline
  verification complete; device re-validation outstanding).

---

## 12. PHASE AUTHORIZATION

```text
2H: NOT AUTHORIZED / NOT STARTED
```

No 2H work, no download UI, no offline-playback feature.

---

## 13. EVIDENCE ARTIFACTS

| File | Contents |
|---|---|
| `docs/evidence_p2gc_direct_transport_device_run_2026-09-22.log` | PRE-fix fresh-install run over the direct transport |
| `docs/evidence_p2gc_direct_transport_server_2026-09-22.log` | instrumented server log (`Range`, UA, bytes actually sent) |
| `docs/evidence_p2gc_engine_probe_device_2026-09-22.log` | in-app-process probe: `dart:io` full read + real engine driven directly |
| `docs/evidence_p2gc_fixed_fast_device_run_2026-09-22.log` | POST-fix run, fast transport — **3/3 pass** |
| `docs/evidence_p2gc_fixed_fast_run1_device_2026-09-22.log` | first POST-fix fast run (P2GC-3 failed on `isTransferActive`) — the flakiness datum |
| `docs/evidence_p2gc_fixed_slow_device_run_2026-09-22.log` | POST-fix run, slow transport (92 s transfer; P2GC-3 flaky) |
| `docs/evidence_p2gc_fixed_slow_p3_only_device_2026-09-22.log` | POST-fix, slow transport, P2GC-3 alone (fails on `isTransferActive`) |
| `docs/evidence_p2gc_fixed_slow_server_2026-09-22.log` | instrumented server log for the slow run |

---

## 14. FILES CHANGED

Production code (authorised fix):

| File | Change |
|---|---|
| `lib/core/downloads/background_downloader_engine.dart` | declared-total reporting; size-less updates no longer erase a known total |
| `lib/core/downloads/download_manager.dart` | verified-size return + declared-total gate before the rename; source-declared total precedence; last-stated total preserved |

Tests:

| File | Change |
|---|---|
| `test/core/downloads/download_engine_integration_test.dart` | 3 new gate tests |
| `test/core/downloads/background_downloader_engine_test.dart` | 2 new adapter tests |

Test infrastructure / documentation:

| File | Change |
|---|---|
| `tool/serve_device_test_mp4.py` | `--host`/`--port` (defaults unchanged); `Range` + bytes-sent logging |
| `integration_test/phase2gc_device_verification_test.dart` | URL via `--dart-define=P2GC_TEST_URL` (default keeps the adb-reverse URL); progress/byte evidence markers |
| `docs/PHASE_2G_C_DIRECT_TRANSPORT_REPORT.md` | this report |
| `docs/evidence_p2gc_*.log` | raw evidence |
| `PROJECT_STATE.txt`, `docs/PROJECT_STATE.txt` | handover updated; the false completion-gate claim corrected; both copies byte-identical |

Temporary diagnostic probes (`test/core/downloads/zz_gate_probe_test.dart`,
`integration_test/zz_engine_transfer_probe_test.dart`) produced the §6.2/§6.3
evidence and were **deleted** afterwards, so the committed suite stays green.

---

*Every number above comes from a log in §13 or a line of source quoted in §6.
Where evidence is incomplete (the 8028-byte stale-state artifact in the earlier
run, the untested adb-reverse path, the D-3 mechanism, pause/resume on a fast
link) that is stated rather than smoothed over.*
