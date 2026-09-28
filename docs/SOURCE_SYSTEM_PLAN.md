# SPECTA SOURCE SYSTEM — IMPLEMENTATION PLAN

Status: **PLAN ONLY — NOT STARTED. No code written against this document without
explicit owner approval.**

Date: 2026-09-27 (Slices 1–7 + 7b done; §13 added 2026-09-28)
Scope: Slices 1–7 below. **Slice 8 (SPECTA official distribution / Node 0 sync)
is BLOCKED and deliberately excluded** pending the real repository layout and a
genuine SPECTA-compatible sample file (decision G).

> **Owner clarification of 2026-09-28 is captured in §13.** It changes Slice 8 from
> "waiting for a repository" to "repository exists, decisions pending". Nothing in
> §0–§12 changed. No code has been written against §13.
>
> **Known pre-existing defect in this file:** lines 318–344 are a stray duplicate of
> §1 (lines 43–69) that predates 2026-09-28. Left in place rather than silently
> rewritten, and flagged here so it is not mistaken for a second decision table.

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

## 13. OWNER CLARIFICATION — 2026-09-28 (requirements only, no code)

**Status: AWAITING WRITTEN CONFIRMATION. No slice is authorised. No code was
written against this section.**

### 13.1 What the owner has now confirmed

| # | Confirmation | Effect on the plan |
|---|---|---|
| H1 | The product is an **open** system. Any user may supply any source, by any route. | Confirms "no provider allowlist" (A1) in spirit. Does **not** yet define what SPECTA can *execute* — see §13.2. |
| H2 | Terminology is **Sources**, never "Extensions", in all user-facing copy. | Slices 1 and 5 already satisfy this. Internals keep `ExtensionManager`/`extension_id` per A2. |
| H3 | Official owner sources are **Node 0** onward; user-imported sources are **Node 1** onward. Node 0 is the owner's GitHub-backed source. | Matches A6 exactly, and re-confirms D/Q4: **only Node 0 is undeletable.** |
| H4 | The green dot marks **official/owner provenance only** — never a quality score, never a site identity. | Matches Slices 5 and 7 as built. Gated only on `TrustLevel.official`. |
| H5 | Node labels (`Node 0`, `Node 1`, …) are the **only** identifier shown on cards and on Source Health. | Already verified on device in 7b. |
| H6 | **No site, brand, provider name, provider-supplied title, or filesystem path** may appear on any source surface. | Zangetsu's own detail page *does* show the provider name — SPECTA will not. |
| H7 | Deleting a node must stop that source from working — the node owns its JS. Deleting Node 0 is refused. | Matches A7 + D as built. |
| H8 | Node 0 pulls its JS from the owner's **private** GitHub repository. | Replaces the "Slice 8 is blocked" state in §9. |

### 13.2 The one genuine contradiction — needs an answer before any code

§9 and the earlier audit concluded that third-party files such as
`maxmovies-cc.js` are rejected because they declare a **different ecosystem's**
header (`// ==Extension==` with `@package`) rather than SPECTA's
`// ==SpectaExtension==` with `@id`. Decision **A1 locks that gate in place.**

H1 says "any source, from anywhere, any type of file."

**These cannot both be true, and this is a decision, not a wording problem.**
An app that executes a `.js` file needs *some* agreed calling contract — SPECTA
has to know which functions to call and what shape they return. So the real
question is which of three things "any type of source" means:

- **(a) Arbitrary executable JS** — the gate is removed or loosened and SPECTA
  attempts to run whatever it is given. Highest openness; also the highest risk
  (untrusted code in-process; weakens A1 and F). Requires an explicit owner
  decision to change A1.
- **(b) Adapters for known dialects** — SPECTA stays closed, and support for
  `==Extension==`-style files is added deliberately, per dialect, with tests.
  Keeps A1. Each dialect becomes a named, reviewed, test-covered adapter.
- **(c) Store-only** — the file is accepted and kept, and only files matching
  SPECTA's contract are *runnable*. Maximum openness of *storage*, execution gate
  intact.

**Recommendation: (b), or (c) if openness matters more than execution.**
Option (a) is the only one that requires actively reversing a locked security
decision, and I will not do that on an ambiguous reading of "any type". Both the
Zangetsu files and `maxmovies-cc.js` point to (b).

