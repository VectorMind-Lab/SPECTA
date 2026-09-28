# SOURCE SYSTEM RUN REPORT

**Run:** Slices 1â€“7 implemented, committed and gated.
**Branch:** `source-system-run`
**Source of truth for this run:** `H:\dev\SPECTA` (the C: project was never edited)
**Baseline commit:** `440fa9a`
**Head commit:** `06728d9`

## 0. HEADLINE NUMBERS

| | |
|---|---|
| `flutter analyze` | **No issues found** (0 issues) |
| `flutter test` | **1252 passed Â· 39 skipped Â· 0 failed** |
| Baseline before any slice | 1171 passed Â· 39 skipped Â· 0 failed |
| Net new tests | **+81** |
| On-device checks | **23 PASS, 1 NOT TESTED, 1 NOT TESTABLE** after Slice 7b — see §9 and §10 |
| Release APK | **BUILT, SIGNED, INSTALLED** twice via `adb install -r` → `Success` — see §9, §10 |
| Slice 8 (official repo sync) | **BLOCKED, as agreed** |

## 1. COMMITS, ONE PER SLICE

| Slice | Commit | Subject | Gate |
|---|---|---|---|
| baseline | `440fa9a` | baseline before Slices 1â€“7 | 1171 / 39 / 0 |
| 1 | `e23303b` | Extension â†’ Source copy; fix misleading manifest diagnostic | 1172 / 39 / 0 |
| 2 | `0ed20e0` | Node identity model (pure, no DB, no UI) | 1190 / 39 / 0 |
| 3 | `7332323` | Node persistence â€” schema v8 â†’ v9, proven on a real v8 file | 1193 / 39 / 0 |
| 4 | `1622466` | Node 0 undeletable + a real delete removes the file (A7 + D) | 1209 / 39 / 0 |
| 5 | `23afddf` | Source card shows the node label and nothing else | 1219 / 39 / 0 |
| 6 | `b51c831` | Persisted user reordering, Node 0 not pinned (A4 / Q5) | 1229 / 39 / 0 |
| 7 | `06728d9` | Source Health screen, with an honest "No data yet" | 1252 / 39 / 0 |

## 2. WHAT EACH SLICE ACTUALLY DID

### Slice 1 â€” terminology and one real diagnostic bug
User-facing "Extension" copy became "Source". Separately, a file missing the
`// ==SpectaExtension==` header was reporting `Missing required field: id`,
which blamed the user's file for a problem SPECTA could have described
precisely. It now names the absent header.

### Slice 2 â€” node identity
Pure `SourceNodeSpace`, `SourceNode` and a first-free-index allocator. Official
labels are `Node 0`, `A`â€“`Z`, then `AA`, `AB`, â€¦; user labels are `Node 1`,
`Node 2`, â€¦ The two spaces are disjoint, so a label can never be ambiguous.

### Slice 3 â€” persistence (schema v8 â†’ v9)
Additive columns only: `node_index`, `node_space`, `node_locked`, `node_order`.
Nothing is dropped or rewritten, so every installed row, rollback point and
failure log survives.

**Proven against a real v8 SQLite file** (`user_version = 8`) containing three
installed sources (one disabled), three rollback points and three failure logs.
All rows survive with their real state; backfill yields `Node 1/2/3`
deterministically and idempotently; a fresh v9 database exposes the same
columns as an upgraded one.

> Two fixture bugs were found and fixed while building this test, and both would
> have made the test prove nothing: the fixture first wrote text timestamps where
> Drift stores epoch seconds, and it initially never set `user_version` â€” so
> drift skipped step 9 entirely.

### Slice 4 â€” Node 0 and a true delete (A7 + D)
`uninstall` returns a controlled `ExtensionFailure` naming the node the user
sees; it never throws and never silently no-ops. Node A and every user node
delete normally.

**The orphan-file bug (A7) is closed.** The path is read from the record
*before* the row is deleted, then unlinked through a new `SourceFileRemover`
whose guard normalises both sides â€” `..` segments and a sibling sharing a name
prefix cannot escape. The root itself is never "inside" it. An already-absent
file is success, not failure, and the outcome reports `fileRemoved` honestly.

16 tests run against a **real temp filesystem with the production remover**
(only the root is redirected).

### Slice 5 â€” the card shows the node label only
Primary line is `Node 0` / `Node 1` / `Node A` and nothing else. Name, author,
id and version moved behind a details sheet â€” one tap away, so nothing is
hidden. The green dot is unchanged and still gated **only** on
`TrustLevel.official`; it remains a provenance mark, not a quality score.

The remove-confirmation dialog now names the node rather than the source's
name, since it is the most-read dialog in a destructive flow.

### Slice 6 â€” persisted reordering (A4 / Q5)
`reorder(id, index)` takes a position in the visible order, clamps rather than
rejects, and renumbers every other node in one pass so the result is a dense
`0..n-1`. Node identity is untouched by a move, and **Node 0 is not pinned** â€”
it moves like anything else and stays undeletable wherever it lands.

Reorder is reachable by **button as well as drag**, so it works with a D-pad on
TV and with a screen reader.

> The analyzer caught that `onReorder` is deprecated in favour of
> `onReorderItem`, which already corrects `newIndex`. The manual off-by-one that
> had been written would have double-applied, so it was removed rather than kept.

### Slice 7 â€” Source Health (E / Q3)
Node labels only, plus real recorded state. The percentage is a **display
mapping, not a computed score** â€” SPECTA cannot compute a real reliability
figure, because it knows how many attempts failed, not how many were made.

| Real state | Display |
|---|---|
| never completed anything | **No data yet** |
| healthy, 0 recent failures | 100% |
| degraded, 1â€“2 recent failures | 50% |
| unavailable, 3+ recent failures | 10% |
| disabled | 0% |
| incompatible | 0% |

