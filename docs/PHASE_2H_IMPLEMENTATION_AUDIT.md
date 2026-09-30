# SPECTA — Phase 2H Implementation Audit

Phase: **2H — Extensions Integration & Lifecycle Foundation**
Date: 2026-09-23
Status: **PHASE 2H COMPLETE**
Scope: application-level extension installation and lifecycle only. No real
extension, no official catalogue, no repository created, no push.

---

## 1. Scope

Phase 2H makes the already-existing extension runtime a properly managed,
persistent, application-level subsystem:

```
valid extension file → manifest validation → trust verification →
registration → persistent installation state → enable/disable state →
Extension Manager → runtime instance → actual extension operation
```

and the state must survive an application restart. The runtime itself, the
manifest format, the signing protocol, the capability model, the request
policy, Source Manager, MediaKit and DownloadManager are all **reused
unchanged**.

Explicitly out of scope (and not done): the first real movie-site reference
extension, the official extension catalogue, the `SPECTA-Extensions`
repository, extension update/rollback product flows, TMDB, web UI.

## 2. Starting Repository State

- HEAD `4ca3cdd` (`fix(phase2g): finalize stale attempt event isolation`), branch `master`.
- `origin/master` `7fcb0cc` — **nothing pushed**, and nothing was pushed in this phase.
- Pre-existing uncommitted work preserved, not reverted and not overwritten:
  - `M PROJECT_STATE.txt`, `M docs/PROJECT_STATE.txt`, `M README.md`, `M docs/README.md`
    (the 2G-C 166/166 wording correction recorded by the entry audit).
  - `?? docs/PHASE_2H_ENTRY_AUDIT.md`, `?? docs/SPECTA — Coding AI Master Prompt — Phase 0_ …md`
    (untracked; the latter is unrelated and was left untouched).
- No destructive git command was used (`reset --hard`, `clean`, forced checkout,
  rebase and history rewriting were all avoided).
- Baseline verified before any edit: `flutter analyze` CLEAN;
  `flutter test test/core/extensions/` = 299 passed / 0 failed / 9 skipped.

## 3. Existing Architecture Reused

Verified against source, not assumed from reports. Reused without modification:

| Area | Artefact |
| --- | --- |
| Manifest + API gate | `lib/core/extensions/manifest.dart` (`SpectaApiVersion`, `ManifestParser`, `ManifestValidator`) |
| Contract | `contract/` — operations, capabilities, `ExtensionSource`, result models |
| Trust | `verification/` — `SpectaSigningProtocol`, `SignatureVerifier`, `TrustedKeys` |
| Runtime | `runtime/extension_runtime.dart`, `flutter_js_sandbox.dart`, `controlled_runtime_api.dart`, `request_policy.dart` |
| Persistence | `manager/drift_extension_registry.dart`, Drift tables in `SpectaDatabase` |
| Manager | `manager/extension_manager.dart` (extended, not rewritten) |
| Health | `identity/extension_health.dart` (descriptive only) |

The extension subsystem already reached the app graph via
`manager/extension_providers.dart` + `SpectaStartup`; discovery, metadata,
sources, playback, library and downloads already consumed it. That wiring is
untouched.

**Verified as already complete** (and therefore NOT rebuilt): manifest parsing
and validation, API-version compatibility, capability parsing (fail-closed),
Ed25519 verification over manifest + body, `official`/`unverified`
classification, Drift persistence, `install`/`uninstall`/`setEnabled`, failure
logging, `SpectaResult`-based failure isolation.

## 4. Changes Implemented

