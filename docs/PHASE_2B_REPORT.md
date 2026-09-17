# SPECTA — Phase 2B Report: Search / Discovery Pipeline

**Date:** 2026-09-17
**Sub-stage:** Phase 2B — SEARCH / DISCOVERY PIPELINE ONLY
**Predecessor state:** Phase 1 COMPLETE (real-device verified 2026-09-16);
Phase 2A COMPLETE (2026-09-17); private `VectorMind-Lab/SPECTA` in sync.

Nothing from Phase 2C–2H was started. This report records only what was
actually implemented and measured in this session.

---

## 1. SCOPE

Implemented: the discovery layer of the approved pipeline —

```
user query → SearchRequest
  → enabled extensions (ExtensionManager)
  → parallel discovery (capability-gated runtimes)
  → per-extension outcome isolation
  → normalization (SPECTA-owned)
  → deduplication (SPECTA-owned)
  → unified SPECTA discovery results (+ provenance)
  → Search UI
```

**DISCOVERY FINDS. SPECTA DECIDES.** Extensions only discover; SPECTA
normalizes, deduplicates, and owns the result model. No metadata (2C), no
source resolution/ranking (2D), no player (2E), no persistence (2F), no
downloads (2G), no catalogue (2H).

## 2. IMPLEMENTATION (files)

New — `lib/core/discovery/`:
- `discovery_models.dart` — `SearchRequest`, `DiscoveryReference`,
  `DiscoveryItem`, `DiscoveryOutcomeKind`, `ExtensionDiscoveryOutcome`,
  `DiscoveryResult`.
- `discovery_normalizer.dart` — raw `SearchResult` → normalized
  `DiscoveryObservation` (or drop), key-title computation.
- `discovery_deduplicator.dart` — central identity/merge policy.
- `discovery_coordinator.dart` — round execution (parallel, isolated,
  bounded), aggregation, `DiscoveryService` + `discoveryServiceProvider`.

Modified:
- `lib/features/search/search_state.dart` — real session notifier over the
  2A query provider (no competing provider): statuses, generation-based race
  protection.
- `lib/features/search/search_view.dart` — real results UI (debounced live
  query, unified cards with provenance, honest failure/empty states).
- `lib/core/extensions/runtime/extension_runtime.dart` — search/latest
  parsing hardened (see §5).

New tests: `test/core/discovery/` (3 files), `test/features/search/` (2
files), `test/support/discovery_test_harness.dart`, plus 4 robustness tests
in `test/core/extensions/runtime/extension_runtime_test.dart`.

## 3. MODELS

Existing Phase 1 models were **reused** — `SearchResult`, `MediaType`
(movie/series only), `ExtensionRecord`, `ExtensionRuntime`,
`ExtensionManager`, `SpectaFailure`/`SpectaResult`. No duplicate
representations were introduced; the brief's `Movie/Series/Season/Episode`
names already exist in the Phase 1 contract (`result_models.dart`) and are
untouched — 2B did not need new shapes for them.

New 2B models are discovery-layer only:
- `SearchRequest` — query + page; `normalizedQuery` (trim/collapse
  whitespace); `isValid` (blank query or page < 1 never dispatches).
- `DiscoveryReference` — (extensionId, url, cover) — one extension's
  contribution; the URL is the extension-internal reference for the future
  `details(url)` call of 2C/2D. Never rendered by UI.
- `DiscoveryItem` — unified work: stable key, title, type, year, cover, and
  the ordered `references` list (provenance). `isCrossExtension` reflects
  merges.
- `ExtensionDiscoveryOutcome` — success / skipped / failed per extension,
  failures carried as `SpectaFailure` data (no thrown exceptions escape).
- `DiscoveryResult` — unified items + per-extension outcomes + droppedCount
  + page; helpers `allQueriedFailed`, `noExtensionAvailable`.

No playback/source URLs were added to discovery results. Search results are
provenance + identity, not streams.

## 4. EXTENSION INTEGRATION

- UI never touches a runtime; everything goes through the Phase 1
  `ExtensionManager` (`getEnabledExtensions` → `loadRuntime` →
  `callOperation`). No second extension interface, no sandbox bypass, no
  capability bypass.