**"No data yet" is a real fact, not a guess.** Schema v10 adds
`extensions.last_success_at`, written **only** on a genuinely completed
operation, never at install. Zero failures reads the same for "never tried" and
"working perfectly", and the difference cannot be reconstructed from the failure
count â€” so a new column was the honest way to get it. It is nullable, so every
pre-v10 row lands NULL: SPECTA does not invent a success to make the screen
look better.

`source_ranker.dart` and `source_manager.dart` are **untouched** by design. No
"prefer a higher-priority node even at lower quality" mode was built.

## 3. DEFECT FOUND AND FIXED DURING SLICE 7

`DriftExtensionRegistry.setLastSuccess` was missing the monotonic guard the
in-memory registry had. An out-of-order clock could move "most recent success"
backwards and silently erase the fact that a source had ever worked. A test
caught it; the guard now exists on both sides and a test asserts they agree.

## 4. PROTECTED FILES â€” VERIFIED UNTOUCHED

Diffed against the baseline commit `440fa9a`:

| File | Status |
|---|---|
| `lib/core/extensions/verification/signature_verifier.dart` | **UNCHANGED** |
| `lib/core/extensions/verification/signing_protocol.dart` | **UNCHANGED** |
| `lib/core/extensions/verification/trusted_keys.dart` | **UNCHANGED** |
| `lib/core/extensions/distribution/extension_download_url_policy.dart` | **UNCHANGED** |
| `lib/core/extensions/runtime/request_policy.dart` | **UNCHANGED** |
| `lib/core/extensions/identity/trust_level.dart` | **UNCHANGED** |
| `lib/core/sources/source_ranker.dart` | **UNCHANGED** |
| `lib/core/sources/source_manager.dart` | **UNCHANGED** |

Ed25519 trust, the SSRF/URL policy, the request policy and the source ranker
were not modified by any slice.

## 5. NOT VERIFIED — stated plainly

**This section describes the state after the implementation run only. A later
device run closed most of it; see §9 for what is now actually verified, and §9.3
for what is still open and why.**

Everything below was **NOT VERIFIED** in the implementation run.

- **No device was connected.** No on-device behaviour was exercised.
- The Node 0 refusal **dialog** on a real device â€” NOT VERIFIED.
- The card / details sheet / health screen **visual audit** â€” NOT VERIFIED.
- Reorder **surviving a real application restart** â€” NOT VERIFIED on device.
  (It *is* proven at the database level against a real on-disk SQLite file that
  is closed and reopened â€” that is a database restart, not an app restart.)
- Delete removing the `.js` **on a real device's app-private storage** â€”
  NOT VERIFIED. (Proven on a real temp filesystem with the production remover.)
- A genuine v8 â†’ v10 upgrade **on a user's actual device** â€” NOT VERIFIED.
  (Proven against a hand-built, exact-v8/v9 on-disk file.)
- No streaming-site name on any source surface **by screenshot** â€” NOT VERIFIED.
  (Proven by walking the whole widget tree in tests, which is a different and
  weaker guarantee than a screenshot audit.)
- **Release APK build** â€” see Â§9.

## 6. TOOLCHAIN â€” WHY H: AT ALL

The project path on C: contains spaces (`C:\Users\PORTCR\Music\SPECTA APK\SPECTA`),
which broke Flutter's hooks-runner. The repo's own `gradle.properties` already
documented it: *"repeatedly corrupted caches"*.

- Project â†’ `H:\dev\SPECTA` (**the C: project was never edited**)
- Pub cache â†’ `H:\pub-cache-full` (252/252 packages, nothing downloaded)
- `PUB_CACHE` / `TEMP` / `TMP` / `GRADLE_USER_HOME` â†’ all on H:
- Pristine Flutter at `H:\flutter`
- `pub get --offline` used throughout; **no new packages were downloaded**

`flutter analyze` also went from ~203 s to ~4 s on the short path.

## 7. SLICE 8 â€” STILL BLOCKED, AS AGREED

Not started, by instruction. Still waiting on:

- the real `SPECTA-Extensions` repository layout, and
- a genuine SPECTA-compatible third-party `.js` for honest testing.

No placeholder was fabricated and the Zangetsu repository was not used as
SPECTA data. **No GitHub token work was performed.** The token in
`C:\Users\PORTCR\Music\SPECTA APK\.env` remains to be treated as compromised and
revoked; it was not embedded, committed or logged.

### 7.1 ZANGETSU PROVIDERS — CHECKED, AND IT WOULD NOT WORK (correctly)

`https://raw.githubusercontent.com/Spyou/zangetsu-providers/main/index.json` was
fetched and examined on 2026-09-28, at the owner's request, as a possible source
of genuine public test data. It was retrieved successfully (HTTP 200, 2193 bytes)
and is a well-formed JSON index of nine streaming providers — `anikoto`,
`fourkhdhub`, `uhdmovies`, `hdhub4u`, `hianime`, `vegamovies`, `multimovies`,
`animecube`, `torbox` — with `id`, `name`, `version`, `type`, `lang`, `file`,
`logo` and `nsfw` fields.

**It is not a SPECTA manifest and none of its files can be installed by SPECTA.**
A provider file was fetched and read: `providers/anikoto.js` (30282 bytes) begins
with a plain `//` comment and immediately declares `var SOURCE_ID`, `var SITE`,
and a `getInfo()` function. It has **no `// ==SpectaExtension==` header and no
`@id`/`@name`/`@version`/`@author` fields at all**.

