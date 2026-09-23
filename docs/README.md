# SPECTA

Movies and series for Android phone and Android TV. Fast, simple, login-free,
ad-free at the application level, extension-based, and resilient to individual
source failures.

## Status

**Phase 1 — Extension Foundation: COMPLETE — REAL DEVICE VERIFIED (2026-09-16).**
**Phase 2 — application build-out: sub-stages 2A–2F (incl. the 2F resume follow-up), 2G-A/2G-B/2G-C (download foundation, orchestration, AND real engine integration) and 2H (extension integration & lifecycle foundation) COMPLETE; 2I open.**

`flutter analyze` reports no issues and **803 tests pass** (14 skipped: the
real-engine group needs the JS bridge on `PATH`, `tool/run_tests_real_js.sh`;
with the bridge active the run passes 817 with nothing skipped). Two of the
skipped tests are the Phase 2H real-QuickJS lifecycle suite; with the bridge
active the extension suites alone pass 351/351.

**Phase 2H — Extension Integration & Lifecycle Foundation: COMPLETE (2026-09-23).**
The extension runtime is now a properly managed, persistent, application-level
subsystem. There is exactly ONE installation boundary
(`ExtensionLifecycleService.installFromFile` → manager → manifest parse →
API-compatibility gate → Ed25519 trust classification → registry), and the
Extension Manager alone owns enable/disable and runtime lifecycle: disabling
retires the live runtime before the flag is persisted, re-enabling recreates it
lazily, reinstalling an existing id retires the old runtime instead of leaving a
second identity, and uninstall/`shutdownAll` dispose every engine. Installed
extensions, their enabled/disabled state and their trust survive an application
restart — proved against a real on-disk SQLite database that is closed and
reopened. The `Extensions` screen is now the real install/manage surface (list
with name, version, author, trust and lifecycle state; install; enable/disable;
remove). A deterministic local fixture is executed end-to-end through the REAL
QuickJS engine — manifest, capabilities, `load()`, `search()`, `latest()`,
`details()` for movie and series (seasons/episodes), `getSources()`,
`refreshSource()`, `request()`, `log()`, `healthCheck()` and `shutdown()` — and
one broken extension is proven not to disturb a working one. NO real movie-site
extension, NO official extension repository and NO remote catalogue were created
in this phase: that is the next controlled step. See
[`docs/PHASE_2H_IMPLEMENTATION_AUDIT.md`](docs/PHASE_2H_IMPLEMENTATION_AUDIT.md).

