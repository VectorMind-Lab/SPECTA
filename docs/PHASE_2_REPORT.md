# SPECTA — Phase 2 Report

**Date:** 2026-09-17
**Phase:** Phase 2 (authorized 2026-09-17) — sub-stage 2A complete
**Predecessor state:** Phase 1 COMPLETE (real-device verified 2026-09-16); GitHub
checkpoint complete (private `VectorMind-Lab/SPECTA`, branch `master`).

This report records only what was actually implemented and measured in this
session. Historical Phase 0/Phase 1 reports are untouched; where they disagree
with current state, this file and `PROJECT_STATE.txt` are current.

---

## 1. AUTHORIZED SCOPE FOR THIS EXECUTION

Phase 2 was authorized in sub-stages (2A UI foundation → 2H extension catalogue
integration) with the instruction to work in controlled sub-stages, not to
attempt everything at once.

**Implemented in this session: PHASE 2A — APPLICATION / UI FOUNDATION.**
Nothing from 2B–2H was started. The full Phase 2 pipeline (search → discovery →
metadata → sources → player → progress → downloads → catalogue) remains open.

## 2. STARTING STATE (inspected, not assumed)

Before writing any code, the source tree was inspected against the brief:

Already present (from the UI restoration session, previously unwired or
placeholder):
- `SplashPage` with the approved branding composition (glowing logo, man
  facing the city, taglines, Enter button, phone/TV layouts).
- `SpectaAppShell` (phone bottom nav / TV sidebar rail, 6 destinations) —
  **not reachable**: `SpectaApp.home` opened the Phase 0 `HomePage` directly.
- UI widget kit (`lib/ui/widgets/`), theme presets + provider (provider
  existed but was never consumed by `MaterialApp`).
- `HomeState` / `MediaItem` / `HeroSpotlightBanner` (design fixtures, unused).
- Placeholder views for Search / Library / Downloads / Extensions / Settings.

Gaps found and closed in this sub-stage (section 4).

## 3. ARCHITECTURE — PRESERVED

- No changes to the extension foundation (`lib/core/extensions/` untouched).
- No changes to the database schema, migrations, registries or runtime.
- No new dependencies (`pubspec.yaml` unchanged).
- Riverpod state pattern (`Notifier`/`NotifierProvider`) as established.
- EXTENSIONS DISCOVER. SPECTA DECIDES. — untouched; no provider logic added.

## 4. WHAT WAS IMPLEMENTED (2A)

### 4.1 Approved launch flow wired
`lib/app/specta_app.dart`:
- `home` is now `SplashPage` — Splash (branding, man facing the city) →
  fade → main app shell — exactly the approved concept.
- `MaterialApp` theme is now driven by `spectaThemePresetProvider`
  (brand default cyan/teal), so the accent system is real, not decorative.

### 4.2 Splash state
- `lib/features/splash/splash_state.dart` (new): persisted
  `app.hasSeenSplash` flag (key existed; now actually written) + shared
  auto-transition delay constant.
- `lib/features/splash/splash_page.dart`: marks completion through
  `SplashState` on transition (best-effort — a storage failure can never trap
  the user on the splash).

### 4.3 Home view (visual, fixture-based, honestly labelled)
- `lib/features/home/home_view.dart` (replaces the delegation stub): hero
  spotlight carousel, Continue Watching / Trending Now / Latest Releases
  rails, type badges, progress bars, poster fallbacks, TV-focusable cards,
  responsive column counts (3 phone / 6 large).
- Content is the supplied design fixture (`HomeState.initial`) — stated in
  the class documentation; nothing pretends to be live data. The Phase 2B
  pipeline replaces the fixture.

### 4.4 Settings view (real controls, persisted)
- `lib/features/settings/settings_view.dart` (replaces the placeholder):
  - Appearance: theme preset chips (5 presets, persisted via
    `SpectaSettingKeys.themePreset`).
  - Downloads: concurrency control (existing notifier, now in Settings;
    default 3 / max 9 preserved).
  - Extensions: auto-update toggle (persisted via
    `SpectaSettingKeys.autoUpdateExtensions`).
  - Diagnostics: the Phase 0 foundation self-check preserved verbatim as a
    diagnostics section (schema version, settings round trip, media dir).
- `lib/features/settings/state/auto_update_state.dart` (new): persisted
  auto-update state (the machinery it configures arrives with 2H).
- `lib/app/theme/specta_theme_provider.dart`: the preset provider now
  restores the persisted choice and persists `setPreset`.

### 4.5 App shell corrections
- `lib/app/navigation/specta_app_shell.dart`:
  - TV-sidebar Auto Update switch wired to the persisted provider
    (was throwaway `setState` state).
  - Sidebar card width fix (`width: double.infinity`) — the shrink-wrapped
    card starved its inner Row and overflowed on narrow layouts.
  - 'Auto Update' label made flexible with ellipsis.
- `lib/ui/widgets/specta_status_badge.dart`: label wrapped in `Flexible`
  with ellipsis — identical visuals at normal sizes; no overflow at
  constrained widths.

### 4.6 Accurate placeholder states
- Search: live query field wired to `spectaSearchQueryProvider` (state ready
  for the 2B pipeline); result area states the real 2B status.
