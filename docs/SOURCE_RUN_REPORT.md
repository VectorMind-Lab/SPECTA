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
