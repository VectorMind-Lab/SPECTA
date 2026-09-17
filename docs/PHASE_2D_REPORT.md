# SPECTA — Phase 2D Report: Source Manager

**Date:** 2026-09-17
**Sub-stage:** Phase 2D — SOURCE RESOLUTION / VALIDATION / RANKING / SELECTION ONLY
**Predecessor state:** Phase 1 COMPLETE; 2A/2B/2C COMPLETE (`4249ad9`,
`baceadb`, `bcc47e1`); private `VectorMind-Lab/SPECTA` in sync.

Nothing from Phase 2E–2H was started. This report records only what was
actually implemented and measured in this session.

---

## 1. SCOPE

Implemented: the Source Manager layer of the approved pipeline —

```
Metadata references (2C provenance)
        ↓
SourceManager.resolve (parallel getSources over the Phase 1 manager)
        ↓
structural validation → deduplication → ranking
        ↓
SourcePool (selected + ranked fallbacks + per-extension outcomes)
        ↓
source session state (race-safe, core-layer only)
```

NOT implemented (hard boundaries honored): playback/player/MediaKit wiring
(2E), downloads (2G), watch progress (2F), extension catalogue / GitHub
runtime access (2H), real scrapers/providers, DRM or anti-bot handling.

## 2. FILES CHANGED

Created:
- `lib/core/sources/source_models.dart` — QualityPreference (auto/480p/
  720p/1080p/4K), SourceOutcomeKind, ExtensionSourceOutcome.
- `lib/core/sources/source_pool.dart` — SourcePool (selected, fallbacks,
  per-extension outcomes), RankedSource (candidate + provenance + score).
- `lib/core/sources/source_validator.dart` — structural validation.
- `lib/core/sources/source_ranker.dart` — deterministic ranking policy.
- `lib/core/sources/source_manager.dart` — SourceManager.resolve/refresh +
  SourceService + `sourceServiceProvider`.
- `lib/features/playback/source_session_state.dart` — race-safe session
  state (core seam for 2E; deliberately no UI).
- `test/core/sources/source_validator_test.dart` (12 tests).
- `test/core/sources/source_ranker_test.dart` (7 tests).
- `test/core/sources/source_manager_test.dart` (13 tests).
- `test/features/playback/source_session_state_test.dart` (5 tests).

Modified: none outside the new layer. Phase 1 runtime/contract, 2B, and 2C
code are untouched (verified by the full suite staying green).

## 3. SOURCE MODEL & POOL

- The Phase 1 `ExtensionSource` contract model is REUSED unchanged — no
  duplicate source model was created. V1 types remain MP4 + HLS only; no
  DASH, no DRM.
- `RankedSource` wraps a validated `ExtensionSource` with the contributing
  `extensionId` (provenance), the originating `reference`, and SPECTA's
  ranking `score`.
- `SourcePool` is the unified result: `ranked` (best first, deterministic),
  `selected` (recommended candidate), `fallbacks` (the rest, in order —
  2E's fallback list), and `outcomes` (one per queried extension — the
  provenance/health record of the round). Anonymous URL lists are never
  returned.
- Multi-extension provenance (brief §10) is preserved end to end: every
  candidate knows which extension and which reference produced it; the
  same URL from two different extensions stays twice (distinct CDN risk,
  distinct accountability); the same URL repeated by ONE extension
  collapses.

## 4. VALIDATION (structural — decision documented)

- Decision: validation is STRUCTURAL ONLY; no network reachability probes.
  Probing every candidate would make resolution slow, and reachability is
  exactly what playback's failure path (2E) discovers — 2D's fallback seam
  covers it. No network activity happens in this layer.
- Dropped: blank URLs; URLs over 2048 chars; unparseable/scheme-less URLs;
  schemes outside http/https (file://, javascript:, data: etc. are never
  acceptable media locations); unsupported types (defense in depth beyond
  the contract parser); >32 headers; header names with whitespace/control
  characters (injection guard); subtitle tracks without a URL.
- Tolerated: missing quality/label/tracks (never invented); malformed
  optional metadata skipped where it is per-row (subtitles); blank header
  values.
- Defensive limits: at most 100 candidates accepted per extension per
  round (`maxSourcesPerExtension`) before validation, so a 10,000-source
  or repeated-response payload cannot balloon the pool or ranking work.

## 5. RANKING (deterministic, honest)

- Pure and deterministic: same pool + preference → same order. Tie-breaks:
  score → quality tier → type → URL.
- Quality preference model is exactly V1: auto/480p/720p/1080p/4K.
- Under `auto`: higher native quality wins; adaptive streams get a small
  bonus; missing quality is explicitly scored BELOW any known resolution
  (never invented, never discarded).
- Under a concrete preference: the exact match dominates; near matches
  (one step away) beat far matches; missing quality is an acceptable
  fallback, not a match; a fixed stream at the wanted quality slightly
  beats an adaptive one at the same nominal quality.
