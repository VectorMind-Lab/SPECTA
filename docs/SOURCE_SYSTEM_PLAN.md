# SPECTA SOURCE SYSTEM — IMPLEMENTATION PLAN

Status: **PLAN ONLY — NOT STARTED. No code written against this document without
explicit owner approval.**

Date: 2026-09-27
Scope: Slices 1–7 below. **Slice 8 (SPECTA official distribution / Node 0 sync)
is BLOCKED and deliberately excluded** pending the real repository layout and a
genuine SPECTA-compatible sample file (decision G).

---

## 0. DECISIONS OF RECORD (owner-confirmed)

| # | Decision | Consequence |
|---|---|---|
| A1 | No origin allowlist. The `// ==SpectaExtension==` manifest + API-version gate stays exactly as is. | No validation logic is removed anywhere. |
| A2 | Internals keep `ExtensionManager` / `ExtensionRecord` / `extension_id` / `extensions` table. Only user-facing copy changes. | No class/table renames. No persistence rename. |
| A3 | TMDB / TVMaze / AniList attribution untouched. | Zero changes in those files. |
| A4 | Node order is user-reorderable. Node 0 is **not** pinned to the top; the user may move it anywhere. It stays undeletable regardless of position. | Persisted `node_order`, independent of `node_locked`. No hidden pinning rule. |
| A5 | Stable numbering. Deleting Node 2 does NOT renumber Node 3. | Labels must be **persisted**, not derived. Migration required. |
| A6 | Official -> `Node 0`, `Node A`, `Node B`, `Node C`… User -> `Node 1`, `Node 2`, `Node 3`… The two numbering spaces never collide. | Two independent allocators over one persisted label. |
| A7 | Delete = full wipe: DB rows, failure logs, rollback version, **and the `.js` file on disk**. | `uninstall` gains a file-deletion step (currently missing). |
| B | Real on-device error captured. | See §1. Diagnostic **copy** fix only; the gate itself is correct per A1. |
| C | The source card shows **only** the neutral node label. Name / author / id move to a details sheet. | Card rewrite; no site name can reach the card. |
| D | A **separate persisted "undeletable" flag**, independent of `TrustLevel.official`. **Only the actual Node 0** carries it. A user-imported SPECTA-signed file does NOT. | New column + delete guard. |
| E | Priority is **informational only**: a percentage shown on Source Health. It does **NOT** affect `SourceRanker`. | `source_ranker.dart` and `source_manager.dart` are **untouched**. |
| F | SSRF protection unchanged: HTTPS-only, no `http://`, no LAN/loopback, no escape hatch. | Zero change. Verified live on device. |
| G | Real repo layout + sample sources pending. | Slice 8 not started. |
| Q1 | **The install ROUTE decides the node space, not the signature.** Official sync -> official space. Every user route (file, URL, user repository) -> user space, **even if the file is SPECTA-signed**. A signed file keeps its green dot. | `node_space` is assigned by the caller, never inferred from `TrustLevel`. |
| Q2 | After Z: `Node AA`, `Node AB`, `Node AC`, … (Excel-style bijective base-26). | Pure function, exhaustively tested. |
| Q3 | Percentage mapping as proposed, **except** a node with no recorded activity yet shows **"No data yet"** instead of 100%. Display only. | Derived from real recorded state, never invented. |
| Q4 | Only Node 0 is undeletable. Node A / B / C are official but **deletable**. | Tested both ways. |
| Q5 | User can reorder Node 0 anywhere. No pinned rule. | Tested. |

---

## 1. FINDING B — real on-device error capture (DONE, no code)

Device: `R83L20FRDFM` (SM_A065F, Android 16). App: `net.specta.app` v1.0.0.
Route: Extensions tab -> Install extension -> SAF picker -> Install.

| Test | Input | Exact on-screen text |
|---|---|---|
| 1 | 142 B random JS, no manifest marker | **That file is not a valid SPECTA extension: Missing required field: id** |
| 2 | `maxmovies-cc.js` (12,687 B), `// ==Extension==` dialect, `@package` instead of `@id` | **That file is not a valid SPECTA extension: Missing required field: id** |
| 3 | URL `http://192.168.1.50/my_source.js` | **That does not look like a valid extension link.** |
| 4 | Well-formed unsigned `==SpectaExtension==` source | **Installed Dev Test Unsigned 1.0.0 (unverified).** — card shows `Unverified`, **no green dot**, `Ready`, `Enabled`, deletable |