The historical post-2G-C numbers were **750 tests pass** (9 skipped;
real-JS 721), including the pre-flight fixes (shared Unicode-aware title
identity, `request({query})` parameter support, whole-request transport
deadline, per-row defensive parsing, load-time trust re-classification, and
the hardened request policy — private-host blocking, per-hop redirect
re-evaluation, credential-header hygiene) AND the 2G-C engine integration
(`BackgroundDownloaderEngine` behind the SPECTA `DownloadEngine` interface,
`SourceManagerDownloadResolver`, full manager integration, 8 new/modified
test files). Previously the suite stood at 618/9 (real-JS 627) after 2G-B.
The download domain is now SPECTA-owned end to
end: schema v5 `downloads` table with a tested v4→v5 migration, an
authoritative Drift store, the Persistence Contract (state survives restart,
no stored streaming URLs, no engine artifacts), a `DownloadManager` with FIFO
queue, concurrency 3 (max 9), persist-before-engine scheduling, bounded retry
with exponential backoff, stale-callback protection, and a replaceable
`DownloadEngine` interface. The real engine adapter — `BackgroundDownloaderEngine`
backed by `background_downloader` 9.6.2 — is COMPLETE and wired into the
production provider graph. Its transfer path is exercised by an integration
test (`integration_test/phase2gc_device_verification_test.dart`) on a
Samsung Galaxy A06 (2026-09-21) with PARTIAL results — 1 of 3 device tests
passed (cancellation); P2GC-1 (real MP4 download) had a byte-count mismatch
(8192 vs 2097176 — transfer chain functional but transfer volume insufficient on device);
P2GC-3 (restart reconciliation) failed on timing (isTransferActive returned false
because the 8KB test transfer completed before the check).
CORRECTION 2026-09-22: that verdict was reached over `adb reverse`, which was
exonerated — the same failure reproduced with it removed, and the real MP4
transfer is reachable DIRECTLY from the device over the LAN. Two
transport-independent SPECTA defects were demonstrated (D-1: a truncated
file accepted as completed; D-2: a correct file persisted as 5792/5792),
then FIXED and DEVICE-VALIDATED: P2GC-1 PASS (2097176/2097176, gate
verified, no .part), P2GC-2 PASS (cancellation), P2GC-3 PASS (12 runs, 3
consecutive on runs 10-12; every failure was environmental — SQLite lock
contention, a mid-transfer LAN reset, or a WorkManager registration race —
never a stale-attempt-event symptom). D-3 (stale event isolation) was
investigated, confirmed by a negative control, and fixed with
attempt-identity gating. Offline: analyze clean; 764 passed / 9 skipped /
0 failed (an earlier full-suite run showed 1 failed — a transient
Drift/Dart-isolate test-fixture race in two DOWNLOAD tests, not a discovery
test and not a D-3 symptom); D-3 suite 9/9; downloads-focused 166/166.
Offline playback is NOT TESTABLE (no product seam). See
docs/PHASE_2G_C_D3_INVESTIGATION_REPORT.md §6 and
docs/PHASE_2G_C_DIRECT_TRANSPORT_REPORT.md.
See docs/PHASE_2G_C_ENGINE_AUDIT.md for full evidence.
The full extension runtime was executed inside the app process on a physical
device — Samsung Galaxy A06, Android 16 — with four consecutive 10/10
integration-test runs: app startup, Drift/SQLite on device, the real QuickJS
FFI sandbox, a controlled HTTPS round trip through the request policy,
capability-gate and policy refusals, and failure isolation with
registry-recorded failures. The Phase 2E player was verified the same way
(5/5 on the same device, including real MP4 and HLS playback and ordered
source fallback), and Phase 2F was verified on the same device too — the
schema v2 → v3 migration ran against the real installed database and the
persistent progress sink wrote and read real rows (2/2). The 2F resume
follow-up verified the same way (3/3): the schema v2 → v3 → v4 migrations and
the durable resume provenance on the real installed database. Continue
Watching and Library items now re-open through the existing pipeline. See
[`docs/PHASE_2F_RESUME_FOLLOWUP_REPORT.md`](docs/PHASE_2F_RESUME_FOLLOWUP_REPORT.md),
[`docs/PHASE_2F_REPORT.md`](docs/PHASE_2F_REPORT.md),
[`docs/PHASE_2E_REPORT.md`](docs/PHASE_2E_REPORT.md),
[`docs/PHASE_1_CLOSURE_REPORT.txt`](docs/PHASE_1_CLOSURE_REPORT.txt) — section
22 is the device verification record — and
[`PROJECT_STATE.txt`](PROJECT_STATE.txt) for the handover state.

Previously PENDING items, now closed:

* `FlutterJsSandbox` is covered by 9 real-engine tests in the suite and by the
  on-device integration run.
* The Ed25519 signing protocol is frozen (SPECTA-EXT-SIG-V1, covering the
  JavaScript body, UTF-8) and the positive path was proven with the production
  key; `TrustLevel.official` is producible and tested.
* Declared capabilities are enforced by the runtime on every operation and
  channel call, with mutation evidence.

Known boundary (measured, not assumed): the JS runtime is a restricted-API
in-process boundary, not an OS sandbox, and the bundled QuickJS bridge enforces
no CPU or memory ceiling. Section 7 of the closure report states precisely
what is and is not enforced.