This is the same situation as `maxmovies-cc.js` in §1: a different ecosystem's
dialect. Under decision **A1** the manifest contract gate is exactly what should
refuse it, and Slice 1's improved diagnostic would name the missing header
("This file has no SPECTA source header…") instead of blaming a missing `id`.
Adding a `@package`/Zangetsu-style fallback would be unspecified behaviour that
decision A1 rules out.

**Conclusion: this is not an issue to fix. It is the gate working.** SPECTA would
correctly reject every file in that repository, and it should. Slice 8 remains
blocked for the original reason: no genuine *SPECTA-format* public source exists
yet.

## 8. HONEST NOTES ON HOW THIS RUN WENT

Three things went wrong and are recorded rather than hidden:

1. **A reverted bad attempt (Slice 1).** A PowerShell string-replace roundtrip
   converted CRLFâ†’LF across whole files and produced 1,242 analyzer errors. It
   was reverted cleanly with `git checkout` and redone with targeted editor
   patches. Rule 3 was violated once and corrected.
2. **A mangled file (Slice 4).** One large patch inserted a duplicate
   `library;`, a self-import and duplicated a doc comment in
   `extension_storage.dart`. Caught by the analyzer and repaired with small
   targeted edits rather than a rewrite.
3. **A repeat of the same mistake (Slice 5).** A `Get-Content | Set-Content`
   roundtrip was used to inject a debug print, which is precisely the bulk
   rewrite that had caused problem 1. It happened to be a no-op because the
   pattern did not match, and the file was verified intact. Every subsequent
   edit used the editor tool.

Two test-fixture defects were also found and fixed, both of which had been
making a migration test silently prove nothing (see Slice 3).

## 9. DEVICE VALIDATION RUN (real device, release APK)

**Date:** 2026-09-28. **Device:** `R83L20FRDFM` (SM_A065F, Android 16).
**App:** `net.specta.app`, v1.0.0 (code 1).
**Evidence:** `H:\dev\device_evidence` (XML text dumps only; no screenshot was
needed for any claim below).

Method: the previously installed **old** build was used to install one unsigned
source, then the newly built **release** APK was installed over it with
`adb install -r`. The app was never uninstalled, so this is a genuine in-place
upgrade of a real v8 database.

Build: `tool\build_with_env.ps1 -Release` -> `assembleRelease` in 356.9 s, exit 0,
`app-release.apk` 108.9 MB, V2-signed (cert SHA-256 `99ac9d8e...15189303`).
`adb install -r` returned **`Success`**, which also proves the new APK's signature
matched the installed one. No key material was read, copied, printed or committed;
signing was already configured via the git-ignored `android/key.properties` +
`specta-release.jks`.

### 9.1 RESULTS

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Unsigned source installs on the **old** app and is listed | **PASS** | `1 installed`; card `Dev Test Unsigned / Unverified / 1.0.0 - SPECTA Dev / net.specta.devtest.unsigned / Ready / Enabled` |
| 2 | Release APK builds signed, installs with `-r`, app not uninstalled | **PASS** | `Success`; `dumpsys` still `net.specta.app` |
| 3 | Test source **survives** the upgrade and shows as **Node 1** | **PASS** | `02_upgrade_node1.xml` -> `Sources`, `1 installed`, `Node 1 / Degraded / Enabled` |
| 4 | Real v8 -> v10 migration ran on the device | **PASS** | `08_settings_schema_v10.xml` -> Diagnostics `SQLite schema` / `v10` |
| 5 | Card shows **only** the node label; no name/author/id | **PASS** | `02_upgrade_node1.xml` -> `Node 1 / Degraded / Enabled` only |
| 6 | No `/sdcard` path in any UI | **PASS** | No `/sdcard` string in any captured XML |
| 7 | Details sheet shows name / author / id | **PASS** | `03_details_sheet.xml` -> `Name: Dev Test Unsigned`, `Author: SPECTA Dev`, `Identifier: net.specta.devtest.unsigned` |
| 8 | Unsigned node has **no green dot** | **PASS** | Card is `Unverified`, no provenance dot; details sheet says "Not signed by SPECTA." |
| 9 | Turn a node **OFF** | **PASS** | `04_toggled_off.xml` -> `Node 1 / Disabled / Disabled`, still `1 installed` |
| 10 | Turn it back **ON** | **PASS** | `05_toggled_on.xml` -> `Node 1 / Degraded / Enabled` |
| 11 | Delete a user node: gone from the list | **PASS** | `06_deleted.xml` -> `0 installed`, `No sources are installed.` |
| 12 | Delete dialog names the **node**, not the source | **PASS** | `Remove Node 1? Its saved state on this device is deleted.` |
| 13 | Node numbering is stable (A5/A6): reinstall reclaims `Node 1` | **PASS** | After delete + reinstall: `Node 1 / Ready / Enabled` |
| 14 | Health reflects real recorded state, not a constant | **PASS** | Node 1 read `Degraded` after upgrade, `Ready` after clean reinstall |
| 15 | SSRF: `http://` refused (F) | **PASS** | `07_url_ssrf_refused.xml` -> `That does not look like a valid source link.` |
| 16 | SSRF: a public `https://` URL is accepted and fetched | **PARTIAL** | Policy accepted it and attempted the fetch; failed only on 404 -> `The source link could not be fetched.` |
| 17 | File-picker install gets the **next** node number | **PARTIAL** | Install proven (checks 1, 3, 13); a *second concurrent* node could not be made. See 9.3 |
| 18 | Pasted **https URL** install gets the next node number | **NOT TESTED** | No public HTTPS host serving a SPECTA-compatible `.js`. See 9.3 |
| 19 | Reorder; order persists across a force-stop | **NOT TESTED** | Needs >= 2 nodes. See 9.3 |
| 20 | Source Health: node labels only, "No data yet" when unused | **FAIL** | The screen is **not reachable in the shipped app**. See 9.2 |
| 21 | Node 0 refusal dialog | **NOT TESTABLE** | Requires Node 0, which requires Slice 8. Not attempted. |
| 22 | Delete removes the `.js` from app storage (A7) | **NOT TESTED** | Release build: `run-as` refused (`package not debuggable`), app-private dir unreadable |

