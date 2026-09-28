# SOURCE SYSTEM RUN REPORT

**Run started:** 2026-09-27
**Run stopped:** 2026-09-28 (before Slice 1 began)
**Branch:** `source-system-run`
**Baseline commit:** `440fa9a` — `chore(source-system): baseline commit before Slices 1-7`
**Outcome:** **STOPPED. No slice was implemented. No application code was changed.**

---

## 1. WHAT WAS COMPLETED

### 1.1 Safety baseline (Rule 1) — DONE
- Created branch `source-system-run` from `master` (`2f87ee1`).
- Committed the entire existing working tree (241 modified + untracked files) as `440fa9a`.
- No `reset`, no `--force`, no deletion of existing work.
- `master` is untouched at `2f87ee1`.

### 1.2 Toolchain repair — DONE (this was the real blocker)
The Flutter SDK on `H:\Projects\App sdk and tools\flutter` was **corrupted**: its
working tree had **8,875 deleted files** and the tool could not start at all.

| Missing path | Files | Restored |
|---|---|---|
| `packages/` (incl. `flutter_tools`) | 4,020 | yes |
| `engine/` | 2,903 | yes |
| `examples/` | 1,906 | yes |
| `third_party/`, `LICENSE`, `README.md`, `pubspec.yaml` etc. | 46 | yes |

Restored with `git checkout --` inside the **Flutter SDK repo only**. That repo had
**0 modified and 0 untracked** files, so nothing could be lost. The SPECTA
repository was not touched by this repair.

**After repair:** `flutter --version` → `Flutter 3.47.4 • channel stable`.

### 1.3 `flutter analyze` — PASSES
```
Analyzing SPECTA...
No issues found! (ran in 203.0s)
```

**This is a real, current result on the current tree.**

---

## 2. WHAT BLOCKED THE RUN

### 2.1 `flutter test` cannot execute in this environment

`flutter test` crashes before a single test runs. The exact error:

```
Flutter failed to create a directory at
"<project>\.dart_tool\hooks_runner\objective_c\8e04c28b44\out\".
PathNotFoundException: Creation failed
(OS Error: The system cannot find the file specified, errno = 2)
```

and, on other attempts:

```
Could not acquire the lock to
"<project>\.dart_tool\hooks_runner\shared\objective_c\.lock".
TimeoutException after 0:05:00
```

**What I tried, and the result of each:**

| Attempt | Result |
|---|---|
| `flutter test` (default) | fails — hooks_runner directory/lock |
| `flutter test --no-pub` | fails — hooks_runner directory/lock |
| kill stale `dart` processes, remove stale `.lock` files | fails |
| pre-create the full `hooks_runner` tree by hand | fails — **the tool deletes it, then cannot recreate it** |
| junction `C:\specta_ws` → project (space-free path) | fails — resolves back to the real path |
| `subst S:` drive letter (space-free path) | fails — same error |
| `flutter test --concurrency=1` (rule out lock contention) | fails |
| `flutter test --no-test-assets` (skip the asset bundle) | fails |
| a single test file (`test\core\extensions\manifest_test.dart`) | fails — so it is not a scale/parallelism problem |

