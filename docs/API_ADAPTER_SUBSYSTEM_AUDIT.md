# SPECTA — Abandoned "API Adapter / API Sources" Subsystem: Audit & Disposition

Date: 2026-09-24
Status: **AUDITED — PRESERVED IN STASH — NOT RESTORED, NOT DELETED, NOT BUILT ON**
Owner decision: preserve it; do not resurrect it; do not build Phase 2I around
it; remove it later only through a normal, reviewable change if the audit
proves it obsolete.

---

## 1. How it was found

At the start of the takeover session the working tree was **not** clean and
**did not build**. `flutter analyze` reported **92 errors**, all of them from
files that no report, README or `PROJECT_STATE.txt` mentioned:

```
?? lib/core/api_adapters/            (12 files)
?? lib/features/api_sources/api_sources_view.dart
 M lib/core/database/migrations.dart      (schema 5 -> 6)
 M lib/core/database/specta_database.dart (+2 tables)
```

The committed baseline (`a727eb6`) was independently verified healthy first
(`flutter analyze` clean; `flutter test` 803 passed / 14 skipped / 0 failed), so
the breakage was entirely attributable to this uncommitted work.

It was moved into a recoverable stash — `stash@{0}: baseline-audit-quarantine` —
so that nothing was destroyed and the baseline could be verified. **That stash
has not been dropped, applied, popped or modified.**

## 2. What it actually contains

~2,300 lines of new Dart across 13 files, plus a 2-table schema bump:

| File | Lines | Role |
| --- | --- | --- |
| `api_adapter.dart` | 604 | Translates an external JSON API into SPECTA models by evaluating **user-written field paths**. |
| `api_source.dart` | 270 | Pure config model: base URL, three endpoints, methods, auth type, headers, mappings. No secret field, by design. |
| `request_builder.dart` | 207 | The only place a request URL is assembled; path-token substitution + auth placement. |
| `api_providers.dart` | 191 | Riverpod wiring + `ApiSourcesNotifier`. |
| `field_path.dart` | 179 | `results[].id`-style path parser/resolver over JSON. |
| `api_source_dao.dart` | 179 | Drift DAO for the config table. |
| `api_credential_store.dart` | 150 | Credential interface + in-memory and Drift implementations. |
| `api_adapter_service.dart` | 143 | Parallel discovery over configured sources; a "Test connection" probe. |
| `field_mapping.dart` | 128 | `FieldTarget` vocabulary + `ResponseMappings`. |
| `api_sources_view.dart` | 81 | A CRUD screen for API sources. |
| `api_config.dart` | 40 | Auth-type and HTTP-method enums. |
| `api_source_table.dart` / `api_credentials_table.dart` | 39 / 35 | Two Drift tables. |
| `migrations.dart` / `specta_database.dart` | +49 / +4 | Schema **v6**: `api_sources`, `api_credentials`. |

### Why it was created (inferred from the code itself)

It is the answer to "how do I integrate a provider that is not a movie site?"
without writing JavaScript: the user supplies endpoints, auth and field paths,
and SPECTA evaluates them. The credential separation (config table carries only
a `credential_reference`; the secret lives in a separate table) is deliberate
and documented in the files.

## 3. Why it was NOT rescued

### 3.1 It does not compile, and the breakage is not cosmetic

Concrete, verified defects found by reading the code and by running the
analyzer — not stylistic complaints:

1. **Generated Drift code was never regenerated.** `specta_database.g.dart`
   contains **zero** references to the new tables, so `_db.apiSourceTable` and
   `_db.apiCredentials` do not exist. This alone produces most of the 92 errors.
2. **`ApiSourceSerializers` is referenced but never defined.** `api_providers.dart`
   calls it in 11 places; the class does not exist anywhere in the tree (the DAO
   defines an `ApiSourceMapper` instead). Two divergent persistence paths were
   written for the same table.
3. **`AdapterOutcome.valueOrThrow` does not exist.** `api_adapter_service.dart`
   calls it; the class only has a `value` field.
4. **`flutter_riverprovider.dart`** — a misspelled import in the UI file, so the
   screen does not compile at all.
5. **`s(enabled: v)`** in the UI — invoking a data object as a function.
6. **Schema mismatch.** `ApiSource` declares `searchPathParams`, but the Drift
   table has **no** `search_path_params` column and the v6 migration does not
   create one. The DAO never writes it and `ApiSourceMapper` never reads it, so
   the field silently does not persist.
7. **The migration and the table disagree about the column set**, so the
   upgrade path and a fresh install would not produce the same schema.
8. **No tests.** Zero test files reference any of it, so none of it has ever
   been executed.

### 3.2 It is a second, parallel integration architecture

SPECTA's established architecture is
`Core -> ExtensionManager -> Restricted JS runtime -> Extension contract`, which
is what `docs/PROJECT_STATE.txt`, `README.md` and every phase report describe,
and which the Phase 2I reference extension now exercises against a real
provider. The API-Adapter subsystem adds a **competing** channel that bypasses
the JS runtime entirely and runs its own URL assembly, its own auth handling and
its own JSON mapping in Dart. Adopting it would mean maintaining two ways for a
"provider" to reach discovery, metadata and sources — with different security
properties — against a rule that says the Core architecture is fixed unless the
audit proves a genuine defect. It does not.

### 3.3 Nothing in the product is blocked by its absence

Checked one by one:

- Real-provider integration → solved by the extension contract (Phase 2I, done).
- Provider-agnostic Core → already true, and now **enforced by a test** that
  fails if any provider marker appears in `lib/`.
- Credential handling → no credential is needed by any integration path that
  currently exists. The extension runtime deliberately exposes no credential
  store, and the reference provider is public.
- "Integrate a JSON API without writing JS" → a genuine capability, but a
  *feature*, not a missing foundation, and nothing in V1 depends on it.
- Schema v6 → not needed by any shipped feature; schema v5 is complete for V1.

The one idea in it that is worth keeping is the **separation of configuration
from secrets** (a config row never carries a token). That is a good pattern, and
if a generic API source is ever built it should keep it. It is recorded here so
the idea is not lost with the code.

## 4. Disposition

| Item | Decision |
| --- | --- |
| The 13 files | **Preserved** in `stash@{0}`. Not restored into the tree. |
| `migrations.dart` / `specta_database.dart` (schema v6) | **Reverted to v5** for now; they were part of the same stash. |
| Core changes | **None.** `lib/` is unchanged by Phase 2I. |
| Tests | None added for it (there is nothing working to test). |
| Future removal | Only via a normal, reviewable change, and only if the owner decides it is obsolete. This audit is the evidence that decision should rest on. |
| Future revival | If ever wanted, it must be **reimplemented against the existing architecture** with real tests — not merged as-is, and not used as a foundation for anything in the meantime. |

## 5. Verdict

The subsystem is **not** part of SPECTA, is **not** depended on by anything, and
is **not** a gap in the current architecture. It is incomplete, unexecuted,
unwired and off-architecture, and it left the repository in a non-building
state. It stays in the stash; V1 does not ship it.

No action is required from the owner to proceed. If the subsystem is ever
wanted, the recommendation is to rewrite the field-path/mapping core against
the extension contract rather than restore this tree.
