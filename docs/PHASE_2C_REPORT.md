# SPECTA — Phase 2C Report: Metadata Manager / Details Pipeline

**Date:** 2026-09-17
**Sub-stage:** Phase 2C — METADATA / DETAILS ONLY
**Predecessor state:** Phase 1 COMPLETE (real-device verified 2026-09-16);
Phase 2A COMPLETE (2026-09-17); Phase 2B COMPLETE (2026-09-17, commit
`baceadb`); private `VectorMind-Lab/SPECTA` in sync.

Nothing from Phase 2D–2H was started. This report records only what was
actually implemented and measured in this session.

---

## 1. SCOPE

Implemented: the canonical metadata layer of the approved pipeline —

```
DiscoveryItem (2B, with provenance)
        ↓
Metadata Manager (per-reference details() retrieval)
        ↓
SPECTA validation + normalization
        ↓
canonical MetadataItem (movie / series + seasons + episodes)
        ↓
details Riverpod state → minimal details UI
```

Not implemented (future sub-stages): source resolution/ranking/selection
(2D), player (2E), library/progress (2F), downloads (2G), extension
catalogue (2H).

## 2. FILES CHANGED

Created:
- `lib/core/metadata/metadata_models.dart` — MetadataItem,
  ReferenceMetadata, SeriesSeason, SeriesEpisode.
- `lib/core/metadata/metadata_normalizer.dart` — details validation +
  normalization; NormalizedDetails outcome.
- `lib/core/metadata/metadata_manager.dart` — MetadataManager +
  MetadataService + `metadataServiceProvider`.
- `lib/features/details/details_state.dart` — DetailsState,
  DetailsSessionNotifier, `detailsSessionProvider`.
- `lib/features/details/details_view.dart` — minimal details UI.
- `test/core/metadata/metadata_manager_test.dart` (11 tests).
- `test/core/metadata/metadata_normalizer_test.dart` (10 tests).
- `test/features/details/details_state_test.dart` (7 tests).
- `test/features/details/details_view_test.dart` (5 tests).

Modified:
- `lib/core/extensions/runtime/extension_runtime.dart` — details() parse
  hardening (see §4); parse logic extracted to `parseMediaDetails` +
  private row parsers.
- `lib/features/search/search_view.dart` — result cards now open the
  details surface (2C navigation).
- `test/core/extensions/runtime/extension_runtime_test.dart` — 6 new
  parser-robustness tests.

## 3. METADATA ARCHITECTURE

- **Models.** `MetadataItem` is SPECTA's canonical details model: stable
  identity key, canonical title/type/year, best cover/backdrop, and one
  `ReferenceMetadata` per contributing provider reference (provenance
  preserved — nothing is discarded during merging). `SeriesSeason` /
  `SeriesEpisode` are SPECTA's own normalized shapes, detached from any
  provider's JSON. No playback/source fields exist anywhere in the layer.
- **Identity.** The metadata identity key is the SAME evidence key the
  discovery layer established — (normalized title, type, year), `none`
  year bucket included — computed by
  `MetadataManager.identityKey()` using the identical title-key rule.
  No global identity algorithm was invented. Per §10 of the brief,
  cross-provider merging happens only through the references SPECTA
  already merged at discovery; the details layer never merges two
  different works.
- **Metadata Manager.** `metadataFor(item, manager)`: loads each
  reference's runtime through the Phase 1 ExtensionManager, verifies the
  granted `details` capability, calls `details(url)` with a bounded
  per-reference timeout (20 s; test-seam override exists), validates +
  normalizes each payload, and merges valid contributions. Outcomes are
  data (`success` / `skipped` / `failed` / `invalid`), never exceptions;
  one bad reference cannot break the request.
- **Normalization/validation policy** (documented in code, tested):
  - DROPPED: blank title/URL; type mismatch with the discovery-observed
    type; fields over the 512-char protocol-noise guard.
  - TOLERATED: missing optionals (→ null, never invented); blank
    strings → null; empty season list (partial series, not failure);
    duplicate seasons/episodes (first wins after canonical sort);
    unsorted episodes (sorted); malformed season/episode rows skipped
    individually at the runtime parser.
- **Movie vs series.** Both flow through the same pipeline; a series
  payload answering a movie request is dropped (type mismatch), never
  converted. Seasons/episodes exist only for series.
- **Caching/persistence.** None. Phase 2C keeps metadata as Riverpod
  state (in-memory only). No Drift schema change; persistence is
  deferred to 2F where it is actually required. Deliberate, documented.