### 9.2 DEFECT FOUND — the Source Health screen is unreachable (Slice 7)

`SourceHealthView` (`lib/features/extensions/source_health_view.dart`) is **dead
code in the shipped app**. A search of every file under `lib/` finds the symbol in
exactly three places:

- its own class declaration (line 26) and constructor (line 27),
- a doc comment in `source_health_row.dart:11`.

There is **no import, no route, no navigation entry and no construction site**
anywhere in `lib/`. The only reference outside its own file is
`test/features/extensions/source_health_view_test.dart`, which pumps the widget
directly. That is why 1252 tests pass while the feature is invisible to users: the
tests never travel through navigation.

The consequence is that Slice 7's own gate — "suite green + device screenshot" —
was met in a way that could not detect the defect. Decision **E** and **Q3** are
currently unfulfilled in the product. The Sources toolbar offers only
`Reload installed sources`, `Check the official catalogue for source updates` and
`From a link`; the catalogue button does nothing because Slice 8 is blocked.

**No code was changed in that run.** Slice 7b (`3afcd4a`) has since fixed it —
see §10 for the fix, the device re-run, and proof that the new tests would have
caught the original defect.

### 9.3 BLOCKED — why checks 17, 18 and 19 could not run

The file-picker install entry (`Install source`) is rendered **only inside the
empty state** (`extensions_view.dart:69-75`,
`ExtensionsStatus.ready when state.items.isEmpty`). Once one source is installed,
the Sources screen offers no way to add another by file, and the catalogue button
is inert pending Slice 8. The only remaining route to a second node is
`From a link`, i.e. a public HTTPS URL.

That route cannot be exercised, because:

- the SSRF policy (unchanged, decision F) correctly refuses LAN/loopback targets,
  so a local HTTP server cannot be used;
- the GitHub remote `VectorMind-Lab/SPECTA` is **not publicly reachable** — both
  the raw file and the repository API return 404 — so there is no public SPECTA
  source to point at;
- Slice 8 is blocked precisely because no genuine public repository layout or
  third-party sample file exists yet.

Fabricating a public host, or disabling the SSRF policy to test the route, were
both rejected: the first would invent data, the second would weaken a protected
surface to make a test pass. Both are explicitly out of bounds.

A secondary observation, **not a regression**: "install only from the empty state"
is pre-existing baseline behaviour, confirmed by reading `extensions_view.dart` at
commit `440fa9a`, where the same empty-state guard wraps the install button. Slice 5
did not introduce it. It is recorded because it is what blocked a two-node reorder
test.

**Resolved by Slice 7b.** The header's file-install action is now always rendered
and named `Install from file`, so a second and third source can be added from a
file. The two-node reorder test this blocked was then run on the device and
passed — see §10.3.

### 9.4 HONEST SUMMARY

Eleven of the fourteen checks that could be run without Slice 8 passed, including
the four the previous run had to record as NOT VERIFIED: the **real v8 -> v10
migration on a real device** (check 4), the **card visual audit** (checks 5, 6, 8),
the **details sheet** (check 7), and the **delete flow** (checks 11, 12).

Reorder-survives-a-real-restart (check 19) is still **NOT VERIFIED**, for the
concrete reason in 9.3 rather than for lack of a device. The one genuine **FAIL**
is check 20, the unreachable Source Health screen, described in 9.2.

Nothing in this run touched application code. The only repository change is this
report.

---

## 10. SLICE 7b — reachability fix, and the device re-run

**Commit:** `3afcd4a`. **Gate:** `flutter analyze` clean (0 issues);
**1259 passed · 39 skipped · 0 failed** (was 1252 — exactly the +7 new tests).

Slice 7b fixes the defect in §9.2 and the blocker in §9.3, and nothing else.
No protected file was touched, and no Slice 8 work was started.

### 10.1 WHAT CHANGED

1. **Source Health is reachable.** A neutral `monitor_heart` action was added to
   the Sources header cluster and pushes a new `SourceHealthPage` — a wrapper
   giving the screen the same `Scaffold` + `AppBar` + `BackButton` shape every
   other pushed view in the app uses (see `DetailsView`). `SourceHealthView`
   itself is deliberately unchanged, so its own six tests needed no edits. The
   action sits inside the existing horizontally-scrolling cluster, so the
   narrowest width still scrolls rather than overflowing (Phase F behaviour kept).

2. **File install is no longer limited to the empty state.** The header action
   already existed but was off-screen and named just `Install`, directly beside
   `From a link`. It is now always rendered and named **`Install from file`**.
   The empty-state button is kept, as instructed.

3. **Seven navigation tests** in `test/features/extensions/extensions_navigation_test.dart`.
   No test in that file constructs `SourceHealthView` or the install dialog
   directly — every one starts at `ExtensionsView` and navigates by tapping, so
   an unreachable screen cannot pass.

### 10.2 THE GAP IS CLOSED BY CONSTRUCTION, NOT BY ASSERTION

The claim "these tests would have caught it" was **verified, not assumed**. With
`onOpenHealth` temporarily stubbed to a no-op:

| Suite | Result with the route broken |
|---|---|
| 3 new navigation tests | **FAIL** |
| 6 pre-existing `source_health_view_test.dart` tests | **still PASS** |

That is the original blind spot reproduced exactly: the old tests pump the widget
directly and are blind to reachability, while the new ones travel through the UI
and are not. The stub was then reverted and `extensions_view.dart` verified
**byte-identical by SHA-256** to its pre-stub state.