| File | Change |
| --- | --- |
| `lib/core/extensions/manager/extension_manager.dart` | Install/replace semantics + `_retireRuntime`; `uninstall`, `setEnabled` and `shutdown` now retire runtimes through it |
| `lib/core/extensions/manager/extension_lifecycle_service.dart` | **New.** Application-level lifecycle boundary (`ManagedExtension`, `ExtensionLifecycleService`) |
| `lib/core/extensions/manager/extension_providers.dart` | Added `extensionLifecycleServiceProvider` |
| `lib/features/extensions/state/extensions_state.dart` | **New.** `ExtensionsState` + `ExtensionsNotifier` + `extensionsProvider` |
| `lib/features/extensions/extensions_view.dart` | Placeholder replaced by the real install/manage surface |

No change to the runtime, the sandbox, the request policy, the signing
protocol, the trust model, Source Manager, MediaKit or DownloadManager.

### 4.1 Duplicate IDs, replacement and runtime retirement

`_processManifest` now resolves the record id first, looks up any existing
record with the same id, and — if one exists — retires the live runtime for
that id before persisting anything. Consequences, both tested:

1. A replacement can never leave an earlier version still executing under the
   new record (the registry and the running code can no longer disagree).
2. The user's **disabled** choice and original `installedAt` are carried
   forward. Re-importing a file is not an implicit re-enable.

`_retireRuntime(id)` is the single shutdown path, used by replacement,
`setEnabled(false)`, `uninstall` and `shutdown`; `shutdownAll` iterates it.
Disabling now retires the runtime **before** the flag is persisted.

## 5. Extension Installation

One boundary, and only one:

```
ExtensionLifecycleService.installFromFile(path)
  → ExtensionManager.importExtension(filePath)
      → read file
      → ManifestParser.parse           (malformed ⇒ rejected, registry untouched)
      → SpectaApiVersion.isCompatible  (unsupported ⇒ rejected, registry untouched)
      → _classifyTrust                 (Ed25519 over manifest + JS body)
      → DriftExtensionRegistry.install (insertOnConflictUpdate)
```

Fail-safe properties, each covered by a test:

- A malformed file, a file with a missing required field, an unsupported
  `apiVersion`, an unknown capability, and an unreadable path all return a
  structured `SpectaResult` failure **before** the registry is touched.
- A file cannot become executable if it never passed these gates, because
  `loadRuntime` re-reads, re-parses and re-verifies the file on disk and
  grants only the capabilities it finds there.
- Official status still derives exclusively from cryptographic verification.
  Writing `@signature …` (or any untrusted field) without a valid signature
  yields `unverified`.

## 6. Trust Verification

Unchanged and re-verified by the new restart test:

- `TrustLevel.official` requires a valid Ed25519 signature over
  `SPECTA-EXT-SIG-V1` payload bytes (canonical metadata JSON + JS body) against
  SPECTA's published public key.
- Missing / malformed / wrong-key / tampered signatures ⇒ `unverified`.
- Trust is re-derived from the file at load time; a divergence from the stored
  value is persisted and recorded as a failure (pre-existing 2G-C behaviour,
  retained).
- **No signing key was created, modified, printed, logged, embedded or
  requested.** The persistence test mints its `official` case with a throwaway
  key pair generated inside the test; the production private key remains
  outside this repository, in an offline directory, untouched). `trusted_keys.dart`
  was not modified.

## 7. Persistence

No schema change and no migration: Phase 2H reuses the existing `extensions`
table (`Extensions`, `ExtensionVersions`, `ExtensionFailureLogs`) in
`SpectaDatabase`. No second database, no JSON/SharedPreferences registry, no
cloud backend.

`test/core/extensions/manager/extension_persistence_restart_test.dart` proves
the restart guarantee against a **real on-disk SQLite file**:

- install two extensions (one signed → `official`, one unsigned → `unverified`);
- disable one, shut runtimes down, **close** the database;
- open a **fresh** `SpectaDatabase` + registry + manager over the same file;
- assert: both records present with correct version/author; trust levels
  reconstructed (`official` / `unverified`); the disabled flag survived; the
  enabled view excludes it; the disabled extension cannot load; the trusted
  extension loads **and its trust is re-derived from the file**, still
  `official`.