**Root cause.** `ManifestParser._startMarker` is `// ==SpectaExtension==`.
`maxmovies-cc.js` declares `// ==Extension==` — a different ecosystem's dialect — so
`extractHeader()` returns an **empty** map and `parse()` fails on the first field it
reads, `id`. `describeUnimportableSource` then falls through to
`'That file is not a valid SPECTA extension: ${cause.message}'`, which is literally
true but tells the user nothing.

**This is NOT a provider allowlist and NOT an ID allowlist.** It is the manifest
contract gate, which decision **A1 requires us to keep**. The defect is the
EXPLANATION, not the rule.

**Fix (Slice 1, copy only, zero security impact):**

| Case | Current | Proposed |
|---|---|---|
| No `==SpectaExtension==` marker at all | `…: Missing required field: id` | "This file has no SPECTA source header. A SPECTA source is a .js file that begins with `// ==SpectaExtension==`." |
| Marker present, a required field missing | `…: Missing required field: id` | keep the field name, use "source" wording |
| JSON document | existing message (already good) | keep |

No `@package` fallback is invented. That would be unspecified behaviour.

---

## 2. SLICE 1 — User-facing copy: "Extension" -> "Source"

**No DB. No behaviour change. Lowest risk, immediately visible.**

Files (copy only):
- `lib/app/navigation/specta_destination.dart` — nav label `Extensions` -> `Sources`
- `lib/features/extensions/extensions_view.dart` — title, empty state, `Install extension` -> `Install source`, tooltips
- `lib/features/extensions/extensions_url_dialog.dart` — dialog defaults
- `lib/features/extensions/extensions_catalogue_sheet.dart` — sheet copy
- `lib/features/extensions/extensions_repository_sheet.dart` — sheet copy
- `lib/features/extensions/state/extensions_state.dart` — `errorMessage` fallbacks
- `lib/features/settings/settings_view.dart` — `_ExtensionsCard` title, auto-update line
- `lib/core/errors/specta_failure.dart` — ~94 user-facing `message` strings
- `lib/core/extensions/manager/extension_manager.dart` — the §1 diagnostic fix only

Tests to change: `extensions_view_test` (`'Extensions'`, `'Install extension'`,
`'Remove extension'`, `'0 installed'`, `'Unverified'`), `settings_view_test:55`,
`search_view_test` (`'Search across your enabled extensions'`), `developer_dot_test`.
Tests to add: every distinct failure message asserted with source wording; the two new
manifest-diagnostic branches.

**GATE:** `flutter analyze` clean, full suite green, no behavioural diff.

---

## 3. SLICE 2 — Node identity model (pure logic, no DB, no UI)

New file: `lib/core/extensions/identity/source_node.dart`

Pure functions, zero I/O, exhaustively testable.

```
SourceNodeSpace.official   -> Node 0, A, B, ... Z, AA, AB, AC ...
SourceNodeSpace.user       -> Node 1, 2, 3, 4, ...
```

- `SourceNodeSpace` enum: `official | user`
- A node's `index` is its position **within its own space** — the two spaces are
  independent, so a user node can never be handed an official label and vice versa (A6).
- `SourceNodeAllocator.next(space, assigned)` returns the **lowest free index in that
  space**, reading the `assigned` set. It never computes `max + 1` over a compacted
  list — that is exactly what would renumber on delete (A5).
- `nodeLabel` is derived for **display only**; the stored truth is `(space, index)`.

Tests (pure, exhaustive):
- official: 0->A->B->…->Z->AA->AB (Q2 boundary, both sides of Z)
- user: 1->2->3
- spaces never collide
- allocator fills the first free slot, not the highest + 1
- **deleting Node 2 leaves Node 3 labelled Node 3** (A5, the load-bearing case)
- deleting Node 0 then reinstalling reuses the first official slot as `Node 0`
  (free-slot allocation, not renumbering of survivors)

**GATE:** no DB, no UI, no app behaviour change. Suite identical apart from additions.

---

## 4. SLICE 3 — Node persistence (migration v8 -> v9)

Four additive columns, all defaulted so **no existing row is touched**:

```sql
ALTER TABLE extensions ADD COLUMN node_label  TEXT;                             -- NULL = unassigned
ALTER TABLE extensions ADD COLUMN node_space  TEXT;                             -- 'official'|'user'|NULL
ALTER TABLE extensions ADD COLUMN node_locked INTEGER NOT NULL DEFAULT 0;       -- D: undeletable
ALTER TABLE extensions ADD COLUMN node_order  INTEGER NOT NULL DEFAULT 0;       -- A4: display order
```