- Library / Downloads / Extensions: message text updated from the false
  "coming in Phase 2" to the precise sub-stage (2F / 2G / 2H) each depends on.

## 5. FILES CHANGED

Modified:
- `lib/app/specta_app.dart` (entry flow + theme wiring)
- `lib/features/splash/splash_page.dart` (splash persistence)
- `lib/app/navigation/specta_app_shell.dart` (persisted switch + overflow fix)
- `lib/app/theme/specta_theme_provider.dart` (restore + persist preset)
- `lib/ui/widgets/specta_status_badge.dart` (overflow-safe label)
- `lib/features/home/home_view.dart` (real visual home)
- `lib/features/search/search_view.dart` (query field + accurate status)
- `lib/features/library/library_view.dart`, `lib/features/downloads/downloads_view.dart`,
  `lib/features/extensions/extensions_view.dart` (accurate statuses)
- `lib/features/settings/settings_view.dart` (real settings UI)

Created:
- `lib/features/splash/splash_state.dart`
- `lib/features/settings/state/auto_update_state.dart`
- `test/widget_test.dart` (rewritten: launch-flow smoke tests)
- `test/features/home/home_page_test.dart` (rewritten: shell coverage)
- `test/app/theme/specta_theme_provider_test.dart` (new, 4 tests)
- `test/features/settings/auto_update_state_test.dart` (new, 3 tests)
- `docs/PHASE_2_REPORT.md` (this file)

Unchanged by design: all of `lib/core/` (database, errors, extensions,
settings keys), `pubspec.yaml`, `android/`, assets, historical reports.

## 6. ARCHITECTURE DECISIONS

1. **Splash on every launch** (approved flow), with `hasSeenSplash` recorded —
   the flag exists so a future "short splash on relaunch" preference builds on
   real state without a schema change.
2. **Home renders the design fixtures now, labelled as fixtures.** The 2B
   pipeline swaps the provider's data source; the UI layer is final-form.
   Alternative rejected: leaving the Phase 0 diagnostics page as Home — the
   approved design already existed unwired.
3. **Diagnostics preserved under Settings** — the Phase 0 self-check remains
   reachable (it also backs the Phase 1 device verification's first test,
   which finds the foundation card inside the app).
4. **Settings only exposes controls backed by real state today.** TMDB API key
   and repository URL keys exist but are intentionally NOT surfaced until 2C/2H
   implement their consumers — no fake configuration screens.
5. **Persisted settings restore asynchronously** (brand/theme default first
   frame, stored value applied when the store answers) — same pattern as the
   existing download-concurrency notifier.

## 7. VERIFICATION (executed this session)

| Check | Result |
| --- | --- |
| `flutter analyze` | **PASS — No issues found** |
| `flutter test` | **PASS — 274 passed, 9 skipped (real-engine group, no JS bridge on PATH), 0 failed** (baseline was 266+9; +8 new tests) |
| `flutter build apk --debug` | see section 9 |
| Device run | NOT REQUIRED — 2A is widget-level UI; no runtime/device-specific code was touched. Phase 1 device verification stands. |
| Secret scan | Clean (tracked files; no new sensitive material introduced) |

New test coverage:
- Launch flow: splash branding renders first; splash auto-transitions to the
  main shell; completion flag persisted (`test/widget_test.dart`).
- Shell: home shows the visual home (not diagnostics); diagnostics under
  Settings; concurrency control persists (`test/features/home/home_page_test.dart`).
- Theme preset: brand default, persist + restore, unknown-name fallback.
- Auto-update: default enabled, persist + restore.

Test-fixed defects (found by the new tests before any device could hit them):
- Sidebar Auto Update card overflow (narrow sidebar).
- Status badge label overflow at constrained widths.

## 8. KNOWN LIMITATIONS (2A)

- Home/Search results are fixtures/stubs until 2B lands — clearly labelled.
- TV form-factor detection remains the documented viewport approximation
  (Phase 1 carry-over; unchanged).
- The splash has no "skip on tap of background" — only the Enter/Start button
  and the auto-timer, matching the approved composition.
- Theme changes apply instantly but are not animated (not in the approved
  design's scope).

## 9. BUILD

Recorded after this report was drafted: see the build line in section 7 and
`PROJECT_STATE.txt` for the measured result. No product dependency changed, so
no toolchain drift was expected.

## 10. REMAINING PHASE 2 WORK (authorized, not started)

- 2B Search/discovery pipeline (SearchResult/MediaItem/Movie/Series/Season/
  Episode models, parallel extension discovery, normalization, dedup).
- 2C Metadata manager architecture (metadata ≠ sources; TMDB as optional
  local-config metadata provider).
- 2D Source manager (pool → validation → ranking → selection; MP4 + HLS v1).
- 2E Player integration (MediaKit surface, retry-through-pipeline, progress).
- 2F Library / history / watch progress persistence.
- 2G Download foundation (queue, pause/resume, ≤3 default / ≤9 ceiling).
- 2H Extension catalogue integration (separate SPECTA-Extensions repo —
  creation deferred until this stage actually requires it).

## 11. NEXT PHASE 2 SUB-STAGE

**PHASE 2B — SEARCH / DISCOVERY PIPELINE**, per the authorized order.