- Only **enabled** extensions are candidates. The authoritative capability
  check is the runtime's own granted set (re-read from the manifest at
  load); an enabled extension without `search` is **skipped**, not failed.
- A failed runtime load is a **failed outcome** — the record stays enabled
  (no permanent disable on a single failure).
- One extension failing cannot crash the round; outcomes are isolated and
  aggregated.

## 5. RUNTIME BOUNDARY HARDENING (conflict-audit fix)

The Phase 1 runtime's search/latest parser silently defaulted an
unrecognized `type` (e.g. `"anime"`) to `movie` — violating the brief's
"unsupported types must be rejected or safely ignored". Fixed:
`_parseSearchResults` now **skips** entries with unsupported types, missing
title/url, or non-object rows; a fully-invalid list parses to an empty
success rather than failing the operation. No existing test pinned the old
behavior (verified before changing); 4 new tests pin the new behavior.

## 6. NORMALIZATION POLICY

- Title/URL trimmed; blank title/URL → dropped; > 512 chars (title or URL)
  → dropped (protocol-noise guard); blank cover → null.
- Type: movie/series only (anything else was already refused upstream).
- Tolerated, never invented: missing year (stays null), missing cover.
- Title casing preserved for display; a case/punctuation/whitespace-
  insensitive `keyTitle` is precomputed for dedup.
- Provider-specific references (`raw`, `url`) are never altered or
  discarded.

## 7. DEDUPLICATION + PROVENANCE POLICY

- Identity key = `(keyTitle, type, year)` — never title alone.
  - Casing/whitespace/punctuation variants merge ("THE MATRIX" /
    "the matrix").
  - Different years do NOT merge (remakes stay separate); a year never
    merges with a missing year; different types never merge; similar but
    different titles never merge.
  - Two observations that both lack a year share the `none` year bucket
    (same key); provenance preserves both references.
- Exact repeats from the SAME extension (id+url) are ignored; the same URL
  from two DIFFERENT extensions is kept (both are provenance).
- **Mandatory provenance rule:** the same work from N extensions becomes
  ONE `DiscoveryItem` with N ordered references — nothing is deleted.
  Title/type/year/cover never mutate after first observation (cover is
  filled only if absent).
- Within one extension, same identity + different URLs stays as two
  references (provider catalogue data SPECTA has no authority to collapse).

## 8. CONCURRENCY, TIMEOUTS, RACES

- Parallel fan-out via `Future.wait`, capped at `maxConcurrency = 6`
  extensions per round; `maxResultsPerExtension = 100` caps a pathological
  response; `perExtensionTimeout = 20 s` per extension (bounded below by
  the runtime's own 30 s operation timeout and the request policy's
  timeouts).
- Every failure is converted into `ExtensionDiscoveryOutcome.failed` —
  `TimeoutException`, `JsEvalException`, sandbox crashes (`StateError`),
  and non-JSON responses are all isolated; healthy extensions still
  contribute.
- **Race protection:** `SearchSessionNotifier` stamps each round with a
  monotonic generation; a completed round applies only if it is still the
  newest ("bat"→"batm"→"batman" can never interleave). `reset()`
  invalidates in-flight rounds. Disposal invalidates too. The UI additionally
  debounces 400 ms.
- Tested deterministically with a scripted sandbox (per-call outcomes,
  per-call-index hang simulation, coordinator timeout override seam).

## 9. PAGINATION / CACHING / DATABASE / DEPENDENCIES

- **Pagination:** the extension contract's `search(query, page)` is
  honoured end-to-end (`SearchRequest.page` → runtime → `DiscoveryResult.page`
  → `SearchState.page`); page-2 dispatch is verified by test. The load-more
  UI is deliberately deferred; the service boundary needs no change for it.
- **Caching:** none added. No persistent search storage, no Drift table.
- **Database:** untouched — no schema change, no migration, zero risk to
  2F/2G.
- **Dependencies:** zero new packages. No pubspec change.

## 10. SEARCH UI / TV COMPATIBILITY