- **Riverpod.** `metadataServiceProvider` (service over the Phase 1
  manager — no second instance) and `detailsSessionProvider` (session
  state). No competing providers; the discovery layer is untouched.
- **TMDB / external metadata providers.** NOT implemented. No API keys,
  no provider settings, no external calls. The layer is
  provider-agnostic by construction (extensions only).

## 4. RUNTIME PARSER HARDENING (conflict-audit fix)

The audit found the Phase 1 `details()` parser had the same defect 2B
fixed in search parsing: `type` was coerced with
`MediaType.fromCode(...) ?? MediaType.movie`, silently converting
unknown/missing types to movie; a malformed season/episode row threw
into the whole parse; an invalid rating was accepted.

New contract (tested, and consistent with 2B rules):
- `type` is REQUIRED and must be movie/series — otherwise the operation
  fails with a controlled parse error (PARSER failure path), never a
  silent conversion.
- `id`/`title`/`url` must be non-empty strings or the parse fails.
- Rating outside 0..10 → null (bad data, not clamped).
- Malformed season/episode rows are skipped individually; blank URLs,
  non-int numbers, non-object rows.
- Non-object payload → controlled failure.

No existing test pinned the old behavior; all prior runtime tests pass
unchanged.

## 5. EXTENSION BOUNDARY

EXTENSIONS DISCOVER. SPECTA DECIDES — preserved:
- Only the existing `details()` contract operation is used. `getSources()`
  is never called anywhere in 2C code (grep-verifiable).
- Only references from the item's discovery provenance are queried;
  extensions never solicit.
- Capability gate: a reference whose loaded runtime does not grant
  `details` is `skipped`, not failed, and never permanently disabled.
- One failing extension never breaks the request or the app.
- No provider-specific parsing in core; no source/playback coupling.

## 6. DETAILS STATE + UI

- States: idle / loading / success / failure, plus honest partial
  failure (`failedReferences` + `invalidReferences`, ids only — no raw
  exceptions in UI) surfaced as a "details come from N of M sources"
  notice.
- Race protection: monotonic generation guard identical to the search
  session — rapid navigation (A→B) and late stale responses are tested.
- Loading state renders discovery-observed data immediately (title/
  type/year/cover from the DiscoveryItem) — never fabricated metadata.
- UI: poster/title/year/type/genres/rating/runtime header; overview;
  seasons with expandable episode lists for series; Retry action on
  failure. Back button + tappable/selectable cards are D-pad reachable;
  nothing touch-only; no source/player/download affordances (2D/2E/2G).
- Search integration: `_DiscoveryCard` activation now opens the details
  surface (`detailsSessionProvider.open(item)` + push). Cards were
  already focusable for TV traversal in 2B.

## 7. TESTING (exact results)

- flutter analyze: **No issues found!**
- flutter test: **379 passed, 9 skipped (real-engine group), 0 failed**
  (baseline 340+9 → +39 new tests).
- New coverage: details parser robustness (6), normalizer accept/drop
  policy (10), manager pipeline — movie/series/multi-reference/
  isolation/timeout/identity (11), session states incl. races and
  partial failure (7), UI render/retry/TV focus (5).
- Deterministic: controlled fake sandbox + fixtures; no live internet
  services.

## 8. BUILD / DEVICE

- Build: NOT REQUIRED this sub-stage (pure Dart + widget UI; no
  toolchain, manifest, or dependency change).
- Device: NOT PERFORMED — `adb devices` shows no device attached. The
  layer is exercised by unit/widget tests only; recorded honestly.
  A device run of search→details remains open until a device session.

## 9. SECURITY / DEPENDENCIES / DATABASE

- Security: no secrets added; capability/runtime/signature boundaries
  untouched (parser change only tightens validation); repository stays
  PRIVATE; SPECTA-Extensions not created.
- Dependencies: NONE added.
- Database: NO schema change; no generated-file edits.

## 10. KNOWN LIMITATIONS

- Metadata is in-memory only; leaving the details surface drops it
  (by design until 2F).
- Details quality is bounded by what each extension returns; when
  references disagree (e.g. years), the discovery-established identity
  wins and per-reference data stays visible for later phases.
- Load-more/pagination remains deferred as documented in 2B.
- Details UI is intentionally minimal (metadata only) until later
  sub-stages authorize source/player surfaces.

## 11. CONCLUSION

Phase 2C scope is implemented, tested (379+9/0), analyzed clean,
documented, and committed. 2D–2H were NOT started.