- NOT "highest quality first" and NOT "fastest URL first". No fabricated
  telemetry: startup/buffering/success-rate terms do not exist yet and
  are not scored; the ranker is pure so 2E can add a health term without
  a rewrite.

## 6. SELECTION, FALLBACK, REFRESH

- `SourcePool.selected` = `ranked.first`; `fallbacks` = the rest. 2E will
  receive a full ordered candidate list and never needs to re-resolve just
  to find alternatives.
- `SourceManager.refresh(extensionId, reference)` uses the EXISTING Phase 1
  `refreshSource(reference)` contract operation (no second refresh
  mechanism). Refresh-unavailable and refresh-failed are represented
  honestly as a null result — a normal handled outcome for 2E's retry
  flow, never a throw.
- 2E compatibility (brief §36): the selected/fallback candidates already
  carry source type, URL, headers, audio tracks, subtitles, quality, and
  the adaptive flag — everything the player contract needs, with no
  Source Manager rewrite.

## 7. EXTENSION INTEGRATION & ISOLATION

- The EXISTING Phase 1 `ExtensionManager.loadRuntime` + `callOperation`
  + `ExtensionRuntime.getSources/refreshSource` and the `sources`
  capability are used. No second runtime, contract, sandbox, request API,
  or capability system was created.
- Per-extension outcomes (success/skipped/failed/invalid) are data — never
  exceptions. One extension timing out, throwing, or returning invalid
  sources never prevents healthy extensions from contributing and never
  permanently disables anything.
- Extensions without the `sources` capability are `skipped`, not failed.
- Timeout: 20 s per extension (test seam for shorter); the runtime's own
  operation timeout remains in force beneath it.

## 8. CONCURRENCY / RACES

- Parallel fan-out bounded at 6 extensions (same cap as discovery).
- `SourceSessionNotifier` reuses the 2B/2C monotonic-generation pattern:
  Episode 1's late result can never overwrite Episode 2 (tested), and
  reset rejects in-flight rounds (tested).
- No player UI, no screens, no playback controls were added (hard
  boundary §22). The session state is the clean service seam 2E consumes.

## 9. SECURITY / DATABASE / DEPENDENCIES

- Security audit: scheme allow-list + host/path presence (no arbitrary URL
  execution surface added); header name validation (no control-character
  injection); defensive response caps (no memory blowup from hostile
  output); subtitle URLs required; no credentials/cookies handled; all
  extension access remains behind the existing capability + request-policy
  boundary; nothing claims OS-level isolation. Secret scan of the diff and
  new files: CLEAN.
- Database: NO schema change (pools are in-memory; 2F/2G decide durable
  source data later). No Drift files touched.
- Dependencies: NONE added (brief §37 satisfied: zero new packages).
- No GitHub dependency at runtime (2H boundary intact).

## 10. CONFLICT AUDIT (post-implementation)

- Phase 1: untouched (runtime, capabilities, request policy, sandbox,
  health) — full extension suite green.
- 2B: discovery layer untouched; `DiscoveryConcurrency` reused concept
  without coupling.
- 2C: metadata layer untouched; `ReferenceMetadata.referenceUrl` is the
  exact input the Source Manager consumes (clean join, no rewrite risk).
- 2E/2F/2G/2H: nothing prematurely implemented (no player, no progress, no
  downloads, no catalogue); all seams documented above.

## 11. TESTING (exact results)

- flutter analyze: **No issues found!**
- flutter test: **418 passed, 9 skipped (real-engine group), 0 failed**
  (baseline 379+9 → +39 new tests: 12 validator, 7 ranker, 13 manager,
  5 session state, 2 shared-harness additions).
- Deterministic fixtures only — no live internet, no real providers, no
  GitHub, no TMDB.

## 12. BUILD / DEVICE

- Build: NOT REQUIRED (pure Dart core/service layer; no toolchain,
  manifest, or dependency change).
- Device: NOT PERFORMED — `adb devices` shows no device attached. Recorded
  honestly; the layer is exercised by unit tests only.

## 13. KNOWN LIMITATIONS

- No reachability probing: a structurally valid source may still fail at
  playback time (by design; 2E's fallback consumes 2D's ranked list).
- No playback telemetry in ranking yet (nothing measurable exists before
  the player; 2E can extend the ranker).
- Refresh is only as available as each extension makes it; unavailability
  surfaces as an honest null.
- Per-extension response caps (100) are generous but finite; an extension
  with more legitimate candidates per page than that would be truncated
  (no known real case).

## 14. CONCLUSION

Phase 2D scope is implemented, tested (418+9/0), analyzed clean,
documented, and committed. 2E–2H were NOT started.

**DISCOVERY finds. METADATA identifies. SOURCE MANAGER resolves, validates,
ranks and selects. PLAYER (2E) will play.**