Also proven: a malformed file never becomes a persisted extension, and a
re-install after a restart still keeps a disabled extension disabled.

Transient runtime objects and QuickJS handles are never persisted.

## 8. Enable/Disable

Persisted in the `extensions` table (`enabled` column) and **enforced by the
manager**, not by UI state:

- `setEnabled(id, false)` → retire runtime → persist flag.
- `loadRuntime(id)` on a disabled extension returns
  `CAPABILITY_ERROR` and creates **no** sandbox (test-asserted).
- `getEnabledExtensions()` (what discovery/metadata/sources consult) excludes
  disabled extensions.
- `setEnabled(id, true)` persists only; the runtime is recreated lazily by the
  next `loadRuntime` (no eager engine allocation).
- A disabled extension cannot keep running through a surviving old runtime,
  because disabling removes it from the manager's runtime map and shuts it down.

## 9. Runtime Lifecycle

The Extension Manager remains the sole owner of runtime lifecycle:

```
install → (enable) → loadRuntime → operate → healthCheck → shutdown/disable/uninstall
```

- `loadRuntime` caches one runtime per id in `Map<String, ExtensionRuntime>`.
- A **failed** load disposes its own sandbox immediately and is never published
  (pre-existing behaviour, re-tested) — so a broken extension cannot leak a
  QuickJS engine.
- Reinstalling an id, disabling, uninstalling and `shutdownAll` all dispose the
  engine.
- No global singleton and no per-operation runtime creation were introduced.

## 10. Failure Isolation

Verified at both the manager level and through the **real engine**:

- A JS engine that fails to evaluate → that extension's load fails; the app and
  every other extension are unaffected.
- Real-engine test: a valid-manifest/invalid-JS extension fails to load while a
  working extension still loads, `search()`es and returns results.
- Every runtime operation returns `SpectaResult<T>`; every manager/coordinator
  path catches `Object`, so no extension exception reaches the UI.
- Failures are recorded in `ExtensionFailureLogs` and surfaced via
  `healthOf()` (descriptive; never auto-disables).
- The UI layer surfaces a structured message for a rejected install / failed
  enable/disable/uninstall; failures are never swallowed silently.

## 11. API Compatibility

`SpectaApiVersion.current = 2`, `supported = {2}` (unchanged). An extension
declaring any other `apiVersion` is rejected at install with
`ExtensionFailureType.unsupported` and a message naming both versions, and
never becomes executable. No speculative forward-compatibility layer was added.

## 12. Capability Enforcement

Unchanged and fail-closed, re-verified end-to-end:

- Manifest `@capabilities` is parsed strictly; an unknown token fails the
  import (test: `search,teleportation` ⇒ `Err`, registry untouched).
- The runtime is constructed with exactly the manifest's capability set; a
  test asserts an extension declaring `search,details` receives exactly those
  and neither `sources` nor `network`.
- An operation needing an undeclared capability returns a `CapabilityFailure`
  (e.g. `getSources` on a `search`-only extension), not a warning, not a
  partial grant.
- The install/lifecycle layer never broadens capabilities: it passes the
  manifest set through and re-reads it from the file at load time.

## 13. Test Coverage

New (43 tests + 1 fixture):

| File | Tests | Covers |
| --- | --- | --- |
| `test/core/extensions/manager/extension_manager_lifecycle_test.dart` | 23 | install boundary (valid/malformed/missing field/unsupported API/unknown capability/missing file), duplicate IDs, replacement + runtime retirement, enable/disable, runtime cleanup, failure isolation, capability fail-closed, lifecycle service |
| `test/core/extensions/manager/extension_persistence_restart_test.dart` | 3 | installed + enabled/disabled + trust survive restart on a real SQLite file |
| `test/core/extensions/integration/extension_lifecycle_real_js_test.dart` | 5 | REAL QuickJS: install → load → capabilities → search/latest → details (movie + series w/ seasons & episodes) → getSources → refreshSource → `request()` → log → healthCheck → shutdown; disable/enable; real-engine failure isolation; lifecycle service |
| `test/features/extensions/extensions_state_test.dart` | 7 | notifier: initial load, install success/failure, enable/disable persistence, uninstall, reload, storage failure containment |
| `test/features/extensions/extensions_view_test.dart` | 5 | UI: empty state, install through the dialog, rejected install, switch disables + persists, remove with confirmation (incl. cancel) |
| `test/support/fixtures/lifecycle_extension.js` | — | deterministic, network-free reference fixture used by the real-engine suite |