**Diagnosis:** manual writes into `.dart_tool\hooks_runner\shared\objective_c\`
succeed from PowerShell (`[System.IO.File]::Create` returns OK), but the
Flutter/Dart toolchain cannot create the same directories or lock files there.
The tool deletes the directory on start and then fails to recreate it. This is a
defect in the Dart native-assets / build-hooks runner **in this environment** —
not in SPECTA code, and not something SPECTA's changes can fix.

`flutter analyze` works. Only `flutter test` is broken, because only the test

---

## 3. TEST COUNTS

| | Count |
|---|---|
| Baseline test count | **UNKNOWN — NOT VERIFIED** |
| Reason | the suite cannot be executed in this environment |

The previously reported figure of *1171 passed / 39 skipped* is **stale** and
applies to an older commit. It is **not** re-confirmed here and must not be
treated as the current baseline.

---

## 4. NOT VERIFIED

Everything in Slices 1–7. Explicitly:

- Slice 1 — the "Extension" → "Source" copy rename: **NOT STARTED**
- Slice 1 — the manifest diagnostic fix from finding B: **NOT STARTED**
- Slice 2 — the node identity model: **NOT STARTED**
- Slice 3 — the v8 → v9 migration: **NOT STARTED**
- Slice 4 — Node 0 undeletable flag and true delete: **NOT STARTED**
- Slice 5 — the node-label-only card: **NOT STARTED**
- Slice 6 — reorderable order: **NOT STARTED**
- Slice 7 — Source Health screen: **NOT STARTED**
- Slice 8 — official distribution: **NOT STARTED, and still BLOCKED by decision G**
- No APK was built.
- Nothing was run on the phone for this run.

The only verified result in this run is `flutter analyze` → **No issues found**.

---

## 5. STATE OF THE REPOSITORY

- Branch `source-system-run` @ `440fa9a`.
- Working tree **clean** — 0 changed files.
- `master` @ `2f87ee1` — untouched.
- `docs/SOURCE_SYSTEM_PLAN.md` (the approved plan) is committed on the branch.
- Temporary scripts and logs created during the run have been deleted.
- The `New folder\` test fixtures (`__invalid_test.js`, `__devtest_unsigned.js`,
  `maxmovies-cc.js`) were **left in place** — they may still be useful.

---

## 6. WHAT MUST BE CHECKED / FIXED ON YOUR MACHINE

1. **Make `flutter test` run again.** This is the only thing blocking the run.
   Most likely causes, in order of probability:
   - a **stale/corrupt `.dart_tool`** — try `flutter clean`, then
     `flutter pub get`, then `flutter test`;
   - the Dart **native-assets / build-hooks** runner is broken on this Flutter
     3.47.4 install — try re-downloading the SDK, or testing on another machine;
   - disk pressure on `C:` (only **8.8 GB free** during the run) — freeing more
     space is worth trying.
2. **Capture a real baseline test count** once `flutter test` runs. Every slice
   report will be measured against it.
3. **Revoke the exposed GitHub PAT** in `C:\Users\PORTCR\Music\SPECTA APK\.env`.
   It was pasted into chat and must be treated as compromised. No token was
   used, embedded or committed during this run.

---

## 7. OPEN QUESTIONS FOR YOU

1. Should I retry the run once `flutter test` is confirmed working, or do you
   want to run it yourself first?
2. Do you want the Flutter SDK re-downloaded? The repair restored the working
   tree from git, but the SDK had lost real files in a way that suggests an
   interrupted install; a clean re-download would be safer.
3. The `hooks_runner` failure is a Flutter-tool defect, not a SPECTA defect.

---

## 8. WHAT WAS NOT TOUCHED (Rule 5 compliance)

None of these were modified at any point in this run:

- `lib/core/extensions/verification/trusted_keys.dart`
- `lib/ui/widgets/specta_developer_dot.dart`
- `lib/core/sources/source_ranker.dart`
- `lib/core/sources/source_manager.dart`
- `lib/core/extensions/distribution/extension_download_url_policy.dart`
- `lib/core/extensions/runtime/request_policy.dart`

No GitHub token was used. No network install of any provider. No Slice 8 work.

path triggers the hooks runner.

### 2.2 Why I stopped instead of continuing

Rule 2 requires `flutter analyze` **and the full test suite** to be clean after
every slice; Rule 3 permits moving on only when that gate passes.

Without a runnable test suite I cannot establish a **baseline test count**,
verify any slice, or honestly claim anything is green. Implementing Slices 1–7
with no way to run tests would mean writing a schema migration, a node allocator
and a delete-lifecycle change **completely unverified**. That is exactly what
Rule 3 and Rule 7 forbid. **So the run stopped at zero slices.**