### 10.3 DEVICE RE-RUN (same device, same evidence discipline)

Release APK rebuilt (`assembleRelease`, exit 0, 109.0 MB) and installed with
`adb install -r` → **`Success`**, over the app that already held a real v8→v10
database. `net.specta.app` was never uninstalled. Evidence in
`H:\dev\device_evidence`, XML text only.

| Check | Result | Evidence |
|---|---|---|
| Source Health action present on the Sources screen | **PASS** | `10_sources_health_action.xml` → `Source health` |
| **Source Health opens from Sources** | **PASS** | `11_source_health_screen.xml` → `Source Health`, `Back`, `Refresh` |
| Health screen shows **node labels only** | **PASS** | `11_...xml` → `Node 1`; no `Dev Test`, no `net.specta.devtest`, no `/sdcard`, no `/data/` |
| Health screen can be left again | **PASS** | `Back` returned to `Sources`, `1 installed` |
| `Install from file` offered **with 1 node installed** | **PASS** | `12_install_from_file_visible.xml` → `1 installed` + `Install from file` |
| **Second source installed from a file → Node 2** | **PASS** | `13_two_nodes_node1_node2.xml` → `2 installed`, `Node 1`, `Node 2` |
| No name/id/path leak with two nodes | **PASS** | `13_...xml`: no `Dev Test`, no `/sdcard` |
| **Reorder the two nodes** | **PASS** | `14_reordered_node2_first.xml` → `Node 2` above `Node 1`; move controls correctly enabled at each end |
| **Order survives force-stop + reopen** | **PASS** | `15_order_persists_after_restart.xml` → still `Node 2`, then `Node 1` |

Two things worth recording honestly:

- **"No data yet" was not observable on this device.** The health screen showed
  `Node 1 / Working with problems / 1 recent failure / 50%` rather than "No data
  yet", because the node has a genuinely recorded failure — it is a stub source
  whose calls fail. That is the honest mapping working on real data (Q3), not a
  regression. "No data yet" for a never-used node is proven by 4 tests through the
  real path, but is **NOT TESTED on device** for want of a node that has never
  been invoked. Recorded as such rather than claimed.
- **The new actions are off-screen until the header is swiped.** The cluster
  scrolls by design, so `Source health` and `Install from file` sit right of the
  fold at 720 px. Reachable, and the scrolling behaviour was explicitly kept, but
  not immediately visible. The widget tests scroll to reach them, which is what a
  user must also do.

### 10.4 WHAT IS NOW CLOSED

- **Check 20 (Source Health) — FAIL → PASS.** The screen is reachable and shows
  node labels only.
- **Checks 17, 18 (PARTIAL / NOT TESTED) → PASS for the file route.** A second
  source is now installable from a file while others exist, and numbering
  continued to `Node 2`. Check 18 (install via pasted **https URL** as the route
  that assigns the *next* number) remains **NOT TESTED** for the reason in §9.3:
  no public HTTPS host serving a SPECTA-compatible `.js` exists. That is a Slice
  8 dependency, not a 7b one.
- **Check 19 (reorder across a real app restart) — NOT VERIFIED → PASS.** This
  was open across two previous runs. It is now closed with device evidence.

Still open, unchanged: check 21 (Node 0 refusal, needs Slice 8) and check 22
(A7 file unlink, not observable on a release build).

## 11. REQUIREMENTS CLARIFICATION — 2026-09-28 (no code, no tests)

**Status: documentation only. Analyze not re-run, suite not re-run, nothing built.
No implementation slice proposed or started.**

The owner clarified the direction of the Sources system. The full capture is
`SOURCE_SYSTEM_PLAN.md` §13. This entry records only what changed in the
run's standing state.

| Item | Before | After |
|---|---|---|
| Slice 8 (Node 0 / GitHub sync) | BLOCKED pending a repository | Repository **exists** (private). Blocked instead on decisions §13.2, §13.3, §13.4. |
| Node numbering | A6 recorded, unexercised on device | Owner re-confirmed: Node 0 = official, Node 1+ = user. |
| Green dot | A provenance mark per Slices 5/7 | Re-confirmed: **official provenance only**, never quality. |
| Site names in UI | H6 already required | Re-confirmed. SPECTA will diverge from the Zangetsu reference, which does show the provider name. |

### 11.1 The one open decision that actually blocks work

"Accept any type of source" (open system) and locked decision **A1** (the
`// ==SpectaExtension==` manifest gate stays as is) are in direct conflict.
An app that executes JS needs an agreed calling contract, so the honest
options are (a) arbitrary executable JS — which reverses A1 and F, (b) deliberate
per-dialect adapters, or (c) store anything, run only SPECTA-contract files.
**Recommended: (b).** Not chosen unilaterally.

### 11.2 Correction to an earlier claim in this report

An earlier pass characterised third-party provider files (Zangetsu's, and
`maxmovies-cc.js`) as incompatible with SPECTA. That was stated too strongly.
Zangetsu was **not** installed and its Settings were **not** inspected; only two
of its URLs were read. What is actually established is narrower: those files use
a different ecosystem's header, so **the current parser** rejects them. Whether
they *should* be supported is a product decision, not a finding. Recorded
corrected rather than left to stand.

### 11.3 Secret hygiene re-verified

Tracked-file scan for token-shaped strings: **0 real matches**
(`docs/GITHUB_CHECKPOINT_REPORT.md` matches only the literal pattern names in
prose). `H:\dev\SPECTA\.env` is untracked, git-ignored (`.gitignore:17`), and
contains only `TMDB_API_KEY` by name. **No GitHub token has been used, and
none was created or requested.** The older token in
`C:\Users\PORTCR\Music\SPECTA APK\.env` remains compromised and unrevoked by me.