## Core principle

> **EXTENSIONS DISCOVER. SPECTA DECIDES.**

Extensions search, discover metadata and find media sources. SPECTA owns result
normalisation, deduplication, metadata, source validation, source ranking and
selection, playback, downloads, persistence, watch progress, library, history
and the entire UI. An extension never decides which source SPECTA plays.

## Architecture

```
UI (phone / TV)  →  Riverpod state  →  Core services
                                       ├── Extension manager   → JS sandbox → extensions → external sources
                                       ├── Metadata manager    → providers
                                       └── Media manager       → source manager
                                                                  ├── validation
                                                                  └── ranking / selection
                                                                       ↓
                                                                    Player (MediaKit)
                                                                       ↓
                                          SQLite (Drift)  ←→  library / history / downloads
                                                                       ↓
                                                             Download manager → local media files
                                                                       ↓
                                                              Offline playback
```

The extension foundation (including its Phase 2H install/manage lifecycle),
discovery, metadata, source manager, player and the download orchestration AND
engine layers exist and are wired.

### Extension trust and execution

```
SPECTA CORE  →  EXTENSION MANAGER  →  RESTRICTED JS RUNTIME  →  EXTENSION CONTRACT
```

* Extensions are single `.js` files with a `// ==SpectaExtension==` manifest
  header and a class named `Extension`.
* Trust is cryptographic, never location-based: a valid Ed25519 signature from
  SPECTA's public key yields `official`; a missing or invalid signature yields
  `unverified`. A manually imported extension with a valid signature is still
  official.
* Extensions reach the host only through two channels — `request()` (controlled
  network) and `log()`. `fetch`/`XMLHttpRequest` are never enabled and no
  filesystem, database, contacts, SMS, device-identifier or native bindings are
  registered.

**Read this before relying on that boundary:** it is a restricted API surface,
not an OS-level sandbox. Extension JavaScript runs inside the SPECTA process
and there is no CPU or memory ceiling. An explicit request policy IS enforced
(scheme allow-list http/https, GET/POST/HEAD methods, response-size and
timeout caps, redirect cap) and, since the 2G-C pre-flight, private/loopback
host targets are blocked and every redirect hop is re-evaluated against the
full policy (best-effort host checking; it does not fully defeat DNS
rebinding). Section 7 of the Phase 1 report states the original enforcement
set, and section 8 documents what is still provisional about the signing
protocol.

## Toolchain

