# Phase C1 report — Anime identity and contract architecture

Date: 2026-09-25
Status: VERIFIED for the C1 scope. C2 was not started.

## Inspected

- `PROJECT_STATE.txt`, `README.md`, `pubspec.yaml`, `analysis_options.yaml`.
- Extension manifest parsing, content types, runtime parsing, and manager lifecycle.
- Discovery normalization/deduplication, metadata models/normalization/manager.
- Drift tables, migrations, generated database code, library DAO, download DAO.
- Existing extension, discovery, database, library, download, metadata, and runtime tests.
- Pre-existing uncommitted worktree changes; none were reset, discarded, or overwritten.

## Implemented

- Added distinct `MediaType.anime`.
- Added `anime` and `movies_series_anime` extension scopes.
- Added `ExternalIds` with defensive positive-integer AniList parsing.
- Added `MediaIdentity.anilistKey` and episode key helper.
- Anime discovery requires an AniList ID and deduplicates by `anilist:<id>`.
- Existing movie/series identity remains `normalized title|type|year`.
- Added optional `contractVersion` parsing:
  - missing: legacy `2.0.0`;
  - anime: `2.1.0` required;
  - malformed values rejected;
  - unsupported future revisions rejected.
- Added runtime search/details `externalIds` parsing.
- Added metadata identity propagation for anime.
- Added persistence-shaped `canonicalId` and `identityVersion` to progress, metadata, and download models.
- Wired canonical identity through library, media references, and downloads.
- Added migration 7 (`contract_version`) and migration 8 (`canonical_id`, `identity_version`).
- Regenerated Drift using build_runner. Generated code was not hand-edited.
- Updated stale schema and content-type expectations.
- Added C1 identity, parsing, dedup, movie/series regression, and restart persistence tests.

## Database

- `schemaVersion`: 8.
- Migration 7 adds `contract_version` to `extensions` and `extension_versions`.
- Migration 8 adds `canonical_id` and `identity_version` to `watch_progress`, `downloads`, and `media_references`.
- Migration SQL is additive; existing rows retain legacy identity version 1.

## Tests executed

Toolchain:

```text
H:\flutter\bin\flutter.bat
H:\flutter\bin\cache\dart-sdk\bin\dart.exe
Flutter 3.47.4
Dart 3.13.3
```

Commands and results:

- `flutter pub get`: passed.
- `dart run build_runner build --delete-conflicting-outputs`: passed; 368 outputs written. The tool reported that `--delete-conflicting-outputs` is removed/ignored in this build_runner version.
- `dart format lib test`: passed; no changes on final run.
- `flutter analyze`: **No issues found**.
- Focused C1/regression suites: **120 passed, 0 failed**.
- Full `flutter test`: **975 passed, 39 skipped, 0 failed**.

The final full-suite log ends with `All other tests passed!`.

## Not performed

- AniList networking.
- Home, Search, or Details wiring.
- Any C2 work.
- API-key use or TMDB API-key work.
- Android build.
- Real-device testing.
- Commit or push.

## Known limitations

- C1 establishes the identity and persistence foundation only; user-facing anime catalogue wiring is intentionally deferred.
- `MediaType.anime` is currently accepted by the contract, but TMDB adapter DTOs explicitly decline anime payloads because TMDB anime support is outside C1.
- Media-reference rows persist canonical identity, but the public `LibraryStore.referencesFor` return model remains the existing `DiscoveryReference` shape; the C1 restart test verifies the persisted columns directly.
- The worktree contains substantial pre-existing uncommitted work. C1 changes are layered on top and were not isolated into a commit.

## Files

C1-specific new files:

- `docs/phase_reports/C1_environment.md`
- `docs/phase_reports/C1_report.md`
- `test/core/c1_anime_identity_test.dart`
- `test/core/c1_persistence_restart_test.dart`

C1 implementation was applied across the existing extension contract, discovery, metadata, library, download, database, and test files. The pre-existing worktree changes remain present.

## Git

No commit or push was authorized or performed. Worktree remains dirty by design.
