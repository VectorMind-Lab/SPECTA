# SPECTA — CODEBASE INVESTIGATION REPORT (2026-09-20)

Scope: read-only sweep for bugs, gaps and latent risks across `lib/`, `test/`,
`tool/`, `android/`, build config, and packaging. No features added; one
1-line defensive fix applied (§1). Verification: `flutter analyze` clean,
`flutter build apk --debug` SUCCESS after the fix; the APK's merged manifest
was inspected binary-decoded to confirm the permission is present exactly once.

## 1. Fixed this session (1 line, verified)

**`android/app/src/main/AndroidManifest.xml` — explicit INTERNET permission.**
Until now SPECTA's own manifest declared no permissions at all; the INTERNET
permission only arrived through a transitive plugin manifest merge. This is a
fragile implicit dependency: swapping or updating that plugin would silently
strip networking from release builds (the failure mode would be invisible
until the app cannot reach any source). The permission is now declared
explicitly with a comment explaining why. Rebuilt and verified: the merged
APK manifest contains exactly one INTERNET entry. (No functional change —
the merged manifest before and after is identical.)

## 2. Confirmed clean (checked, not guessed)

- No `TODO`/`FIXME`/`HACK` markers anywhere in `lib/`, `test/`, `tool/`.
- No empty `catch` blocks; error paths either classify or propagate.
- Only two `debugPrint` sites, both legitimate (extension channel logging,
  media_kit init failure).
- `DownloadManager` internals: retry timers are clock-abstraction based and
  disposed-guarded; `dispose()` cancels engine attempts and clears all
  transient maps; `_liveProgress` entries are removed on terminal
  reconciliation (no stale-progress leak into later states); every
  early-return in result reconciliation still frees the attempt slot
  (the 2G-B slot-leak fix is intact).
- No unsafe JSON type coercions (`as int`/`as bool`/`as Map`) in the
  discovery/metadata/extension-runtime parsing hot paths — those layers use
  defensive parsing (hardened in 2B/2C).
- No secrets or hardcoded credentials in `lib/` (the only `apiKey` reference
  is the settings KEY constant for the user-supplied TMDB key; the value
  lives in local settings, not code).

## 3. Latent risks — documented, deliberately NOT fixed (need your decision)

1. **Release build signs with debug keys.** `android/app/build.gradle`'s
   release block still carries Flutter's default TODO ("Signing with the
   debug keys for now"). Fine for development; any public distribution
   requires a real keystore + signing config decision.
2. **No `minifyEnabled`/`shrinkResources` config** — release APKs will be
   larger than necessary and unminified. Harmless, but worth deciding before
   2G-C adds a native downloader library.
3. **Phase 1 security carry-overs (pre-existing, documented in PROJECT_STATE):**
   no CPU/memory ceiling for extension JS (a runaway script can occupy the
   isolate), trust classification is data not enforcement (unverified
   extensions still install and enable), redirect targets are not re-checked
   against the scheme allow-list, non-UTF-8 bodies are returned lossy.
4. **`android.permission.DUMP` appears in the merged manifest** (present in
   the pre-fix APK too). It is characteristic of debug/profile tooling and
   DUMP is a signature-level permission normal Android apps cannot actually
   hold, but it should be re-checked in the RELEASE APK before any public
   build (debug APKs merge debug-tooling manifests).
5. **Single-device verification** — all device evidence is one Samsung A06
   (Android 16). TV D-pad flows and older Android versions remain untested
   on hardware.
6. **2G-B boundary reminder:** no real transfer exists yet; the download
   manager is intentionally unreachable from the UI until 2G-C provides the
   engine adapter.

## 4. Verdict

No functional defects found in the shipped code. The one structural
vulnerability found (implicit INTERNET permission) is fixed and verified.
Items in §3 are decisions/awareness items, not bugs.

```text
flutter analyze:        No issues found
flutter build apk:      SUCCESS (debug, manifest fix verified in merged output)
flutter test:           NOT RE-RUN after the 1-line manifest change (manifest
                        is outside Dart test scope; full suite was green at
                        commit 8d966b8 and no Dart code changed since)
```