| Item | Value |
| --- | --- |
| Flutter | 3.47.4 (stable) |
| Dart | 3.13.3 |
| Flutter SDK location | `H:\flutter` (space-free; see the setup log relocation note) |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` (cmdline-tools absent) |
| JDK | OpenJDK 21 (Android Studio JBR) |
| State management | Riverpod (`flutter_riverpod` + `riverpod`, pinned 3.4.3) |
| Database | SQLite via Drift (`drift`, `drift_flutter`, `sqlite3` native assets) |
| JS runtime | `flutter_js` 0.8.7 (QuickJS on Android) |
| Cryptography | `cryptography` 2.9.0 (+ `cryptography_flutter` 2.3.4) |
| Playback | MediaKit (`media_kit` 1.2.6 — wired to the player in Phase 2E) |

Environment setup is recorded in [`docs/SETUP_LOG.md`](docs/SETUP_LOG.md).

## Project layout

```
lib/
├── main.dart                       entry point; installs the Riverpod scope
├── app/
│   ├── specta_app.dart             root MaterialApp (one app for phone + TV)
│   ├── navigation/                 responsive app shell, destinations, nav state
│   ├── platform/form_factor.dart   phone / tablet / television layout families
│   └── theme/specta_theme.dart     colour, spacing and focus tokens
├── core/
│   ├── database/                   Drift database, tables, migrations, DAOs
│   ├── discovery/                  search pipeline: normalizer, dedup, coordinator
│   ├── downloads/                  download models, failure model, engine seam,
│   │                               DownloadManager, retry policy (orchestration;
│   │                               the real engine adapter is Phase 2G-C)
│   ├── errors/                     failure categories, SpectaResult, failures
│   ├── extensions/                 PHASE 1 — extension foundation
│   │   ├── catalogue/              content-type vocabulary
│   │   ├── contract/               operations, capabilities, sources, results
│   │   ├── identity/               trust levels
│   │   ├── manager/                registry (Drift + in-memory), manager, records
│   │   ├── runtime/                runtime, controlled APIs, JS sandbox
│   │   ├── verification/           Ed25519 verifier, trusted public key
│   │   └── manifest.dart           manifest parser/validator, API versions
│   ├── identity/                   shared media identity: Unicode-aware title key
│   ├── library/                    watch-progress store, LibraryStore + Drift DAO
│   ├── metadata/                   canonical metadata, normalizer, manager
│   ├── playback/                   PlaybackEngine seam, MediaKit engine, progress
│   ├── settings/                   canonical persisted setting keys
│   ├── sources/                    SourcePool, validator, ranker, SourceManager
│   └── storage/                    app-private directory layout
├── features/
│   ├── details/                    details state + view (movie / series)
│   ├── downloads/                  downloads view (honest empty state until 2G-C)
│   ├── extensions/                 extension manager UI + lifecycle state (2H)
│   ├── home/                       Home over design fixtures + real rails
│   ├── library/                    Library / history views
│   ├── playback/                   player surface + race-safe session state
│   ├── search/                     search state + view (live discovery)
│   ├── settings/                   settings state (persisted via Riverpod)
│   └── splash/                     splash branding
└── ui/
    └── widgets/                    focus wrapper, buttons, cards, scaffolds