- `SpectaMigrations.schemaVersion` 8 -> 9, step registered in `_steps`.
  `specta_database.g.dart` regenerated and committed.
- **Why a migration is unavoidable:** A5 (stable numbering) cannot be derived at read
  time from `(installedAt, id)` — that model renumbers when a node is deleted. The
  label must be stored.
- **Lazy backfill:** rows with `node_label IS NULL` are assigned once, deterministically
  ordered by `(installedAt, id)`, then written. An existing install therefore becomes
  Node 1 on first load, once, and is stable forever after.
- **Space assignment happens at install, from the route (Q1).** The caller passes the
  space; `_processManifest` never infers it from `TrustLevel`. Consequence: a
  SPECTA-signed file the user imports becomes **Node 1 with a green dot**, not Node A.
- Files: `extensions_table.dart`, `migrations.dart`, `specta_database.g.dart`,
  `extension_record.dart`, `extension_registry.dart`, `drift_extension_registry.dart`,
  `in_memory_extension_registry.dart`, `extension_manager.dart`,
  `extension_lifecycle_service.dart`.

Tests:
- a real v8 database file upgrades to v9 with all rows, `extension_versions` and
  `extension_failure_logs` intact
- a fresh `createAll()` produces the same schema
- backfill is deterministic and idempotent
- reinstalling the same id **keeps** its node label
- a reinstall does **not** consume a new number
- signed-file-via-user-route gets user space + green dot


## 5. SLICE 4 — Node 0, the undeletable flag, and a true delete (A7 + D)

- `ExtensionManager.uninstall` refuses when `node_locked = 1`, returning a controlled
  `ExtensionFailure` — never a throw, never a silent no-op.
- **A7 file wipe:** read `record.filePath` **before** the row is deleted, then unlink
  the file inside the same registry operation. Today `DriftExtensionRegistry.uninstall`
  removes versions + failure logs + the row in one transaction but **leaves the `.js`
  on disk** — that is the orphan this slice closes.
- **Guard:** only unlink a path inside SPECTA's own app-private extension directory. A
  path outside it is never deleted (defence against a poisoned `filePath`).
- Delete must retire the runtime first — this already happens
  (`_retireRuntime` precedes `_registry.uninstall`) and is preserved.

Tests:
- Node 0 uninstall refused, node still installed
- Node A (official, unlocked) uninstall **succeeds** (Q4)
- file removed from disk after a successful uninstall
- a file path outside app storage is never unlinked
- uninstall succeeds even when the file is already gone
- disable != delete (OFF keeps the node installed)

**GATE:** suite green + device check of the refusal dialog.

---

## 6. SLICE 5 — The source card shows the node label only (C)

`lib/features/extensions/extensions_view.dart`, card rewritten:

- **Primary line: the node label only** — `Node 0`, `Node 1`, `Node A`.
- The green dot stays exactly where it is, still gated **only** on
  `TrustLevel.official`. It remains a provenance mark, not a quality score.
- `name`, `version`, `author`, `id` move into a **details sheet** behind an info
  affordance.
- Health badge, ON/OFF switch and delete remain on the card.

Tests:
- the card renders the label and **does not** render name / author / id
- the details sheet contains them
- green dot present for signed and absent for unsigned, **coexisting** in one list
- no site name can reach the card

**GATE:** suite green + device screenshot audit.

---

## 7. SLICE 6 — Reorderable order (A4 / Q5)

- `node_order` is edited through a reorder control.
- **Node 0 is not pinned.** No hidden rule, per A4 and Q5.
- `ExtensionLifecycleService.installed()` stops sorting by `(name, id)`. Sorting by
  name means **the provider's chosen name currently decides the display order** — which
  is also a name leak under §16. It returns `node_order` ascending, tie-broken
  deterministically by `node_label` then `id`.

Tests:
- a reorder survives an app restart
- Node 0 can sit last in the list and is still undeletable there
- ties break deterministically
- display order is independent of the source name

**GATE:** suite green + device restart check.

---

## 8. SLICE 7 — Source Health screen (E / Q3)

New screen, node labels only, no site names. Shows **real** existing state only:
`ExtensionHealth` (healthy / degraded / temporarily unavailable / disabled /
incompatible), the recent-failure count, the enabled flag, version, last update.

**Percentage mapping (Q3, display only):**

| Real state | Display |
|---|---|
| no recorded activity yet | **No data yet** |
| healthy, 0 failures | 100% |
| degraded, 1-2 failures | 50% |
| temporarily unavailable, 3+ failures | 10% |
| disabled | 0% |
| incompatible | 0% |