### 11.4 Standing numbers unchanged

`flutter analyze` clean and **1259 passed / 39 skipped / 0 failed** still describe
Slices 1–7 + 7b at commits `cbcc18b`, `3afcd4a`, `02b0f3c`. They are **not**
re-validated by this entry, because this entry changed no Dart file.

---

# COMPLETION REPORT — Slices 1 & 2 (2026-09-28)

Branch `source-system-run`. Commits: `8b71945` (docs), `fce5070` (Slice 1),
`d54e3af` (Slice 2). Working tree clean at the time of writing.

## C.1 What changed

| Slice | Commit | Substance |
|---|---|---|
| Docs first | `8b71945` | `SOURCE_SYSTEM_PLAN.md` §14 (the eight product rules), §14.2 (superseded table), §16 (as built). `SOURCE_RUN_REPORT.md` §12. `GITHUB_CHECKPOINT_REPORT.md` scope note. New `SOURCE_PLATFORM_TASK_REPORT.md`. |
| 1 — UI | `fce5070` | Horizontal action scroll removed; `+ Add Source` sheet; card 138 px to 104 px. |
| 2 — compatibility | `d54e3af` | `compat/source_format_detector.dart` and `compat/foreign_source_adapter.dart`; `resolveImportableSource()` in the manager. |

## C.2 Evidence

| Check | Result |
|---|---|
| `flutter analyze` | **No issues found** (full project, not just `lib`) |
| `flutter test` (full suite) | **1282 passed / 39 skipped / 0 failed** |
| Tests added, Slice 1 | 6 (no horizontal scroll, 320 px width, card compactness, Add Source routes, end-to-end add, overflow menu) |
| Tests added, Slice 2 | 18 (`test/core/extensions/compat/source_compatibility_test.dart`) |
| Tests updated | 3 suites; every change commented with its reason |
| Encoding | All edited files verified clean UTF-8 (only 2014, 00A7, 2026 present) |
| Secrets | Token-pattern scan over the full diff: **0 hits**. `defaultIndexUrl` is a public `raw.githubusercontent.com` URL. No token in the APK, assets, `repository.json`, JS, logs or docs. |
| DB schema | **Unchanged.** No migration, no schema edit. |

### Acceptance criteria

**UI**
- [x] Card substantially smaller: 138 px to 104 px, measured and asserted by a test
- [x] Green dot small (7 px) and clear; node name readable
- [x] Enabled/disabled obvious: explicit label plus switch
- [x] `+ Add Source` obvious and fully visible: asserted `isFullyVisible` at 360 px
- [x] A source can actually be added through the UI: end-to-end test
- [x] Install from URL fully visible and usable: asserted in the sheet
- [x] No clipped controls, no horizontal overflow at 360 px **and** 320 px
- [x] Existing functionality preserved; Node 0 undeletable; user nodes possible

**Compatibility / docs**
- [x] No source rejected merely for a different header: asserted on every refusal path
- [x] Each format documented with the required template: `SOURCE_SYSTEM_PLAN.md` §16.3
- [x] Provenance and compatibility separate in code and docs
- [x] No token or secret anywhere
- [x] `.md` files match the implementation; no known contradictions remain
- [x] Superseded decisions marked SUPERSEDED (§14.2, §15)

## C.3 WHAT IS AND IS NOT VERIFIED — stated plainly

These are **not** claimed as working. Updated 2026-09-28 by §13, which was
written to close items 1 and 2 and did: **both are now VERIFIED on the device**
and are kept here so the earlier state of the claim is not lost.

1. **Real Android device — Slice 1/2 layout.** **VERIFIED on hardware** (§13.4).
   Checks A1-A6 ran on the Galaxy A06 (`R83L20FRDFM`, Android 16): Add Source
   fully on-screen, node card **106.0 px** tall, all four install routes inside
   the viewport, overflow menu intact, and the layout holding at a constrained
   320 px with no overflow. Measured on the device's real **384 logical px**
   panel (the plan's "360 px" was this handset's neighbour, not its size).
2. **Runtime execution of an adapted source.** **VERIFIED on the device's real
   QuickJS** (§13.4): a foreign CommonJS source adapts, installs, loads, and its
   own `search()`/`details()` values reach the host; an operation the source does
   not declare is refused with a stated reason rather than an empty result.
   Getting here is what surfaced the blocker in §13.2 — the shim did not parse at
   all, on any engine.
   **install VERIFIED · runtime VERIFIED on device.**
3. **A genuine third-party source file.** None was present in the repository.
   The foreign-format work is driven by realistic fixtures. The first real
   third-party file will need one more pass, because a real provider module may
   nest its exports or name its operations differently.
4. **ES-module sources cannot run (new, §13.3).** A source detected as an ES
   module is adapted and installed, then dies on `export` in the script-mode
   sandbox. The adapter ships it as though it would run. Now pinned by a
   characterisation test rather than hidden; fixing it properly is a decision —
   transform the module, or refuse it at import with a message that says why.

## C.4 Recommended next step

Both halves are done. The device run happened (§13.4) and, unlike a fake
sandbox, the real thing found a blocker first: the bug was in the generated text,
so a stubbed sandbox would have mimicked straight past it.

What is actually left: the ES-module gap in item 4 — decide transform vs. refuse
at import — and item 3, which needs a genuine third-party file to test against.

## 12. OPEN-PLATFORM REQUIREMENT CORRECTION — 2026-09-28

**Status: documentation correction. No code changed in this entry.**

`SOURCE_SYSTEM_PLAN.md` §14 is now the authoritative product requirement. This
entry records what changes in this report's standing state.