### 13.3 The imported-JS runtime contract (undefined — needed even for (b) and (c))

An imported file must be able to do something. The minimum shape is still
unwritten. Needed from the owner, or derived from the real `SPECTA-Extensions`
files:

- required entry points, and their signatures
- what a source returns for search / details / episode list / stream resolution
- how a source declares failure, and how retry/backoff is signalled
- the `apiVersion` range a source may declare
- whether sources are sandboxed, time-limited, or run on the UI isolate

**I will not invent this.** A wrong guess produces a manifest and a runtime that
the real owner files do not satisfy — exactly the failure mode the Zangetsu
inspection exposed.

### 13.4 Node 0 / GitHub sync (partially defined)

Confirmed: private repository, owner-controlled, feeds Node 0.
Still undefined, and each is a decision I should not make unilaterally:

| # | Question | Note |
|---|---|---|
| H8a | Repository layout — flat `.js` files, or a manifest/index file listing them? | Determines whether SPECTA needs an index parser. |
| H8b | Reachable by raw HTTPS, or via the GitHub API? | A private repo needs auth either way. |
| H8c | **Authentication** | See §13.5. The one with a real security consequence. |
| H8d | Sync trigger — on app start, manual only, or on a timer? | Affects battery and data use. |
| H8e | Update policy — silent, notify-and-ask, or automatic? | |
| H8f | Failure behaviour — offline, private-repo error, expired token: what does the user see, given that no site or brand may be shown? | |
| H8g | Does a failed update leave the working copy in place? | Recommended: yes, always keep last-known-good. |
| H8h | Is Node 0 refreshed in place, or does each version get its own node? | |

### 13.5 GitHub credential handling — a hard constraint, not a preference

The owner has a private repository and intends to supply a **short-lived token**.
These rules are not negotiable, and are already enforced in this repo:

1. **Do not paste the token into chat.** Anything sent to a chat is written to a
   transcript. Put it in a file that is already git-ignored.
2. `H:\dev\SPECTA\.env` exists, is **git-ignored** (`.gitignore:17`), and holds
   only `TMDB_API_KEY`. It is the correct place for a new variable.
3. **The token must not be compiled into the APK.** §12 already says this. A
   token inside a shipped APK is extractable by anyone who unpacks it, which
   makes the private repository effectively public. If a private repo must be
   fetched from a released app, the credential has to be a per-device token the
   user supplies — an architecture decision, not an implementation detail.
4. It must not be echoed by tooling. Where I inspect `.env` files, I read
   **variable names only**, never values.
5. A token that has appeared in chat, a log, a commit, or build output is
   **compromised and must be rotated**. The earlier token in
   `C:\Users\PORTCR\Music\SPECTA APK\.env` is already in that state.

**Verified 2026-09-28:** a token-shaped-string scan over tracked files returned
**zero** real matches. `docs/GITHUB_CHECKPOINT_REPORT.md` matched only because it
contains the *literal* pattern names in prose. `.env` is untracked. No secret is
in git history.

### 13.6 Zangetsu reference — what was actually checked

To correct an earlier overstatement of mine: I inspected two Zangetsu URLs and
their provider files. I did **not** install Zangetsu or open its Settings — it
is not installed on the test device. What the evidence does show:

- Its provider files carry a different ecosystem's header and no SPECTA manifest,
  so SPECTA's current parser rejects them. That is a **provisional
  implementation finding about the current parser**, not a verdict on whether
  they should be supported.
- The reference app's UI **does** display the provider name, with a provenance
  badge beside it, and its detail page offers an **Auto Resolve** row naming a
  provider as the current resolver. H6 forbids that in SPECTA, so SPECTA's
  equivalent must show the **node label** (`Node 1`, `Node 2`) where Zangetsu
  shows a site name. A deliberate divergence from the reference.

### 13.7 Blocked pending written confirmation

1. §13.2 — which of (a)/(b)/(c) "any type of source" means. **Blocks Slice 8.**
2. §13.3 — the runtime/API contract for an imported source.
3. §13.4 — H8a–H8h, especially **H8c authentication**, which determines whether
   a token can live on the device at all.
4. Whether Node 0's GitHub sync ships in the same release as user source import.

Until items 1–3 are answered, no implementation slice is proposed.
