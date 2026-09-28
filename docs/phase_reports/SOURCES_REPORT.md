# Phase report — Extension Sources / Providers

Date: 2026-09-26
Status: **VERIFIED** for the repository-index route and the reporting fixes;
the SAF picker interaction was not driven end to end (see Remaining blockers).

## 1. What already existed (inspected, not assumed)

Per the instruction to inspect before implementing, the following were already
in place and were **kept, not rebuilt**:

| Area | Existing state |
| --- | --- |
| `ExtensionManager` | Single authoritative installation boundary |
| Phone `.js` import | SAF picker + verified app-private copy |
| Direct URL | `UrlInstallDialog` -> `installFromUrl` |
| GitHub URL | Already just an https URL; **no GitHub code needed** |
| `ExtensionCatalogueClient.load(url)` | **Already accepted any URL** — the UI hardcoded the default |
| Official catalogue | `repository.json`, schemaVersion 1, strict |
| Sources destination | `SpectaDestination.extensions`, labelled "Extensions & Sources" |
| Trust | `TrustLevel` from the manifest signature only |

The most important finding: **`load(indexUrl)` was already parameterised.**
Requirement D was therefore not a networking change — it was a missing UI
affordance plus a document-shape problem.

## 2. What was missing

1. **No way for the user to supply a repository index.** The sheet hardcoded
   `OfficialExtensionCatalogue.defaultIndexUrl`.
2. **The strict parser rejected real repository shapes.** A public provider
   index uses `sources[]`, RELATIVE `file` paths, `logo`, a single `type`, and
   carries no `schemaVersion`. The official parser requires `extensions[]` and
   an absolute `downloadUrl`.
3. **Three false "too large to install" reports** (detailed in §5).

## 3. What was implemented

### `lib/core/extensions/catalogue/extension_repository_index.dart` (new)
`ExtensionRepositoryIndexParser` normalises a user-supplied index into the SAME
`ExtensionCatalogueEntry` the official catalogue produces, so UI, install action
and trust rules keep one code path.

* Root array key: `extensions`, `sources`, `addons`, `plugins`, `providers`,
  `items`, or a bare top-level array.
* File key: `downloadUrl`, `file`, `url`, `path`, `download`.
* RELATIVE paths resolved by RFC 3986 against the index's own **directory**;
  absolute URLs passed through unchanged.
* `iconUrl`/`logo`/`icon`/`image`; `id`/`internalName`/`slug`;
  `name`/`title`/`displayName`; `author`/`authors`/`owner`.
* `sha256`/`fileHash`/`hash` normalised from a `sha256-` prefix to bare hex.
  **Transport integrity only** — never authenticity.
* Bounded: 500 entries, 2048-char fields.
* **Non-`.js` entries are skipped and counted.** A compiled/binary provider
  plugin can never install, so offering a button for it would be a guaranteed
  failure.

### `extension_catalogue_client.dart`
Added `loadRepositoryIndex(url)`. The fetch, URL policy, redirect handling and
failure classification were **extracted into a shared `_fetch`** used by both
`load` and `loadRepositoryIndex`, so the two cannot drift. The existing
memoisation of `load` was preserved and is still covered by its original test.

### `lib/features/extensions/extensions_repository_sheet.dart` (new)
Sources -> Repository -> Provider cards. Shows only real data: repository name
and description, the **web host** the index came from, a real provider count, a
real "N skipped" count, and per-provider version/author/installed state. Every
Install button returns an `ExtensionCatalogueEntry` to the caller, which routes
it through the existing `installCatalogueEntry` -> `ExtensionManager`.

### `lib/features/extensions/extensions_url_dialog.dart`
`UrlInstallDialog` was **parameterised** (title, label, hint, action, copy) and
reused for the repository prompt rather than duplicating a second dialog.

### `lib/features/extensions/extensions_view.dart`
Added a `Repository` action to the existing header cluster and
`_browseRepository`. No rename, no recolour, no restructure; the header already

## 4. Installation route status