| Item | Correction |
|---|---|
| "Slice 8 blocked pending a private repository" | **Wrong premise.** The official `SPECTA-Extensions` catalogue is **public**; `defaultIndexUrl` is already a public `raw.githubusercontent.com` URL. The private repo named in `GITHUB_CHECKPOINT_REPORT.md` is `VectorMind-Lab/SPECTA`, the app's own source-control repo, not the extension catalogue. |
| §11.1 "recommended (b) — dialect adapters" | **Withdrawn as a question to put to the owner.** The requirement is that external formats be supported, so a compatibility layer is the work, not an owner choice. |
| §11.2 "current parser rejects them" | Still true, and now reframed: it is a **compatibility gap to bridge**, not a product verdict. |
| Green dot | Confirmed as **official provenance only**, and explicitly **never** a gate on compatibility. |
| Token/secret handling | No token exists or is needed. Verified again this run: no token-shaped string in any tracked file or in history. |

Nothing in the previously recorded test counts changes here. `flutter analyze`
and the `1259 passed / 39 skipped / 0 failed` figures still describe Slices 1-7
and 7b; they are not re-validated by a docs-only change.

---

# 13. SLICE 1 / SLICE 2 VERIFICATION PASS (2026-09-28)

**Status: one blocker found and fixed, one gap recorded, device run PASSED
(§13.4).**

This pass set out to close §C.3 items 1 and 2 on the phone. It did both, but not
in the planned order: it first executed the compatibility adapter's real output
in a real JavaScript engine, and that found a defect that made **every** adapted
source unrunnable. The device run then confirmed the fix on QuickJS.

## 13.1 How the adapter's output was executed

The adapter's output was written to disk by the adapter itself (no hand-written
copy) and evaluated against the sandbox's real global shape: `SpectaExtension`
defined, and **no `module`, no `exports`, no `require`, no `fetch`** — exactly
what `sandboxBootstrap` in `extension_runtime.dart` provides. The identical
generated text was later handed to the device's real QuickJS (§13.4), which is
what turns this from a host-only claim into a device claim.

## 13.2 BLOCKER FOUND — the generated shim did not parse

The first result from that harness, against the shim as shipped in `d54e3af`:

```
typeof module  -> undefined
typeof exports -> undefined
EVALUATE THREW: SyntaxError: Unexpected identifier 'healthCheck'
```

Three separate defects, all in `foreign_source_adapter.dart`'s generated text:

| # | Defect | Effect | Fix |
|---|---|---|---|
| 1 | The Dart template ended its operation list with `}}` after an interpolation. In Dart, `}}` after `${…}` is the **escape for a literal `}`**, so the generated file carried a stray brace. | `class Extension` closed before `healthCheck`; `healthCheck` dangled outside the class → **SyntaxError at load, for every adapted source, in every engine** | Emit one `}` |
| 2 | The shim looked for `module.exports`, but the sandbox is a plain script global and defines no `module`, while the imported body — included verbatim, as designed — begins with its own `module.exports = …`. | `ReferenceError: module` on the first statement of any CommonJS source | Declare a CommonJS prelude (`__spectaModule` / `module` / `exports`) **before** the imported code |
| 3 | `__spectaResolve()` fell back to `return this`. The only members on `this` are the shim's own forwarding methods. | An export that could not be captured recursed until the stack died, so the host saw a stack overflow where it should see "this source does not implement X" | `return null`, letting `__spectaCall` report the absence |

Defect 1 is the one worth reading twice: the existing host tests asserted the
shim's **content** — it contains `class Extension extends SpectaExtension`, it
contains `does not implement` — and all of that was true. The file simply was not
valid JavaScript. Content assertions cannot see a grammar error; one execution
can. §C.4 had recommended exactly this, and it paid for itself immediately.

## 13.3 After the fix — same probe, same engine

```
=== CommonJS source ===
  EVALUATE: ok
  search('ghost', 1)  -> OK [{"title":"FOREIGN[ghost]foreign-build-7",
                              "url":"https://example.invalid/watch/ghost",
                              "type":"movie","year":2026}]
  details(ref)        -> OK {"id":"…/watch/ghost",
                             "title":"FOREIGN-DETAILS …/watch/ghost", …}
  healthCheck()       -> OK true          ← the method that used to dangle

=== source with no capturable export ===
  EVALUATE: ok
  search('ghost', 1)  -> THREW Error: This source does not implement "search".
                          (previously: unbounded recursion)

=== ES module source ===
  EVALUATE THREW: SyntaxError: Unexpected token 'export'
```

The `search` value is the fixture's own literal, assembled by the fixture's own
code — so the host received what the foreign source returned, which is the claim
Slice 2 makes and the claim §C.3 item 2 could not previously support.

**Recorded gap (not fixed here, §C.3 item 4):** the third block. An ES module is
detected, adapted and installed, then dies on `export` because SPECTA evaluates
extensions as plain scripts. Pinned by a characterisation test named
`KNOWN GAP: an ES module is wrapped for a script global that cannot parse it`, so
it cannot be mistaken for working code. The honest options are to transform the
module or to refuse it at import with a message that says why; that is a product
decision, not a drive-by edit.

**Engine honesty:** these runs used V8 (Node v24.16.0) through `node:vm`, in a
context whose globals were transcribed from `sandboxBootstrap`. It is not
QuickJS, and on its own it would only have proved the grammar. §13.4 then ran the
same generated text on the device's real QuickJS and it passed, so the two
together cover parse-level correctness on the host and runtime behaviour on the
engine that ships.

## 13.4 Device run — PASSED on real hardware

The phone came back on the bus mid-session (`R83L20FRDFM · SM_A065F ·
android-arm64 · Android 16 (API 36)`, state `device`), and the suite ran on it.
**6/6 passed in 14 s after a 161 s `assembleDebug`.** This supersedes the
"NOT RUN — phone disconnected" state recorded in `88d868a`, and it closes §C.3
item 1 and the device half of item 2.