- Reuses the approved visual identity and existing widget kit; no redesign.
- Debounced live query; unified result cards (poster fallback, type · year,
  provenance line "Found on N extensions"); honest states for empty,
  partial failure, total failure, and no-extensions.
- D-pad/touch: the text field keeps focus after results render (verified by
  widget test), results are focusable via the existing `SpectaFocusWrapper`,
  no focus trap, no mouse-only assumptions.
- No raw exceptions/stack traces ever reach the UI (verified by test that
  internal error text does not render).

## 11. SECURITY AUDIT

- No secrets, keys, tokens, or credentials introduced (full staged-diff
  scan before commit).
- No weakening of JS restrictions, capability gates, the controlled request
  layer, or signing/integrity. Search results are inert data; no code
  execution path from results.
- Extensions still have no access to the database, filesystem, or anything
  beyond the declared capabilities.

## 12. CONFLICT AUDIT (design, before and after)

- No duplicate models/providers/interfaces were created (reused
  `SearchResult`, `MediaType`, manager/runtime, `spectaSearchQueryProvider`).
- Found and fixed: runtime type-defaulting conflict (§5); a doc/comment
  contradiction in the deduplicator (null-year semantics) — implementation
  kept, comment corrected.
- Future-compatibility: `DiscoveryItem.references` carries exactly what 2C
  (details resolution) and 2D (per-extension source resolution) will need;
  no hidden coupling to metadata, sources, player, or persistence; no
  discovery rewrite will be required by later phases.

## 13. VERIFICATION (all actually run)

- `flutter analyze`: **No issues found!** (clean).
- `flutter test` (full suite): **340 passed, 9 skipped, 0 failed.**
  Baseline after 2A was 274+9; this sub-stage adds **66 tests**:
  - normalization: 12 (valid/malformed/boundary/optional/preservation)
  - deduplication: 19 (exact/casing/whitespace/punctuation/year/type/
    similar titles/provenance/ordering/within-extension)
  - coordinator: 15 (round assembly, multi-extension dedup, drop counting,
    provenance end-to-end, failure isolation, timeout cut-off, all-failed,
    crash isolation, malformed output, non-JSON response, pagination,
    service wrapper)
  - search state: 11 (all seven statuses, blank query, stale-round
    rejection, reset rejection, page reporting)
  - search UI: 4 (idle, live round + focus retention, total failure
    sanitization, clear-to-idle)
  - runtime hardening: 4 (unsupported type skip, missing fields, all-invalid
    list, latest parity)
  - Tests run against the REAL Phase 1 `ExtensionManager` path (file-based
    extension load → manifest → capability grant → operation call), not a
    mock of it.

## 14. DEVICE / BUILD STATUS

- **Android device: NOT REQUIRED / NOT PERFORMED.** 2B is pure Dart
  pipeline + widget UI; `adb devices` shows no device attached. The Phase 1
  Galaxy A06 verification is NOT reused as 2B verification. Device
  verification of live extension search belongs to the sub-stage that first
  runs real extension JS on-device.
- **Build: NOT REQUIRED** this sub-stage (no toolchain/platform change; no
  new dependency). Phase 1 build record stands.

## 15. KNOWN LIMITATIONS

- No installable extension exists yet (catalogue is 2H), so on-device
  discovery with a real remote provider is future work; the pipeline is
  verified against contract-conformant test extensions.
- The scripted sandbox models extension responses without executing JS;
  real-engine execution remains covered by the Phase 1 real-engine test
  group (9 tests, skipped without a JS bridge on PATH, as documented).
- Load-more UI deferred (service boundary ready).
- Dedup is exact-identity: cross-extension merging without a year on one
  side stays separate by design (a metadata layer in 2C may later resolve
  these conservatively — that is 2C's decision, not discovery's).

## 16. STATUS SUMMARY

- 2A COMPLETE · **2B COMPLETE** · 2C–2H NOT STARTED · SPECTA-Extensions not
  created · main repo still PRIVATE.
- **STOPPED AT: PHASE 2B BOUNDARY.** Next authorized sub-stage (when
  authorized): 2C — Metadata.
