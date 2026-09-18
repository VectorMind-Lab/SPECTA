# SPECTA

Movies and series for Android phone and Android TV. Fast, simple, login-free,
ad-free at the application level, extension-based, and resilient to individual
source failures.

## Status

**Phase 1 — Extension Foundation: COMPLETE — REAL DEVICE VERIFIED (2026-09-16).**
**Phase 2 — application build-out: sub-stages 2A–2E COMPLETE; 2F–2H open.**

`flutter analyze` reports no issues and **446 tests pass** (9 skipped: the
real-engine group needs the JS bridge on `PATH`, `tool/run_tests_real_js.sh`).
The full extension runtime was executed inside the app process on a physical
device — Samsung Galaxy A06, Android 16 — with four consecutive 10/10
integration-test runs: app startup, Drift/SQLite on device, the real QuickJS
FFI sandbox, a controlled HTTPS round trip through the request policy,
capability-gate and policy refusals, and failure isolation with
registry-recorded failures. The Phase 2E player was verified the same way
(5/5 on the same device, including real MP4 and HLS playback and ordered
source fallback). See [`docs/PHASE_2E_REPORT.md`](docs/PHASE_2E_REPORT.md),
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

Only the extension foundation layer exists so far. The metadata manager, source
manager, player and download manager are future work.

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
not an OS-level sandbox. Extension JavaScript runs inside the SPECTA process,
there is no CPU or memory ceiling, and no request policy (URL scheme, method,
headers) is enforced yet. Section 7 of the Phase 1 report states precisely what
is and is not enforced, and section 8 documents what is still provisional about
the signing protocol.

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
| Playback | MediaKit (`media_kit` baseline only, wired to nothing) |

Environment setup is recorded in [`docs/SETUP_LOG.md`](docs/SETUP_LOG.md).

## Project layout

```
lib/
├── main.dart                       entry point; installs the Riverpod scope
├── app/
│   ├── specta_app.dart             root MaterialApp (one app for phone + TV)
│   ├── platform/form_factor.dart   phone / tablet / television layout families
│   └── theme/specta_theme.dart     colour, spacing and focus tokens
├── core/
│   ├── database/                   Drift database, tables, migrations, DAOs
│   ├── errors/                     failure categories, SpectaResult, failures
│   ├── extensions/                 PHASE 1 — extension foundation
│   │   ├── catalogue/              content-type vocabulary
│   │   ├── contract/               operations, capabilities, sources, results
│   │   ├── identity/               trust levels
│   │   ├── manager/                registry (Drift + in-memory), manager, records
│   │   ├── runtime/                runtime, controlled APIs, JS sandbox
│   │   ├── verification/           Ed25519 verifier, trusted public key
│   │   └── manifest.dart           manifest parser/validator, API versions
│   ├── settings/                   canonical persisted setting keys
│   └── storage/                    app-private directory layout
└── features/
    ├── home/                       temporary Phase 0 foundation screen
    └── settings/                   settings state (persisted via Riverpod)
```

Nothing outside `lib/core/extensions/` imports the extension manager, runtime,
verifier, manifest parser or registry yet, so those libraries are not reachable
from `main.dart` and are dropped from the built application.

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

Sub-stages 2F (library, history and persistent watch progress), 2G (download
manager) and 2H (extension catalogue in a separate repository) — plus real
scraper extensions and any external metadata provider (e.g. TMDB). SPECTA
produces no content of its own: it searches, resolves and plays what the
extensions you install provide. The extension foundation, discovery pipeline,
metadata layer, source manager and player surface are all in place and wired
into the running app.

## Documents

| File | Purpose |
| --- | --- |
| `PROJECT_STATE.txt` | Handover state: phase, work done, verification, blockers |
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
  and there is no CPU/memory ceiling for extension JavaScript.
* Trust classification is data, not enforcement: unsigned/unverified
  extensions still install and enable.
* Redirect targets are not re-checked against the request scheme allow-list,
  and non-UTF-8 response bodies are returned as a lossy Latin-1 projection.
* TV detection is a viewport approximation.
* Device tests use public third-party test streams; a stream host that stalls
  (rather than errors) is failed by the player's open timeout and the session
  falls through to the next candidate — measured on device (2026-09-19).
* `cryptography_flutter` and `flutter_js` apply the Kotlin Gradle Plugin; a
  future Flutter release will refuse to build them. Upstream issue, documented
  rather than suppressed.
* Android cmdline-tools absent, so `flutter doctor` warns. Not build-blocking.