| # | Route | Status | Evidence |
| --- | --- | --- | --- |
| 4 | Phone JS import | **Code + unit tests only** | SAF path unchanged; channel-name drift fixed earlier; picker interaction NOT driven this phase |
| 5 | Direct URL | **Verified** | `installFromUrl` tests + device test |
| 6 | GitHub URL | **Verified** | Reached live on device; no GitHub-specific code required |
| 7 | Repository JSON URL | **Verified on device** | Real public index read: 9 providers, relative paths resolved |
| 8 | Repository -> extension | **Implemented, not installed on device** | Entry -> `installCatalogueEntry` -> `ExtensionManager` covered by the automated suite |

## 5. Reporting defects found and fixed

While testing the reported failure, three unrelated causes were all reported as
`tooLarge`, i.e. **"That extension file is too large to install."**

| Site | Real cause | Now |
| --- | --- | --- |
| `extension_lifecycle_service.dart` | no readable manifest id | `notAnExtension` |
| `extension_downloader.dart` | empty body | `emptyResponse` |
| `dart_io_..._transport.dart` | body is not UTF-8 | `notText` |

`tooLarge` now means oversize and nothing else. A non-extension download is
explained in plain language by `describeUnimportableSource`, which names a JSON
document for what it is — a repository catalogue, not a file size problem.