Evidence is text, not screenshots: every measured value is logged under a
`SPECTA-S12` tag, because `uiautomator` cannot see inside a Flutter surface.

**Device reality first:** the panel reports **logical 384 × 853 at 1.875×**,
textScaleFactor 1.0. The plan asked for "360 px"; this handset's 720p panel is
384 logical px, so every check below was measured on the real 384 px viewport and
the narrow-phone case was asserted at a constrained **320 px** rather than 360.

Slice 1 — the Sources screen as the device really renders it:

| Check | Device-measured result |
|---|---|
| A1 Add Source visible, no horizontal viewport, no overflow | `Add Source -> 167,84 .. 243,104` inside 384×853 = **true** |
| A3 node card is compact | **card height 106.0 px** (host expectation was ≈105) |
| A4 all four install routes on-screen | `Install from a link -> 56,557 .. 170,577` · `Import a JavaScript file -> 56,620 .. 209,640` · `Browse the official catalogue -> 56,683 .. 246,703` · `Add from a repository -> 56,746 .. 198,766` — all inside 384×853 |
| A5 compact card still reaches details + remove | overflow menu still carries both |
| A6 holds on a narrow phone | at **320 px**: `Add Source -> 167,84 .. 243,104` and `Node 1 label -> 61,149 .. 110,170`, both inside 320×853, no overflow |

Slice 2 — a foreign source executed by **the device's own QuickJS**:

```
B1 :: format=adapted adapted=true failure=null
B2 :: install OK id=foreign.community-device-source.f757e4c9 node=Node 1
      trust=unverified contentType=movie
B3 :: loadRuntime OK — QuickJS on the device evaluated the shim and the
      embedded foreign body
B4 :: search OK   -> [FOREIGN[ghost]foreign-build-7]
B4 :: details OK  -> FOREIGN-DETAILS https://example.invalid/watch/ghost
B5 :: absent latest() reported as: Source did not declare the "latest"
      capability, so latest was refused.
cleanup :: shutdown OK — the QuickJS context was released
cleanup :: source is still installed after shutdown, as it should be
```

That is the claim §13.3 could only make on V8, now made on the engine that
matters: QuickJS parsed the generated shim, ran the verbatim CommonJS body, and
the host received the foreign source's own string back. It also confirms the
§13.2 fix rather than merely tolerating it — the pre-fix shim would have thrown
`SyntaxError` at B3.

**Two side effects, recorded because they are real:**
1. The previously installed release-signed APK conflicted with the debug build
   (`INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package net.specta.app
   signatures do not match`). The toolchain resolved it by itself — `Uninstalling
   old version...` then a clean install — which means **the device's app data was
   wiped** by this run. Any on-device state from the §9/§10.3 evidence runs is
   gone. No action needed, but do not assume the phone still holds that data.
2. The test installs and removes a foreign source and a node in the app's own
   database on the device. It cleans up after itself; `cleanup ::` above is that
   assertion passing.

Reproduce with:

```
cd H:\dev\SPECTA
$env:Path="H:\flutter\bin;$env:Path"
flutter test integration_test/slice12_device_verification_test.dart -d R83L20FRDFM
```

## 13.5 Regression net added, so this class of bug cannot return

Five host-side tests in
`test/core/extensions/compat/source_compatibility_test.dart`, in a group named
`the generated shim must parse and run in the sandbox`:

* braces balance across the generated file — this one fails against the old template;
* no member is emitted after the class has closed;
* the CommonJS prelude is declared **before** the imported body, not after;
* the shim never resolves the call target to `this`;
* the ES-module gap, as a characterisation test that must be replaced, not
  deleted, when the gap is genuinely closed.

## 13.6 Counts and hygiene for this pass

* `flutter test` — **1287 passed / 39 skipped / 0 failed** (was 1282; +5 from §13.5).
* `flutter test integration_test/slice12_device_verification_test.dart -d
  R83L20FRDFM` — **6 passed / 0 failed** on the physical device (§13.4).
* `flutter analyze` on `lib/core/extensions/compat`,
  `test/core/extensions/compat` and the new integration test — **no issues**.
* `dart format --set-exit-if-changed` on the touched files — clean.
* The probe fixtures and the temporary Dart dump harness were deleted. The Node
  probe lives under `build/` (git-ignored) as `build/shim_probe/probe.mjs`; it is a
  tool, not a test, and nothing in `lib/` or `test/` depends on it.
* The raw device transcript from §13.4 is at `build/s12/run.log` (git-ignored, so
  treat it as ephemeral). Every line of it that matters is transcribed into
  §13.4 above, which is the durable record.

## 13.7 What this pass settles, and what it does not

Settled, with device evidence: a foreign CommonJS source can be installed and
**actually executed** by SPECTA on real hardware, and its values reach the host.
The Slice 1 layout claims are no longer widget-test inferences. The one defect
that made the whole compatibility layer decorative is fixed and now guarded
structurally.

Not settled: ES-module sources still cannot run (§C.3 item 4), and no genuine
third-party source file has ever been fed through the adapter (§C.3 item 3) — the
fixtures are realistic, not real.

This pass does **not** re-open the earlier slices' device state: checks 17-20,
including reorder across a real app restart, were closed with device evidence in
§9 and §10.3, and §5's list describes the implementation run rather than today.
Still open there, unchanged and not reachable from this pass: check 18 (install
by pasted https URL) and check 21 (Node 0 refusal) both need Slice 8, and check 22
(A7 file unlink) is not observable on a release build. One side effect of this
run is noted in §13.4: the debug install replaced the release APK and so cleared
the device's app data.