"No data yet" is derived from **real recorded state** (an extension that has never
been loaded and has zero recorded failures), never from a guess.

**`source_ranker.dart` and `source_manager.dart` are NOT touched.** E is explicit that
priority must not override quality ranking, and no automatic "prefer a higher-priority
node even at lower quality" mode is built.

Tests: percentage maps from real facts only; no fabricated state; no site names;
a disabled node reads "Disabled" regardless of its health facts.

**GATE:** suite green + device screenshot.

---

## 9. SLICE 8 — SPECTA official distribution / Node 0 sync — **BLOCKED**

Not planned in detail. Awaiting: the real `SPECTA-Extensions` repository layout, and a
genuine SPECTA-compatible third-party `.js` for honest testing.

No placeholder will be fabricated, and the Zangetsu repository will not be used as
SPECTA data.

**GitHub security (unchanged):** the token currently in
`C:\Users\PORTCR\Music\SPECTA APK\.env` is treated as **compromised and must be
revoked**. It will not be embedded in the APK, committed, or logged. If
`SPECTA-Extensions` is public, no token is required anywhere.

---

## 10. SLICE 9 — Full regression + real-device validation

1. `flutter analyze` clean.
2. Full suite green — the exact count will be reported, not estimated.
3. Release APK built via `tool\build_with_env.ps1`.
4. Device: file import -> node created -> label shown -> enable -> discovery -> resolution.
5. Node 0 undeletable; Node A deletable; user node deletable.
6. Delete removes DB rows **and** the `.js` file.
7. Reorder survives a restart; Node 0 reorderable to last.
8. Three official + one third-party coexisting.
9. No streaming-site name on any source surface — screenshot audit.
10. No `/sdcard/...` path in any UI.
11. An existing v8 install upgrades to v9 without losing anything.

---

## 11. SLICE 10 — Documentation (last, only what is verified)

`PROJECT_STATE.txt`, `docs/phase_reports/`, `docs/PHASE_2H_ENTRY_AUDIT.md`, `README.md`.
Every item records test count, analyze result, build result and device result.
Anything untested is written **NOT VERIFIED**.

---

## 12. NOT IN PLAN / OUT OF SCOPE

- No provider allowlist, ever.
- No `github.com = trusted`, no `telegram = trusted`. Distribution != identity.
- No `Node 0.1` / `Node 0.2` scheme.
- No change to `ExtensionManager` -> `SourceManager` internal renames.
- No change to SSRF policy.
- No change to `SourceRanker` or `SourceManager` resolution.
- No change to TMDB / TVMaze / AniList attribution.
- No GitHub credential in the APK.

**GATE:** migration test green, **plus a real upgrade run on the device** (the phone
currently has a real v8 database).

---

| 1 | 142 B random JS, no manifest marker | **That file is not a valid SPECTA extension: Missing required field: id** |
| 2 | `maxmovies-cc.js` (12,687 B), `// ==Extension==` dialect, `@package` instead of `@id` | **That file is not a valid SPECTA extension: Missing required field: id** |
| 3 | URL `http://192.168.1.50/my_source.js` | **That does not look like a valid extension link.** |
| 4 | Well-formed unsigned `==SpectaExtension==` source | **Installed Dev Test Unsigned 1.0.0 (unverified).** — card shows `Unverified`, **no green dot**, `Ready`, `Enabled`, deletable |

**Root cause.** `ManifestParser._startMarker` is `// ==SpectaExtension==`.
`maxmovies-cc.js` declares `// ==Extension==` — a different ecosystem's dialect — so
`extractHeader()` returns an **empty** map and `parse()` fails on the first field it
reads, `id`. `describeUnimportableSource` then falls through to
`'That file is not a valid SPECTA extension: ${cause.message}'`, which is literally
true but tells the user nothing.

**This is NOT a provider allowlist and NOT an ID allowlist.** It is the manifest
contract gate, which decision **A1 requires us to keep**. The defect is the
EXPLANATION, not the rule.

**Fix (Slice 1, copy only, zero security impact):**

| Case | Current | Proposed |
|---|---|---|
| No `==SpectaExtension==` marker at all | `…: Missing required field: id` | "This file has no SPECTA source header. A SPECTA source is a .js file that begins with `// ==SpectaExtension==`." |
| Marker present, a required field missing | `…: Missing required field: id` | keep the field name, use "source" wording |
| JSON document | existing message (already good) | keep |

No `@package` fallback is invented. That would be unspecified behaviour.

---
