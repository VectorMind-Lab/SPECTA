# SPECTA — Phase 0 Completion Report

Date: 2026-09-15 · Operator: implementation AI · Status: **verified with corrections**

> **Audit note (read before Phase 1):** an earlier state claimed Phase 0 was
> "completed and verified". That claim was false at the time it was made: the
> Flutter SDK had never been installed, no test had ever been executed, and the
> Android scaffolding did not exist. This report supersedes it. Everything below
> was produced by commands actually run on this machine on 2026-09-15.

---

## A. Verification commands — actually executed, with real results

| # | Command | Result |
| --- | --- | --- |
| 1 | Archive integrity | Size 1,931,293,116 B matched; **first SHA-256 FAILED** (`4ada96ec…`, expected `3117330…`). `unzip -t` isolated exactly one corrupt member inside chunk 04. Chunk re-fetched (`_setup/refetch_chunk4.sh`), reassembled: **SHA-256 OK** `31173300481bd06e377fd55ee84214689648b1817563efd7b450b7b78bdf351a`. Extracted to `H:\flutter`. |
| 2 | `flutter --version` | Flutter **3.47.4** stable · Dart **3.13.3** · Engine `0e228ec8c8` |
| 3 | `flutter doctor` | Flutter OK · Android toolchain warns (cmdline-tools missing, licenses unsigned) · Chrome OK · Windows desktop VS toolchain absent (not needed for SPECTA) |
| 4 | `flutter pub get` | OK — 124 dependencies resolved at pinned versions |
| 5 | `dart run build_runner build --delete-conflicting-outputs` | OK — 45 outputs, `specta_database.g.dart` generated |
| 6 | `flutter analyze` | First run: **12 issues (5 errors)** → fixed (§C) → final: **No issues found** |
| 7 | `flutter test` | First attempt failed on host toolchain; after SDK relocation (§C2): **27 tests, all passed** |
| 8 | `flutter create --platforms=android --org net.specta` | Android scaffolding generated; applicationId corrected to `net.specta.app` |
| 9 | `flutter build apk --debug` | First run: **FAILED** — malformed NDK stub (CXX1101). Stub removed, `ndkVersion` pinned to `27.1.12297006`; rebuild started, AGP provisioning a fresh NDK. **Pending at time of writing** (§E). |

Rule honoured: every number in this report comes from an executed command.
Nothing is projected or assumed.

---

## B. What Phase 0 contains (and only this)

- Riverpod foundation: `ProviderScope` root; providers for database, settings
  store, form factor, download concurrency, foundation status.
- Drift/SQLite foundation: `SpectaDatabase` v1, migration registry (unregistered
  versions throw), `settings_entries` table, `SettingsDao` behind the
  `SettingsStore` interface.
- Platform structure: one codebase for Android phone + Android TV; manifest
  declares `touchscreen required=false`, `leanback required=false`,
  `LEANBACK_LAUNCHER` category and the TV banner.
- Error foundation: `ExtensionFailureType` (8 canonical categories),
  `SpectaFailure` sealed hierarchy, `SpectaResult` (`Ok`/`Err`).
- Test suite: 27 tests (unit, widget, database).
- Documentation: README, PROJECT_STATE, SETUP_LOG, this report.

Deliberately absent (per phase boundary): extension runtime/sandbox, scrapers,
player, downloads, search/streaming UI, TMDB.

---

## C. Defects found during verification (all fixed)

### C1. Code defects — the Phase 0 code had never seen a compiler

Written against guessed APIs; would not have compiled. Fixed:

| File | Defect | Fix |
| --- | --- | --- |
| `lib/app/platform/form_factor.dart` | `FlutterView` used without import | `import 'dart:ui' show FlutterView, Size` |
| `lib/core/errors/specta_failure.dart` | `const ExtensionFailure(...)` reads `type.retryable` at runtime — not const-evaluable | constructor is now non-const; lint `unnecessary_this` fixed |
| `lib/core/database/daos/settings_dao.dart` | 2 unused imports | removed |
| `test/features/home/home_page_test.dart` | Riverpod 3.x no longer re-exports `Override` | import `package:riverpod/misc.dart show Override`; added explicit `riverpod: 3.4.3` dependency (tests import it directly) |
| `test/features/settings/download_concurrency_test.dart` | same | same |
| `test/core/database/specta_database_test.dart` | `package:sqlite3/open.dart` **no longer exists** in sqlite3 3.x (native-assets model) | override removed; sqlite3 3.6.0 resolves its own SQLite native asset under the Dart VM; pubspec comment updated |

### C2. Environment defect — SDK path contained a space

`H:\Projects\App sdk and tools\flutter` broke the native-assets hook runner
(unquoted path in a spawned command). **SDK and pub cache moved to
`H:\flutter` and `H:\pub-cache`**; `GRADLE_USER_HOME=H:\gradle-home`.
(Recorded in the setup log, which documents both the original install location
and the final one.)

### C3. Machine defect — malformed Android NDK stub

`%LOCALAPPDATA%\Android\Sdk\ndk\28.2.13676358` was a 1 KB shell without
`source.properties` (AGP error CXX1101). Removed the stub. `ndkVersion` is
pinned to the healthy `27.1.12297006` in `build.gradle.kts`; the rebuild's AGP
pass is provisioning NDK 28.2 properly, so the pin is a belt-and-braces
fallback for offline/unattended builds either way.

---

## D. Decisions taken during verification (documented, reversible)

1. **`riverpod` becomes a direct dev-visible dependency** — tests import
   `package:riverpod/misc.dart` for `Override` (3.x API surface change). Same
   version as `flutter_riverpod`.
2. **Native-assets sqlite3 path** — no loader overrides anywhere; documented in
   the test file and pubspec.
3. **NDK pin** — see C3.
4. **SDK relocation to space-free paths** — see C2.

No deviation from the agreed architecture (Riverpod / Drift / MediaKit
baseline / net.specta.app / one codebase for phone+TV).

---

## E. Open items at handover

| Item | State | Owner |
| --- | --- | --- |
| `flutter build apk --debug` | Running detached (`apk_build.log`); AGP was provisioning NDK 28.2. Finish and record the APK size. | Phase 1 start |
| Android licenses | `flutter doctor --android-licenses` unsigned (needs cmdline-tools; not required for the build that succeeded past this point) | operator decision |
| cmdline-tools | Absent — only affects `sdkmanager`/licence UX | Phase 1 convenience |
| Form factor TV detection | Still viewport approximation; platform-channel detection is the planned Phase 1 seam | Phase 1 |
| Release signing | Debug-signed only | later phase |

**Closure note (added 2026-09-16, Phase 1 second audit).** The Phase 0 APK
build item is closed: `flutter build apk --debug` succeeds, the APK is
`build\app\outputs\flutter-apk\app-debug.apk`, and its size and the Android
configuration were recorded from the filesystem. The remaining items in this
table (cmdline-tools/licences, TV platform-channel detection, release signing)
are still open and are tracked in `PROJECT_STATE.txt` section 4. This report
remains a dated record of the Phase 0 pass; the current phase state is in
`docs/PHASE_1_REPORT.txt`.

---

## F. Verdict

Phase 0's **engineering foundation is now genuinely verified at the code level**:
analyze clean, 27/27 tests green, codegen reproducible, Android identity and TV
manifest declarations in place. The only unfinished item is the APK artifact
itself (build infrastructure, not code) — tracked in §E and to be closed at the
start of Phase 1 before any extension work begins.

**Handover ready for Phase 1 — Extension Foundation.**
