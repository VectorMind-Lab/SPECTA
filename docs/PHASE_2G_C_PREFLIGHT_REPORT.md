# SPECTA — PHASE 2G-C PRE-FLIGHT REPORT

**Date:** 2026-09-21
**Scope:** Sections 34–39 of the Phase 2G-C authorization, executed BEFORE any
2G-C engine work. Per Section 34, only the items named in Sections 35–38 were
changed; everything else previously reported complete was left untouched.

Verification vocabulary (Section 39.3):

* **verified by running** — a command was executed in this session and its
  output is quoted/summarized here.
* **verified by reading source** — the cited file was opened and read in this
  session.
* **taken from an earlier report** — quoted, not re-verified.
* **unverified** — could not be established; marked honestly.

---

## A. Repository state before any change

Verified by running (`git log`, `git status`, `git remote -v`, `flutter --version`,
`flutter analyze`, `flutter test`) at session start, before any edit:

* Branch: `master`; HEAD: `7fcb0cc` ("Phase 2G-A/2G-B: download foundation,
  manager, queue and engine seam" — the push recorded in PROJECT_STATE).
* `git remote -v`: `origin  https://github.com/VectorMind-Lab/SPECTA.git (fetch/push)`
  — the remote EXISTS. Finding 35.2.1 verdict: **PROJECT_STATE was right;
  GITHUB_ERROR_CORRECTION_REPORT's deletion narrative applies to a different
  accidental repository, not this remote.** PROJECT_STATE §7 now says so
  explicitly.
* Pre-existing dirty tree (NOT created by this session):
  * root `README.md` + root `PROJECT_STATE.txt` DELETED in the worktree
    (a violation of the documented byte-identical-duplicate rule). Restored
    during Section 35 (see B).
  * `docs/README.md` modified — the documented 2G-B status update.
  * `lib/core/downloads/download_manager.dart` + its test modified — the
    documented 2G-B source-audit §I fix.
  * untracked `docs/PHASE_2G_B_SOURCE_AUDIT.md`.
* Toolchain: Flutter 3.47.4 / Dart 3.13.3 at `H:\flutter` — verified by
  running; matches the documented toolchain table.
* Baseline test counts, verified by running BEFORE any edit:
  * Run 1: **617 passed / 9 skipped / 1 FAILED**
    (`discovery_coordinator` — "provenance is preserved…" — order-dependent
    flake; passes in isolation and on re-run).
  * Run 2: **618 passed / 9 skipped / 0 failed.**
  * Verdict on finding 35.2.5: the audit's "618 / 9" is correct as the
    expected count; the unconditional "0 failed" hid a real (rare) flake.
    Recorded here and in PROJECT_STATE §7; no test was edited (per §34 the
    test does not encode a bug — it is a pre-existing isolation/ordering
    sensitivity in the discovery coordinator suite, listed under E).
  * Real-JS baseline was NOT run before edits (only after; 721 passed).
    The 2G-B figure 627 is taken from an earlier report.

## B. Documentation truth audit (Section 35)

| # | Claim checked | Verdict | Evidence | Action |
|---|---|---|---|---|
| 1 | Git remote deleted | WRONG (remote exists) | `git remote -v` run | PROJECT_STATE §7 corrected |
| 2 | README: "no request policy enforced yet" | WRONG | `lib/core/extensions/runtime/request_policy.dart` read; policy enforces scheme/method/size/timeout; §37 added host + redirect rules | README corrected twice (before §37 and again after) |
| 3 | README: MediaKit "baseline only, wired to nothing" | WRONG | Phase 2E report + `lib/core/playback/` exists | Toolchain table corrected |
| 4 | README: layout lists only home/settings; "not reachable from main.dart" | WRONG (stale) | real `lib/` tree listed: 12 core dirs, 9 feature dirs, ui/ | Layout regenerated; reachability statement corrected |
| 5 | Test counts 617/626 vs 618/627; CODEBASE_INVESTIGATION "green at 8d966b8" vs audit HEAD 7fcb0cc | MIXED | fresh runs (A) + `git log` | Living docs now quote 712/9 + real-JS 721 (pre-flight numbers); historical reports left untouched per §35.3 |
| 6 | PROJECT_STATE §7 quotes 2F-era 475+9; §8 says 2G not authorized while §2/4 say 2G-A/B done | WRONG | this file | §1, §4, §7, §8 rewritten to true state |
| 7 | Duplicated living docs | CONFIRMED VIOLATED | root copies were deleted in worktree | Both pairs restored byte-identical (`cmp` verified) |
| 8 | SETUP_LOG pub-cache location | CONFIRMED as stated | correction 7 (2026-09-16) already correct; re-verified via package_config roots | Dated correction note 8 appended (log body untouched) |
| 9 | "manager 38 tests", "110+ download tests across 6 files" | PARTLY WRONG | counted: 113 `test(` across 6 files; manager file has 39 | PROJECT_STATE §2 annotated with counted numbers |
| 10 | "Device verification not performed" (2B/2C/2D) and "Home content is design fixtures" still true? | TRUE (both) | no device attached this session; `home_view.dart` doc comment read | Left as-is; no change needed |

Documents edited in Section 35: `README.md`, `docs/README.md`,
`PROJECT_STATE.txt`, `docs/PROJECT_STATE.txt`, `docs/SETUP_LOG.md` (note only).
Historical phase reports, evidence logs: NOT rewritten, per §35.3.

## C. Findings 36.1–36.5 and 37

Each finding was first CONFIRMED by reading the cited source; then fixed; then
pinned by new tests. None was "already fixed" and none was refuted.

### 36.1 — Non-Latin titles normalize to an empty key — CONFIRMED
* Evidence: `discovery_normalizer.dart` and `metadata_manager.dart` both used
  `[^\w\s]` (ASCII `\w` in Dart), so a purely e.g. Arabic/Chinese title lost
  every character and keyed to `""`. Verified by reading both files.
* Impact analysis (§39.1 F): the persisted 2F identity is
  `<normTitle>|<type>|<year>`. OLD rows already persisted with an empty title
  segment keep their stored keys (resume parses the stored string; it does not
  recompute it) — no migration needed. NEW rows for non-Latin titles now get a
  real key; two different non-Latin titles that previously COLLIDED on `""` now
  no longer collide. No key format change for existing Latin content (ASCII
  output is unchanged — golden-tested). The `|`-free invariant required by the
  resume parser (`resume_entry.dart` splits on `|`) is enforced in the shared
  function.
* Fix: new `lib/core/identity/title_key.dart` — single Unicode-aware
  implementation (`\p{L}\p{N}_`-equivalent via unicode-aware regex, NFKC,
  casefold, whitespace collapse, empty→`untitled` fallback, `|` rejected).
  Both consumers rewired to it. No re-implementation inside downloads code
  (§39.4 satisfied — 2G-C will use this same function).
* Tests: `test/core/identity/title_key_test.dart` — Unicode preservation,
  ASCII golden parity, empty-key fallback, `|` handling, whitespace/case
  normalization.

### 36.2 — `request({ query })` parameters were built but never applied — CONFIRMED
* Evidence: `controlled_runtime_api.dart` built `queryParameters` from the
  extension payload, and the contract documents `request({query})`, but the
  transport URL was used verbatim — parameters silently dropped.
* Fix: the API merges `query` into the request URL (existing query string
  preserved, extension params appended/overriding) before the transport sees
  it; contract shape unchanged (a `request({query})` call now works as the
  contract already documented).
* Tests: in `request_policy_hardening_test.dart` + existing runtime tests —
  query merged, existing query string preserved, no query = unchanged URL.

### 36.3 — Transport: per-chunk deadline bypass + unbounded buffering — CONFIRMED
* Evidence: `DartIoHttpTransport` applied the timeout to connection setup only;
  a server dripping one byte per interval kept the request alive forever; the
  body accumulated into a growable `List<int>`.
* Fix: whole-request deadline (connection + headers + body all bounded by the
  policy timeout), `BytesBuilder` accumulation, cancellation propagates to the
  socket (a runtime deadline abort actually closes the connection).
* Tests: dripping-body test fails fast under the deadline; large-body
  completion still succeeds; header-deadline test.

### 36.4 — One malformed item breaks a whole list — CONFIRMED
* Evidence: `extension_runtime.dart` `getSources` did `item as Map<String,
  dynamic>` (throws on a bare string row); search/detail rows did
  `item['type'] as String?` / `item['cover'] as String?` (throws on non-string
  scalars); `data['timeout'] as int?` threw on a fractional/string timeout;
  `json['status'] as String` threw on a numeric status. Verified by reading.
* Fix: per-row defensive parsing — bad rows are SKIPPED, bad optional scalars
  degrade to null, numeric/fractional timeout accepted via `num`, string
  timeout falls back to the default. Failure type/shape unchanged for
  genuinely malformed top-level payloads.
* Test edit disclosure (§34 rule): `extension_runtime_test.dart` contained one
  test asserting the buggy behavior itself ("a DASH source in the list fails
  the whole getSources call"). That test asserted exactly the bug, so it was
  rewritten to pin the corrected skip behavior — reason recorded here per §34.
  No other existing test asserted buggy behavior, and no previously-passing
  test failed for any other reason.
* Tests: `extension_runtime_defensive_test.dart` — non-object rows, missing
  URLs, unsupported types, numeric type/cover, numeric/string/fractional
  timeout, numeric status, non-string optional detail fields.

### 36.5 — `loadRuntime` never re-verified trust from the file — CONFIRMED
* Evidence: `extension_manager.dart` `loadRuntime` re-read the file and
  re-derived capabilities, but kept the import-time `trustLevel`; a file
  changed after import kept running as `official`. Verified by reading.
* Fix: trust is re-classified from the file actually being loaded
  (`_classifyTrust(manifest, body)`); a divergence from the stored record
  UPDATES the persisted record (signature + trustLevel + updatedAt) and writes
  an `ExtensionFailureRecord` (operation `load`) naming both levels. The
  policy that unverified extensions still load is unchanged (trust is data).
* Ordering note (honest): my first fix moved the enabled/API/sandbox checks
  AFTER the re-check; three existing tests assert those checks' existing
  failure types/behavior for records whose files are absent/unreadable, they
  do NOT encode the 36.5 bug, and §34 forbids breaking them — so the reorder
  was REVERTED and the checks stay before the file read (their semantics must
  not depend on file readability). The tests in
  `extension_manager_trust_recheck_test.dart` therefore supply a real (faked)
  API + sandbox so the flow reaches the re-check — exactly how production is
  configured. Consequence, recorded honestly: a load refused by the
  enabled/configuration checks will not re-classify trust on that pass; the
  real app always configures both, so every real load reaches the re-check.
* Tests: tampered file downgrades stored trust + records failure; untouched
  file keeps official + records nothing; failure message names both levels.

### Section 37 — Request policy hardening (Tier 2) — CONFIRMED as described
* Evidence: no private-host blocking of any kind; redirects followed by the
  HttpClient WITHOUT re-evaluation. Verified by reading `request_policy.dart`.
* Fix (`request_policy.dart` + `controlled_runtime_api.dart`):
  1. `ExtensionRequestPolicy(blockPrivateHosts = true,
     allowHttpsToHttpRedirect = false)` added.
  2. Blocking by IP literal and by name: localhost/*.localhost, loopback
     127/8 + ::1, private 10/8 + 172.16/12 + 192.168/16, link-local
     169.254/16 + fe80::/10, unique-local fc00::/7, unspecified 0.0.0.0 + ::,
     and IPv4-mapped IPv6 forms of those; hostname RESOLVED before connect
     and refused if any resolved address is blocked (injectable resolver for
     determinism). Best-effort: documented in code and here that this does
     NOT fully defeat DNS rebinding.
  3. Redirects handled manually: `followRedirects = false`; up to
     `maxRedirects` hops; relative `Location` resolved against the current
     URL; FULL policy (scheme allow-list incl. the new host rules) run on
     every hop; 303→GET, 307/308 preserve method+body; `Authorization`/
     `Cookie` headers not forwarded to a different host.
  4. New stable denial codes on the existing `RequestDenialReason` pattern:
     PRIVATE_HOST_BLOCKED, REDIRECT_TO_PRIVATE_BLOCKED,
     REDIRECT_SCHEME_NOT_ALLOWED, REDIRECT_LOOP_EXCEEDED — returned through
     the existing structured `ok:false` response; extension-visible contract
     shape unchanged.
  5. Loopback tests kept working WITHOUT weakening production: the loopback
     tests inject `ExtensionRequestPolicy(blockPrivateHosts: false)` (the
     sanctioned §37.5 test-only override); production provider wiring
     (`extension_providers.dart`) uses the DEFAULT policy = blocking ON, and
     a dedicated test (`production provider policy blocks private hosts`)
     proves it. The override is not reachable from any release code path,
     extension input, or settings screen.
* Tests: `request_policy_hardening_test.dart` — each blocked range (IPv4 +
  IPv6 incl. mapped and bracketed literal forms), public host allowed,
  resolver-based hostname→blocked-address denial, redirect to blocked host
  denied, https→http denied by default / allowed with the flag, relative
  redirect resolved, 303 POST→GET, 307 POST preserved, redirect cap,
  sensitive headers not forwarded cross-host, production policy blocking ON.

## D. Tier 3 items (Section 38) — documented, NOT implemented

All verified against source/config before recording:

1. **JS can freeze the UI** — TRUE (QuickJS on the main isolate, no ceiling;
   already documented). Background-isolate option noted in README/PROJECT_STATE.
2. **Import flow trust hardening** — TRUE (only load-time re-classification
   exists now; copy + content-hash verify at load awaits the 2H import UI).
3. **Release signing/shrinking** — TRUE (`android/app/build.gradle.kts`
   release signs with the debug key; no minify/shrink). `DUMP` re-check in
   release noted. Not changed.
4. **Android backup** — TRUE (`allowBackup` unset ⇒ defaults on; DB holds
   watch history). Owner decision; not changed.
5. **Cleartext HTTP** — policy allows http; manifest has no cleartext
   configuration. Whether cleartext is affected on the target SDK could NOT
   be determined this session (no release build/device test run) — recorded
   as UNVERIFIED, to be tested in a release build; no manifest change made.
6. **Single-device verification + viewport TV detection** — TRUE; restated
   as open risks.
7. **Plugin KGP warning + flutter_js 0.8.7 maintenance risk** — TRUE
   (build output shows the KGP deprecation warning); noted, not acted on.
8. **Project path contains a space** — TRUE (`SPECTA APK`); rename
   recommended, not performed.
9. **Non-UTF-8 bodies lossy Latin-1** — TRUE; noted, not changed.
10. **Legal/distribution note** — added as one neutral sentence.

All ten are in PROJECT_STATE (§4 carry-overs / §6) and README Known
limitations, both copies.

## E. Additional findings (not fixed, per §34)

1. **Order-dependent flake** — `discovery_coordinator` provenance test failed
   once in the full-suite run before any edit, passed in isolation and on
   re-run (A). Evidence: two baseline runs quoted above. Proposed fix (out of
   pre-flight scope): give that test its own extensions/timers or run it in a
   shard; do NOT silence it by weakening assertions.
2. **`flutter test` deprecation noise** — the runner suggests the
  `test/`-directory convention; cosmetic only, no action taken.
3. Nothing else observed that meets the bar of "genuine defect with evidence".

## F. Persisted-key impact analysis for 36.1

(Also summarized in C/36.1.) The 2F persistence key is the evidence key:
`<normTitle>|<type>|<year>` (+ `|s<S>e<E>` for episodes). With the shared
Unicode-aware key:

* Latin/ASCII titles: byte-identical output to the old function (golden
  test) ⇒ existing persisted rows and lookups unchanged.
* Non-Latin titles previously keyed `""` ⇒ previously `||movie|2024`-style
  collisions; new rows get distinct real keys. Old rows keep their stored
  strings; resume parses stored keys and does not recompute them ⇒ no data
  loss, no migration, and the fix strictly reduces future collisions.
* `|` can never appear inside a segment (rejected by the shared function) ⇒
  the resume parser's split invariant is preserved by construction.

## G. Validation results (Section 31 set, run AFTER the pre-flight work)

All verified by running, in this order, on the completed pre-flight tree:

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **712 passed / 9 skipped / 0 failed** (baseline 618/9/0 ⇒ +94) |
| `FLUTTER_BIN=… bash tool/run_tests_real_js.sh` | **721 passed / 0 failed** |
| `flutter build apk --debug` | SUCCESS (`app-debug.apk`; Gradle assembleDebug 159.4 s) |
| `git status --short` | Pre-flight changes only; no commit made (per §30) |

The full Section 31 set was then run a SECOND time after the Section 35/38
document edits and the creation of this report (the §39.2 gate as literally
specified — after ALL pre-flight work, before 2G-C): identical results —
analyze clean; 712 passed / 9 skipped / 0 failed; real-JS 721 passed /
0 failed; debug APK SUCCESS (assembleDebug 31.8 s); HEAD still `7fcb0cc`,
no commit made.

New/changed code in this pre-flight:
* New: `lib/core/identity/title_key.dart`
* Modified: `lib/core/discovery/discovery_normalizer.dart`,
  `lib/core/metadata/metadata_manager.dart`,
  `lib/core/extensions/runtime/request_policy.dart`,
  `lib/core/extensions/runtime/controlled_runtime_api.dart`,
  `lib/core/extensions/runtime/extension_runtime.dart`,
  `lib/core/extensions/manager/extension_manager.dart`
* New tests: `test/core/identity/title_key_test.dart`,
  `test/core/extensions/runtime/request_policy_hardening_test.dart`,
  `test/core/extensions/runtime/extension_runtime_defensive_test.dart`,
  `test/core/extensions/manager/extension_manager_trust_recheck_test.dart`
* Modified tests (each justified above): `request_policy_test.dart` and
  `flutter_js_sandbox_test.dart` (sanctioned §37.5 policy override only),
  `controlled_runtime_api_test.dart` (same override), and one buggy-behavior
  test in `extension_runtime_test.dart` (rewritten per §34).
* Docs: the four living-doc copies + the SETUP_LOG note + this report.

## H. Follow-ups required before/with 2H or the import UI

1. Import UI must copy extensions into app-private storage, store a content
   hash, and verify at load (extends 36.5's re-classification).
2. Decide what the app DOES with unverified extensions (trust is currently
   data, not enforcement).
3. Release keystore + minify/shrink + `DUMP` permission re-check + backup /
   cleartext decisions before any distribution.
4. Background-isolate JS engine evaluation (UI freeze risk).

---

**Verdict:** the Section 39.2 gate is PASSED on the numbers in G. The
pre-flight is complete; Phase 2G-C engine work may begin, reusing
`lib/core/identity/title_key.dart` for download identity (§39.4).
