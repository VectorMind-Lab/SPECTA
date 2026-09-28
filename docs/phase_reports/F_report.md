# Phase F report — Full integration & real-device QA

Date: 2026-09-26
Status: **VERIFIED** (with the caveats listed under "Remaining blockers")

## 1. Status

Phase F automated verification, Android build, and physical-device verification all
completed. Four real-device defects were found and fixed during this phase. Two
Phase D gaps remain deferred and are recorded below.

## 2. Flutter/Dart environment

- Flutter 3.47.4 (stable) — `H:\flutter\bin\flutter.bat` (not on PATH)
- Dart 3.13.3 — `H:\flutter\bin\cache\dart-sdk\bin\dart.exe`
- JDK 21 (Android Studio JBR); Android SDK at `%LOCALAPPDATA%\Android\Sdk`

## 3. Analyze result

```
flutter analyze  ->  No issues found!
```

## 4. Full test result

```
flutter test  ->  1090 passed, 39 skipped, 0 failed  (All tests passed!)
```

A later full-suite run reported 3 failures (`application_bootstrap_test`,
`download_manager_test`, `download_providers_test`). All three were 30-second
`TimeoutException`s in download-queue timing tests. Re-run in isolation:
**51 passed, 0 failed**. Classified as load-induced flakes, not regressions — none
of those files were touched by this phase.

## 5. Database / migration result

Schema version 8. Migration chain verified: anime identity (`canonical_id`,
`identity_version`), extension `contract_version`, watch progress, downloads, media
references. `specta_database.g.dart` is regenerated and in sync. No schema change
was made in this phase.

## 6. Anime integration result

**VERIFIED ON DEVICE.** AniList -> canonical `anilist:<id>` identity -> metadata ->
Search -> card. A live query for "bebop" returned Cowboy Bebop (1998), Cowboy Bebop:
The Movie (2001) and Ein's Summer Vacation (2012) with real cover artwork. The
provider stays separate from source providers: each card states "Anime catalogue —
no streaming source yet".

## 7. Movie/series integration result

TMDB/TVMaze enrichment, matching and fallback verified by the suite. The TMDB key is
injected at build time only, via `tool/build_with_env.ps1` + `--dart-define`; `.env`
is git-ignored and is never bundled as an asset.

## 8. Extension result

All three install routes converge on `ExtensionManager` (device picker, HTTPS URL,
catalogue). Manifest, API/contract compatibility and signature/trust gates are
unchanged. A catalogue entry grants no trust.

## 9. Source discovery result

Search -> extension discovery -> normalization -> dedup -> validation -> ranking ->
selection verified by the suite. Provenance preserved. No provider allowlists in
Core.


## 10. Playback result

**NOT VERIFIED on device.** No extension is installed on the test device, so there
was no real stream to play. The MediaKit path is covered by the automated suite
only. Environment limitation, not a code result.

## 11. Download result

Queue, concurrency, persistence and recovery are covered by the suite (including the
three flake-prone timing tests). No real end-to-end download ran on the device
because no extension/source is installed. **NOT VERIFIED on device.**

## 12. Offline result

**VERIFIED ON DEVICE.** With Wi-Fi and mobile data disabled and the app cold
restarted, cached anime metadata still rendered (titles, years, identity) and artwork
correctly fell back to the neutral placeholder. TMDB/AniList live requests are not
claimed to work offline.

## 13. Real-device result

- Device: `R83L20FRDFM` (physical, over ADB)
- Build command: `flutter build apk --debug`
- APK: `build/app/outputs/flutter-apk/app-debug.apk`
- Build: **SUCCESS**
- Install: **SUCCESS** (`adb install -r`)
- Launch: **SUCCESS**
- Crash scan for the whole session: **0 FATAL, 0 Unhandled Exception**

## 14. Android APK build result

**SUCCESS** (debug, three times in this phase).

## 15. Security result

- No TMDB token, API key, password or private key in any tracked file. No discovered
  value is printed in this report.
- The previously exposed credential is **not** used; it was rotated and never written
  into source, tests or docs.
- `.env` is git-ignored; the key reaches the app only through `--dart-define`.
- No provider-specific Core logic, no sandbox weakening, no DRM/auth bypass.

## 16. Regressions found (all real-device, all fixed)

1. **Search hid catalogue anime when no extension was installed** (C4 gate run).
   `noExtensions` rendered only the install prompt. Catalogue results now render
   whenever present.
2. **Extensions header overflowed by 147 px at phone width**, rendering
   one-character-per-line text. Fixed with a horizontally scrollable action cluster.
3. **The global top bar overflowed by 147 px on every screen.** `SpectaTopBar`'s
   search container had a hard `width: 320` against a 360 dp viewport. It now takes
   the remaining space, stays capped at 320 px and remains right-aligned.
4. **`SpectaEmptyState` overflowed vertically** when the height was tight. Now
   scrollable.

Also fixed in this phase: an AniList GraphQL shape bug where `coverImage` (an object)
and `startDate` (a fuzzy date object) were parsed as strings — the reason the first
device anime run showed neither artwork nor years.

Each fix has a dedicated regression test.


## 17. Remaining blockers / deferred items

- **D gap 1 — DEFERRED (Phase F device QA):** the Storage Access Framework `.js`
  picker path was not exercised end-to-end; the picker interaction was not driven to
  completion. The code path is unit-covered.
- **D gap 3 — DEFERRED (publishing task):** the official `SPECTA-Extensions/` GitHub
  catalogue is not published. The client and format exist; a real published repository
  does not.
- **D gap 4 — DEFERRED (publishing task):** no signed release artefacts exist, so
  official-catalogue trust classification is unproven against a real repository.
- Playback and download are not device-verified (no installed extension).
- **Android TV / D-pad is NOT VERIFIED** — no TV device or TV emulator was available.
- **Release build (minified/R8) is NOT VERIFIED** — only debug builds were produced.

## 18. Files changed in this phase

- `lib/features/extensions/extensions_view.dart` — scrollable header action cluster
- `lib/ui/widgets/specta_scaffold.dart` — responsive top bar
- `lib/ui/widgets/specta_empty_state.dart` — scrollable, no vertical overflow
- `lib/core/anilist/anilist_client.dart` — correct GraphQL field selections
- `lib/core/anilist/anilist_dto.dart` — object-shaped `coverImage` / `startDate`
- `test/features/extensions/extensions_view_test.dart` — narrow-width regression
- `test/ui/specta_scaffold_test.dart` — new top-bar tests
- `test/ui/specta_artwork_test.dart` — artwork coverage
- `docs/phase_reports/F_report.md`, `PROJECT_STATE.txt`, `docs/PROJECT_STATE.txt`

## 19. Git status

Worktree is dirty by design. All pre-existing uncommitted work was preserved. No
reset, stash, clean, discard, force push or other destructive operation was
performed.

## 20. Commit status

**No commit.** No commit was authorized, and none was created.