```

The extension subsystem is reachable from `main.dart` (wired via
`extension_providers.dart` + `SpectaStartup`), exposed to the UI through the
Phase 2H lifecycle service (`extensionLifecycleServiceProvider`), and the
discovery, metadata, source, playback, library and download layers build on it.

## Getting started

```bash
flutter pub get
dart run build_runner build        # Drift codegen (see note below)
flutter analyze
flutter test
flutter build apk --debug
```

`build_runner 2.16.1` removed `--delete-conflicting-outputs`; it is now ignored,
so it is not needed. Codegen is reproducible — a clean run leaves
`lib/core/database/specta_database.g.dart` byte-identical.

Run on a device or emulator:

```bash
flutter run
```

## Not implemented yet (deliberately)

Sub-stage 2I (the first real reference extension), the official extension
catalogue and its `SPECTA-Extensions` repository, extension update/rollback,
and any external metadata provider (e.g. TMDB). SPECTA produces no content of
its own: it searches, resolves and plays what the extensions you install
provide. The extension foundation and its Phase 2H lifecycle (install / enable /
disable / remove / persistence / restart), the discovery pipeline, metadata
layer, source manager, player surface, the persistent library / watch-progress /
history layer, and the download orchestration AND engine adapter
(`BackgroundDownloaderEngine` behind SPECTA's `DownloadEngine`) are all in place
and wired into the running app. Real-device validation of the 2G-C engine was
completed on a Samsung Galaxy A06 (P2GC-1/2/3 PASS, with P2GC-3 passing on 3
consecutive runs); see docs/PHASE_2G_C_ENGINE_AUDIT.md and
docs/PHASE_2G_C_DIRECT_TRANSPORT_REPORT.md for evidence.

## Documents

| File | Purpose |
| --- | --- |
| `PROJECT_STATE.txt` | Handover state: phase, work done, verification, blockers |
| `docs/PHASE_2H_IMPLEMENTATION_AUDIT.md` | 2H report: install boundary, trust verification, persistence, enable/disable, runtime lifecycle, failure isolation, tests |
| `docs/PHASE_2G_B_REPORT.md` | 2G-B report: DownloadManager, queue/concurrency, engine interface, providers, tests |
| `docs/PHASE_2G_A_REPORT.md` | 2G-A report: foundation corrections, Persistence Contract, download architecture decision |
| `docs/PHASE_2F_RESUME_FOLLOWUP_REPORT.md` | 2F resume-by-key follow-up: identity audit, schema v4 provenance, device verification |
| `docs/PHASE_2F_REPORT.md` | Phase 2F (library / history / watch progress) report: schema v3 migration, persistence path, device verification |
| `docs/PHASE_2E_REPORT.md` | Phase 2E (player integration) report: source pipeline, fallback, refresh, device verification |
| `docs/PHASE_2D_REPORT.md` | Phase 2D (source manager) report |
| `docs/PHASE_2C_REPORT.md` | Phase 2C (metadata manager / details) report |
| `docs/PHASE_2B_REPORT.md` | Phase 2B (search / discovery) report |
| `docs/PHASE_2_REPORT.md` | Phase 2A (application/UI foundation) report and the Phase 2 plan of record |
| `docs/PHASE_1_CLOSURE_REPORT.txt` | Phase 1 closure: signing protocol, capability enforcement, device verification record |
| `docs/PHASE_1_REPORT.txt` | Phase 1 second-audit report: defects fixed, exact test counts, security audit, trust model, item-by-item verdict |
| `docs/PHASE_0_REPORT.md` | Phase 0 completion report |
| `docs/SETUP_LOG.md` | Development environment setup record (2026-09-15) |

## Known limitations

* The JS runtime is a restricted-API in-process boundary, not an OS sandbox,
  and there is no CPU/memory ceiling for extension JavaScript (a background
  isolate for the JS engine is a future option; not implemented).
* Trust classification is data, not enforcement: unsigned/unverified
  extensions still install and enable.
* Non-UTF-8 response bodies are returned as a lossy Latin-1 projection.
* Host blocking in the request policy is best-effort (IP literals plus DNS
  resolution before connect); it does not fully defeat DNS rebinding.
* The Phase 2H install UI takes a local file path: SPECTA has no file-picker
  dependency yet, so there is no in-app file browser. Import hardening (copy to
  app-private storage + content-hash verify at load) remains future work;
  load-time trust re-classification from the file is already enforced.
* The extension catalogue, extension update/rollback and the official
  `SPECTA-Extensions` repository do not exist. `saveVersion`/`rollback` remain
  unreachable from any product flow (no version snapshots are ever created).
* Release builds still sign with the debug key and have no minify/shrink
  configuration; a real keystore decision is required before any distribution.
  `android.permission.DUMP` must be re-checked in a release build.
* Android backup is not configured (`android:allowBackup` defaults on); the
  local DB holds watch history — an allowBackup/data-extraction decision is
  pending with the owner.
* Cleartext HTTP is allowed by the request policy (http scheme) and the
  manifest declares no cleartext configuration; to be verified on a release
  build.
* Device verification so far covers ONE device (SM-A065F, Android 16), and TV
  detection is a viewport approximation.
* SPECTA plays content supplied by third-party extensions; app-store
  distribution (for example Google Play) is likely restricted.
* Device tests use public third-party test streams; a stream host that stalls
  (rather than errors) is failed by the player's open timeout and the session
  falls through to the next candidate — measured on device (2026-09-19).
* `cryptography_flutter` and `flutter_js` apply the Kotlin Gradle Plugin; a
  future Flutter release will refuse to build them. Upstream issue, documented
  rather than suppressed. `flutter_js` 0.8.7 maintenance status is a
  dependency risk.
* The project path contains a space (`SPECTA APK`), which already forced
  `kotlin.incremental` off; renaming the directory is recommended but not
  done.
* Android cmdline-tools absent, so `flutter doctor` warns. Not build-blocking.
