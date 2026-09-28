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
| On-device checks | **NOT VERIFIED â€” no device was connected this run** |
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

## 5. NOT VERIFIED â€” stated plainly

Everything below was **NOT VERIFIED** in this run. None of it is claimed as done.

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

## 9. FINAL STATE

- **Release APK: NOT BUILT â€” NOT VERIFIED.** No APK was produced in this run and
  none was installed on a device. Every claim above is from `flutter analyze` and
  `flutter test` only.
- **Where the final code lives:** `H:\dev\SPECTA`, branch `source-system-run`,
  head `06728d9`. The C: copy at `C:\Users\PORTCR\Music\SPECTA APK\SPECTA` was
  **never edited during implementation**; it received a copy-only sync at the very
  end of the run (see the closing summary).