The real-JS suite is skipped (honestly, as *unverified*) when the flutter_js
bridge is not loadable, and runs for real when it is.

## 14. Validation Results

| Gate | Result |
| --- | --- |
| `flutter analyze` | **No issues found** |
| `flutter test` (default) | **803 passed / 14 skipped / 0 failed** |
| `flutter test` with the flutter_js bridge on `PATH` | **817 passed / 0 skipped / 0 failed** |
| `test/core/extensions/` + `test/features/extensions/` (bridge active) | **351 passed / 0 failed** |
| `test/core/extensions/` (default) | 325 passed / 14 skipped / 0 failed |
| `flutter build apk --debug` | **SUCCESS** — `build/app/outputs/flutter-apk/app-debug.apk`, 237,656,613 bytes |

Reproduction notes (environment, measured):

- Flutter 3.47.4 / Dart 3.13.3 at `H:\flutter`; `PUB_CACHE=H:\pub-cache`;
  the project path contains a space (`SPECTA APK`).
- `tool/run_tests_real_js.sh` builds a Windows-style path via `cygpath`; in Git
  Bash that mangled the entry so the bridge still did not load. Putting the
  POSIX directory on `PATH` directly
  (`/h/pub-cache/hosted/pub.dev/flutter_js-0.8.7/windows/shared`) loads the
  bridge and the real-engine tests run. This is an environment/tooling detail,
  not a product defect; the script was left unchanged (outside Phase 2H scope)
  and the evidence is recorded here.

**One transient failure was observed and investigated.** On the first
full-suite run,
`test/core/discovery/discovery_coordinator_test.dart › provenance is preserved
across extensions through the full pipeline` failed once. It is a pre-existing
**order-sensitive** test: the discovery harness shares ONE `ScriptedJsSandbox`
across extensions and the test asserts the canonical title produced by the
first search script to be consumed. It passed in isolation immediately
afterwards, and passed on the next full-suite run (`817/0/0`) and on the default
run (`803/14/0`). The failing file was not modified by Phase 2H (Phase 2H
touches no discovery code), and nothing was weakened or skipped. Recorded as a
pre-existing flake, not classified as environmental without evidence.

The known intermittent Drift/Dart-isolate test-fixture race documented at
2G-C did not reproduce in this session's runs.

## 15. Security Review

Nothing was weakened; explicitly re-checked:

- **Network policy** (`request_policy.dart`) untouched: scheme allow-list,
  method allow-list, URL length, request/response size caps, redirect cap,
  per-hop re-evaluation, credential-header hygiene, private/loopback host
  blocking (name, IP literal, DNS resolution).
- **Signing protocol / verifier / trusted key** untouched; no key created,
  read, printed or logged.
- **Capability enforcement** untouched and fail-closed; the new lifecycle layer
  cannot grant or widen capabilities.
- **Sandbox boundary** untouched: only `specta_request` and `specta_log`
  channels; `fetch`/`XMLHttpRequest`/`require`/`process`/Dart bindings remain
  unavailable (proved by the existing real-engine test, still green).
- **No new dependency** was added (`pubspec.yaml` unchanged).
- **No new attack surface**: the install path validates, verifies and persists
  a local file; it opens no network connection, and the UI takes a file path
  rather than granting any filesystem capability to extensions.
- An untrusted extension still cannot claim `official`; a disabled extension
  cannot participate; an invalid extension cannot become executable.

