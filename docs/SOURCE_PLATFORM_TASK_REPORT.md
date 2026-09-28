# SPECTA OPEN SOURCE PLATFORM — TASK REPORT (2026-09-28)

Branch: `source-system-run`. Working copy: `H:\dev\SPECTA`.
This document supersedes the framing of the previous requirements exchange and is
the live task record for the open-platform work.

## 1. CURRENT PRODUCT REQUIREMENT (owner, authoritative)

SPECTA is an **open source platform**. Any user must be able to create, import or
provide their own source and use it with the app — a JS file they wrote, a
community source, a file import, a URL, or a source in a different existing
source/extension format.

Governing rules for the work below:

1. **Do not reinterpret** "open" as "only JS that follows the existing SPECTA
   contract". The native contract is ONE supported format, not the only one.
2. **Do not turn an implementation problem into a product decision.** The
   question is "how can SPECTA support this format?", not "how do we keep it
   out?". "Different header" is never a sufficient rejection reason by itself.
   A source may be rejected only for a concrete, stated security/runtime reason.
3. **"Open" is bounded.** The runtime stays sandboxed. No native code execution,
   no bypassing DRM/CAPTCHA/anti-bot, no token or cookie theft, no protected
   media extraction, no private device data, no native permissions for source JS.
4. **Provenance and compatibility are separate axes.** A source can be unofficial
   *and* compatible. The green dot means **official provenance only** (verified
   Ed25519) and must never block a compatible user or community source.
5. **No provider allowlist**, no hardcoded provider names, no copying a
   third-party provider repository into SPECTA as official data.
6. The official `SPECTA-Extensions` catalogue repo is **public**. **No token or
   any secret** in the APK, assets, `repository.json`, JS, logs or docs.
7. Node scheme unchanged: official `Node 0, A, B, C`; user `Node 1, 2, 3`;
   only Node 0 undeletable; each source is its own node and individually
   enabled/disabled; OFF is not DELETE; do not invent numbering-after-deletion
   rules; do not assume Node 0 has highest priority.

## 2. FILES INSPECTED (before any change)

| Area | File | What it showed |
|---|---|---|
| Sources UI | `lib/features/extensions/extensions_view.dart` | `_Header` uses `SingleChildScrollView(scrollDirection: Axis.horizontal)` (line 552) — the clipping/scroll cause. `_ExtensionCard` builds 3 rows plus a conditional update row. `SpectaCard` default padding is `EdgeInsets.all(16)`. |
| Install boundary | `lib/core/extensions/manager/extension_manager.dart` | `_processManifest` is the single gate. `ManifestParser.parse` (line 146) is the only parser; a foreign header yields an empty field map and a `Missing required field: id` error. |
| URL install | `lib/core/extensions/manager/extension_lifecycle_service.dart` | `installFromUrl` already converges on `installFromFile` — one boundary, no parallel installer. |
| Contract | `lib/core/extensions/contract/extension_contract.dart` | Operations: `load, capabilities, search, latest, details, getSources, refreshSource, healthCheck, shutdown`. |
| Runtime | `lib/core/extensions/runtime/extension_runtime.dart` | Sandboxed; instantiates a class named `Extension`; only `specta_request` and `specta_log` leave the sandbox; capabilities enforced per call. |
| Manifest | `lib/core/extensions/manifest.dart` | `ManifestParser._startMarker = '// ==SpectaExtension=='`, fields `id/name/version/author/apiVersion/type`. |
| Catalogue | `lib/core/extensions/catalogue/extension_catalogue_client.dart` | `defaultIndexUrl` is already a **public** `raw.githubusercontent.com/SPECTA-Extensions/...` URL. No token in code. |
| Fixtures | `extensions/internet_archive_reference.js`, `test/support/fixtures/lifecycle_extension.js` | The only `.js` files in-repo; both use the native SPECTA header. No foreign-format fixture exists yet. |
| Tests | `test/features/extensions/extensions_navigation_test.dart`, `extensions_view_test.dart` | `tapHeaderAction()` scrolls the horizontal cluster; several tests assert on header labels and card text. |
| Secrets | `.env`, `git ls-files`, token-pattern scan | `.env` untracked + git-ignored, holds only `TMDB_API_KEY`. No token-shaped string in any tracked file or in history. |

## 3. PLANNED CHANGES

- **Docs first** (`SOURCE_SYSTEM_PLAN.md`, `SOURCE_RUN_REPORT.md`, this file):
  mark the manifest-only reading of A1 **SUPERSEDED**, record the eight required
  statements, and correct the private-repo claim. Not a history rewrite — the
  superseded decisions stay visible with their reason.
- **Slice 1 — UI.** Remove the horizontal scroll. Add a full-width, always
  visible `+ Add Source` action opening a sheet of the routes the code actually
  supports. Compact the node card to two rows. All routes keep converging on the
  existing install boundary. No schema change.
- **Slice 2 — compatibility.** Inspect the actual external formats available,
  document each with the §7 template, and add a compatibility layer that
  normalises a supported foreign format into the native internal representation.
  Keep the native format working. Installation and runtime success reported
  separately.

## 4. ACCEPTANCE / STATUS

| Item | Status |
|---|---|
| Docs corrected and superseded decisions marked | see §5 of the plan |
| Slice 1 UI implemented, tested, committed | in progress |
| Slice 2 compatibility, documented per format, tested | not started |
| Full suite + analyzer | to be reported with real counts |
| Real-device verification | to be reported; anything untested marked NOT VERIFIED |