A fourth was fixed in the same spirit: a repository whose entries are all
non-`.js` previously reported `unsupportedSchema` ("uses an unsupported
format"). The format may be perfectly valid, so that was misleading. It now
reports `noInstallableEntries`.

## 6. ExtensionManager convergence

```text
phone .js  ─┐
direct URL ─┤
GitHub URL ─┼─> ExtensionManager (manifest -> compatibility -> signature -> trust)
repository ─┘
```

No route has its own validation or trust path. The repository reader produces
claims only; it cannot grant trust, and `TrustLevel.official` still requires a
valid Ed25519 signature against SPECTA's published key. A test asserts that an
unsigned extension fetched from a GitHub URL does **not** become official.

## 7. Raw filesystem path check

No filesystem path is displayed anywhere in the new surface. The repository
sheet shows the **web host**, never a local path. Tests assert `/sdcard`,
`/storage/emulated` and `/data/user` are absent. Device import continues to use
the system picker; the user is never required to type a path.

## 8. Tests

* `test/core/extensions/catalogue/extension_repository_index_test.dart` — 19 new
* `test/features/extensions/extensions_repository_sheet_test.dart` — 5 new
* `test/core/extensions/distribution/extension_installation_test.dart` — 8 new
* `integration_test/pref_extension_url_device_test.dart` — 3 on-device

```text
flutter analyze -> No issues found!
flutter test    -> 1135 passed, 39 skipped, 0 failed
```

## 9. Android build

```text
flutter build apk --debug -> app-debug.apk    255,195,549 bytes  SUCCESS
flutter build apk         -> app-release.apk 112,518,372 bytes  SUCCESS (minified/R8)
```

The debug APK was installed over the existing build on the physical device
with `adb install -r`, preserving installed extensions and state.

## 10. Real-device verification

Executed in the real app process with the real network stack.

**PRE-F-1 — the reported link:**
```
download ok=true
bytes=343                          (cap = 10485760)
install ok=false
USER-VISIBLE MESSAGE: That link is a repository catalogue — a JSON index of
addons — not a single SPECTA extension. Browse the catalogue to install from it,
or link the .js file of one provider directly.
```
Nothing installed; the message no longer blames a size limit.

**PRE-F-2 — control:** SKIPPED. The reference extension lives in a private
repository and is not reachable from the device without credentials. Reported as
a skip rather than as a pass. Its substance (a real extension installs through
`installFromUrl`, and a GitHub URL confers no trust) is covered by the automated
suite instead.

**PRE-F-3 — a user-supplied repository index (live, external input):**
```
index ok=true failure=null
repo name=<from the test document>  entries=9  skippedNonJs=0
sample entry resolved to an absolute https .js URL
```
A temporary, externally supplied index was passed in at run time; the document
contained 9 relative-path entries, all of which were verified on-device as
absolute, https, `.js` URLs, proving the relative `file` resolution works
against a real host. **That index is not referenced by any SPECTA code, test,
default, or document** — see §13. The test takes its input as a run-time
parameter and reports a skip when none is supplied.


## 11. Files changed

| File | Change |
| --- | --- |
| `lib/core/extensions/catalogue/extension_repository_index.dart` | **new** — tolerant index reader |
| `lib/core/extensions/catalogue/extension_catalogue_client.dart` | `loadRepositoryIndex`, shared `_fetch` |
| `lib/features/extensions/extensions_repository_sheet.dart` | **new** — Sources/Repository/Provider UI |
| `lib/features/extensions/extensions_url_dialog.dart` | parameterised, reused |
| `lib/features/extensions/extensions_view.dart` | `Repository` action + handler |
| `lib/core/errors/specta_failure.dart` | 4 new failure types |
| `lib/core/extensions/manager/extension_lifecycle_service.dart` | root-cause reporting fix |
| `lib/core/extensions/manager/extension_manager.dart` | `describeUnimportableSource` |
| `lib/core/extensions/distribution/extension_downloader.dart` | empty body |
| `lib/core/extensions/distribution/dart_io_extension_download_transport.dart` | non-UTF-8 body |
| `test/core/extensions/catalogue/extension_repository_index_test.dart` | **new** — 19 tests |
| `test/features/extensions/extensions_repository_sheet_test.dart` | **new** — 5 tests |
| `test/core/extensions/distribution/extension_installation_test.dart` | +8 tests |
| `test/features/extensions/extensions_view_test.dart` | updated message assertion |
| `integration_test/pref_extension_url_device_test.dart` | **new** — 3 on-device tests |

## 12. Remaining blockers

## 13. No dependency on any example repository

The repository index used to exercise requirement D on real hardware was an
**external test input only**. SPECTA is generic: it reads whatever index the
*user* supplies, and holds no dependency on, affiliation with, or endorsement
of any particular host.

Concretely, the following are **not** present anywhere in SPECTA:

* the example index URL, or any other third-party index or catalogue URL;
* that repository's provider names, versions, or any of its file contents;
* any default, configuration value, or fallback pointing at it;
* any catalogue entry describing it;
* any permanent automated test that reaches it.

`ExtensionRepositoryIndexParser` contains **no URL literals at all** — it is
driven entirely by the URL passed in at run time. The live-network device tests
take their inputs from `--dart-define`
(`SPECTA_LIVE_CATALOGUE_URL`, `SPECTA_LIVE_REPOSITORY_URL`,
`SPECTA_LIVE_EXTENSION_URL`) and report a **SKIP** when none is supplied, so the
suite is green by default and never touches the public internet unless a human
deliberately asks it to. The automated suite that proves the reader works uses
synthetic fixtures only, with invented names.

Trust and trust-adjacent behaviour are unchanged by this: being listed is not
trust, a repository listing grants nothing, and `TrustLevel.official` continues
to require a valid Ed25519 signature over SPECTA's published key.


1. **SAF picker not driven end to end.** The device has no accessibility
   services installed and Flutter renders to a canvas, so `uiautomator` cannot
   read the UI to drive the system picker. The code path is unit-covered and
   unchanged, but the interaction itself is unverified this phase.
2. **No live install FROM a repository entry on the device.** The device test
   reads the index and resolves entries but deliberately installs nothing.
   Installing from a third-party index was not performed.
3. **No `SPECTA-Extensions` repository is published**, so the official
   catalogue path has no live document. Unchanged from Phase D.
4. **Android TV / D-pad not verified.** No TV device or emulator available.
5. **No signature is available to this build** (the production private key is
   intentionally not in the repository), so Official trust classification is
   proven only with a throwaway test key.
6. **Working tree is uncommitted** since 2026-09-24, by design. No reset, stash,
   clean, discard or force push was performed in this phase.

scrolls horizontally because of the Phase F narrow-screen fix.