## 16. Known Limitations

- The install UI takes a **local file path**; there is no file-picker
  dependency, so no in-app file browser. On Android the user must know the path
  (e.g. a downloaded `.js`).
- The imported file lives at its original path; SPECTA does not yet copy it to
  app-private storage and does not content-hash verify at load. Load-time trust
  re-classification from the file **is** enforced, so a swapped file loses
  `official`.
- No extension update/rollback product flow: `saveVersion`/`rollback` remain
  unreachable (no snapshots are ever created).
- No quarantine state; health remains descriptive and never auto-disables.
- QuickJS still has no CPU/memory ceiling and the runtime is a restricted-API
  boundary, not an OS sandbox (unchanged, documented at Phase 1).
- Device/emulator validation was **not** performed for Phase 2H itself: no
  attached device in this session. The real-engine coverage is host-side via
  flutter_js (QuickJS on Windows) plus the pre-existing on-device Phase 1/2E/2F
  /2G-C runs; the Android debug APK builds cleanly.
- One pre-existing order-sensitive discovery test flake (§14).

## 17. Explicit Non-Goals

Not implemented, by design: the first real movie-site extension; the
`SPECTA-Extensions` repository; the official/remote extension catalogue;
catalogue download, refresh, version detection or offline cache; extension
update/rollback; TMDB or any external metadata provider; HLS offline
downloading; DASH; Media3/ExoPlayer replacement; VPN; DRM/anti-bot/paywall/
access-control/authentication bypass; arbitrary native/filesystem/device APIs;
cloud backends (Supabase/Firebase); web or desktop dashboards. No existing
completed subsystem (Source Manager, MediaKit, DownloadManager, runtime,
signing, request policy) was modified.

## 18. Next Phase — Reference Extension

The next controlled step (2I) is to build **ONE real reference extension** and
use it as an end-to-end integration test:

```
search() → details() → (series: seasons/episodes) → getSources() →
Source Manager (validate + rank) → MediaKit playback
```

It must be legally appropriate, must not bypass DRM/authentication/paywalls/
anti-bot controls, and should be installed through the Phase 2H boundary
proven here. Only after that should the official catalogue / `SPECTA-Extensions`
repository be considered.

## 19. Final Verdict

| Acceptance criterion | Verified |
| --- | --- |
| Existing extension runtime reused, not rewritten | ✔ |
| Extension installation/import boundary works | ✔ |
| Manifest validation works | ✔ |
| API compatibility enforced | ✔ |
| Trust verification integrated | ✔ |
| Official/unverified distinction preserved | ✔ |
| Extension identity deterministic | ✔ |
| Duplicate IDs handled (replace, single identity) | ✔ |
| Extension state persisted | ✔ |
| Enable/disable persisted | ✔ |
| Application restart restores extension state | ✔ (real SQLite file) |
| Runtime lifecycle managed by Extension Manager | ✔ |
| Runtime cleanup verified (failed load, disable, replace, uninstall, shutdownAll) | ✔ |
| One extension failure does not break others | ✔ (fake + real engine) |
| Capability enforcement remains fail-closed | ✔ |
| Existing request security policy intact | ✔ |
| Source Manager / MediaKit / DownloadManager intact | ✔ |
| No real extension created | ✔ |
| No official extension repository created | ✔ |
| No catalogue overreach | ✔ |
| No unauthorized source-access mechanism added | ✔ |
| Tests added for implemented behavior (43 + fixture) | ✔ |
| `flutter analyze` clean | ✔ |
| Relevant tests pass | ✔ |
| Real-JS tests pass (bridge active) | ✔ |
| Documentation updated accurately | ✔ |
| PROJECT_STATE copies identical | ✔ |
| README copies identical | ✔ |
| Phase 2H audit created | ✔ |
| No unrelated modifications | ✔ |
| No push performed | ✔ |

**PHASE 2H COMPLETE.**
