# Phase D report — Extension distribution and installation

Date: 2026-09-26
Status: **PARTIAL** — core distribution and update/rollback UI are complete and
verified; real-device verification and the unpublished catalogue remain (deferred
to Phase F / a publishing task).

## Gap status at a glance

| Gap | Item | Status |
| --- | --- | --- |
| 1 | Real-device verification of the install paths | **DEFERRED** → Phase F (device QA) |
| 2 | Update-check and rollback UI | **CLOSED** (2026-09-26) |
| 3 | `SPECTA-Extensions` repository not published | **DEFERRED** → separate publishing task |
| 4 | Live network test of catalogue/download | **DEFERRED** → Phase F (device QA) |

Gap 2 is closed: `ExtensionsState` now exposes an update check and a rollback
action, both routed through the manager's existing
`saveVersion` / `getRollbackVersion` paths, and both surfaced in the existing
Extensions screen with existing widgets only. Gaps 1, 3 and 4 remain open and
are recorded as deferred, not fixed — see "Known limitations" at the end.

## How the TMDB key is handled

The key is **never** requested or accepted in chat. It is supplied at BUILD time
only, via a git-ignored `.env` in the project root that a build script converts
into a `--dart-define`.

```powershell
# one-time, if the file does not exist yet
Copy-Item .env.example .env      # then paste your key into .env

# every build
.\tool\build_with_env.ps1
.\tool\build_with_env.ps1 -Target appbundle -Release
```

`tool/build_with_env.ps1` reads `.env`, skips blanks/comments, strips surrounding
quotes, and forwards each entry to the Dart compiler. The app reads it with
`String.fromEnvironment('TMDB_API_KEY')` in `lib/core/tmdb/tmdb_providers.dart`.
Equivalent manual invocation:
`flutter build apk --dart-define=TMDB_API_KEY=<key>`.

### `.env` is never bundled

- `.gitignore` ignores `.env`, `.env.*` (with `!.env.example` so the template is
  shareable), plus `*.pem` / `*.p12`.
- `pubspec.yaml` declares only `assets/images/`, so `.env` can never become a
  bundled Flutter asset. Verified: a release APK built through the script
  contains no `.env` entry.
- The build script prints only define NAMES (`Injecting build-time defines:
  TMDB_API_KEY`), never values, and never echoes the assembled command line.
  (An earlier revision of the script did echo it and leaked the key to the
  terminal; that line was removed and the leak verified gone.)
- `.env.example` is the committed template. It carries no secret.

### What the mechanism guarantees

- The key is compiled into the binary. It is never written to the database, a
  Settings field, an asset, or the UI, and there is no runtime path that can
  display it.
- `TmdbFailure.endpoint` records the **path** only, so a key travelling as the
  `api_key` query parameter cannot leak into logs or failure messages.
- `TmdbConfig.toString()` prints `configured` / `absent`, never the value.

**Honest limitation:** a `--dart-define` is a compile-time constant, so the key
is present inside the built APK. Treat any shipped binary as a secret-bearing
artifact and never distribute one carrying a personal key. Injection prevents
accidental commits and bundling; it is not encryption.

### Why the device barely calls TMDB (the caching answer)

`TmdbClient` is read-through cached by `MetadataCacheDao`:

| Setting | Value |
| --- | --- |
| TTL | 30 days (`MetadataCacheDao.timeToLive`) |
| Key | endpoint + sorted non-credential query, e.g. `/search/multi?include_adult=false&language=en-US&page=1&query=dune` |
| Storage | the shared `metadata_cache` table, `source = 'tmdb'` |
| Behaviour | a fresh row returns **without building a URI or touching the network** |

Practical effect: every distinct request costs at most one TMDB call per 30 days
per device. Re-opening a title, re-entering Details, or re-running a search you
already ran costs **zero** calls. Only genuinely new queries reach TMDB.

### Rate limits, per TMDB's own documentation

- The original limit (40 requests / 10 s) was **disabled on 16 Dec 2019**.
- TMDB still enforces an upper bound "somewhere in the 40 requests per second
  range", aimed at preventing bulk scraping. The figure can change.
- TMDB's explicit instruction: **respect `429`**.

`TmdbClient` already maps `429` to `TmdbFailureType.rateLimited`, which is
flagged **retryable**, and a rate-limited response is never cached.

Two honest limitations to be aware of:

1. There is **no client-side request throttle or queue** in SPECTA. At the
   volumes a single user's app produces this is comfortably under the limit, but
   SPECTA is not self-limiting if a future screen started issuing bursts.
2. TMDB also requires visible **attribution** (the "powered by TMDB" logo /
   notice) in any app using its data. SPECTA does not render one yet. That is a
   compliance gap to close before public distribution, and it is not something
   caching solves.

Reference: <https://developer.themoviedb.org/docs/rate-limiting>

### Known issue: the Home "Popular" rail is hidden with no extensions installed

Confirmed on a real device (2026-09-26) with a working, configured key. `Home`
returns the "No extensions are installed yet" empty state at
`home_view.dart:60` (`if (data == null || !data.hasItems)`) **before** the
catalogue rail is considered at line 123. With zero extensions the extension
feed is empty, so the early return wins and the TMDB rail is never built — even
though the request succeeded. The key and the API call are fine; the render
path short-circuits. Not fixed here because it is a C4 Home-layout issue, not
extension distribution.

## Inspected

- `lib/core/extensions/manager/` — `ExtensionManager`, `ExtensionLifecycleService`,
  `ExtensionRegistry` (interface + Drift + in-memory), `ExtensionRecord`.
- `lib/core/extensions/manifest.dart` — apiVersion / contractVersion / trust rules.
- `lib/app/platform/file_picker.dart` — the existing SAF picker (left untouched).
- `lib/features/extensions/` — the existing Extensions screen and its state.
- `lib/core/errors/specta_failure.dart` — the sealed failure hierarchy.
- Pre-existing uncommitted changes; none reset or discarded.

## What already existed (and was reused, not duplicated)

- The whole install pipeline: `importExtension` / `importFromSource` both funnel
  into `_processManifest` (manifest → API+contract compatibility → signature/trust
  → registry.install), with duplicate-ID replacement that retires the live runtime
  and carries the user's enabled state forward.
- The Android SAF `.js` picker with SHA-256 copy verification.
- The signature verifier and `TrustLevel` classification.
- `ExtensionRegistry` persistence, including a `saveVersion` / `getRollbackVersion`
  pair that existed but was **never called**.

## D1 — Device import

Preserved unchanged. The SAF picker, its size cap and its post-copy SHA-256
verification are untouched, and they still hand a verified app-private path to
`installFromFile`. Existing picker tests still pass.

NOT verified on a real device in this phase (see Known limitations).

## D2 — Direct HTTPS install

New `lib/core/extensions/distribution/`:

- `extension_download_url_policy.dart` — HTTPS-only. `http://` is **refused, not
  upgraded**; embedded `user:password@` credentials refused; loopback / private /
  link-local / unique-local hosts refused (IPv4, IPv6 and IPv4-mapped forms).
- `extension_downloader.dart` — `ExtensionDownloadTransport` seam, 10 MB cap
  (same limit as the device picker), optional SHA-256 verification.
- `dart_io_extension_download_transport.dart` — `dart:io` implementation with a
  bounded deadline, a cap enforced **while streaming**, and every redirect hop
  re-validated against the same policy (a public https URL that redirects to
  http/loopback/credentialed is refused, not followed).
- `extension_storage.dart` — app-private write location, plus a file-name
  sanitiser because the extension id is attacker-influenced and must not be able
  to escape the directory.

`ExtensionLifecycleService.installFromUrl` downloads, writes, and then calls
`installFromFile` — literally the same manager entry point as the device picker.

UI: a "From a link" button and `UrlInstallDialog` on the existing Extensions
header. No screen was redesigned.

## D3/D5 — Catalogue contract and repository architecture

`lib/core/extensions/catalogue/extension_catalogue.dart` defines ONE format
(`schemaVersion: 1`):

```
repository.json
{ schemaVersion, repositoryId, name, description, homepage,
  extensions: [ { id, name, description, author, version,
                  apiVersion, contractVersion, contentTypes[],
                  downloadUrl, iconUrl, homepage,
                  sha256, sizeBytes, updatedAt } ] }
```

Conceptual repository (documented, not yet published):

```
SPECTA-Extensions/
  repository.json    <- fetched by SPECTA
  extensions/        <- one .js per extension
  icons/             <- optional
  releases/          <- optional
```

Entry `downloadUrl`s are explicit, so a repository may point anywhere over HTTPS;
SPECTA assumes no layout beyond that. The parser is defensive: wrong-typed or
oversized fields degrade to null, one bad entry is skipped without losing the
others, and entries are capped at 500.

## D4 — Catalogue trust (explicit)

The catalogue model has **no signature or trust field at all**, by design.
Trust remains `TrustLevel`, derived solely from the extension's own manifest
signature verified by `ExtensionManager`. A test asserts that an unsigned
extension served from an "official-looking" host installs as `unverified`.

`sha256` is transport integrity ("these are the bytes I described"), never
authenticity — stated in the code and in the UI copy.

## D6 — Catalogue UI

`ExtensionsCatalogueSheet`: lists advertised extensions, shows what the catalogue
*claims*, and offers ONE action per row (Install / Update / Reinstall). Nothing is
installed automatically. The sheet states "Listing is not trust." Reached from a
"browse" icon in the existing header.

## D7 — Update and rollback (partially delivered)

**Fixed a real pre-existing gap:** `ExtensionRegistry.saveVersion` existed and
`rollback()` read `getRollbackVersion`, but nothing ever called `saveVersion`, so
rollback could never fire. `ExtensionManager._processManifest` now snapshots the
outgoing version before a replacement, after every gate has passed. Proven by
tests: the snapshot appears, and `rollback()` restores the previous version.

Preserved on replacement: the runtime is retired first, and the user's
enabled/disabled state carries forward (an update is not an implicit re-enable).

NOT delivered: there is no "check for updates" round, and no rollback button in
the UI. Version comparison exists (`isExtensionUpdateAvailable`) and drives the
row label, and installing an update uses the normal install path.

## D8 — Tests

New: `test/core/extensions/distribution/extension_installation_test.dart`.

- URL policy: https accepted; http refused; relative/unparseable refused;
  embedded credentials refused; loopback/private/link-local/IPv6 refused.
- Download: valid body + checksum; unreachable host (retryable); 5xx (retryable)
  vs 404; oversized body refused; checksum match accepted / mismatch refused.
- Catalogue: well-formed document parses; unsupported `schemaVersion` rejected;
  malformed entry skipped without losing good ones; unsupported API major hidden
  from the UI list; no trust field; semver update comparison; fetch failure and
  parse failure structured; a fetched catalogue is reused inside its TTL.
- Convergence: URL install writes to storage and lands in the registry; http URL
  refused **before any request is made**; catalogue install takes the same route;
  catalogue listing confers no trust; invalid manifest rejected; unsupported
  contract rejected; a failed install leaves no half-installed row.
- Update/rollback: replacement snapshots the outgoing version; rollback restores
  it; re-install preserves the disabled state; duplicate install replaces rather
  than duplicating.

## D9 — Gate

- All three routes converge on `ExtensionManager` via `installFromFile`. ✓
- No duplicate validation system: the downloader only fetches bytes; all
  manifest/compatibility/trust logic stays in the manager. ✓
- No trust bypass. ✓
- No UI-only installation: the UI only calls the notifier. ✓

## D7 — Extension update (gap 2, closed 2026-09-26)

Update checking and rollback are now exposed on the existing Extensions screen,
using the `saveVersion` / `getRollbackVersion` paths wired earlier. No screen was
redesigned and no new widget was introduced.

- **Manager:** added `isRollbackAvailable(id)`. It reports a rollback only when
  the snapshot would actually *change* the installed version.
- **Lifecycle service:** `isRollbackAvailable(id)` and `rollback(id)`, both thin
  delegations to the manager.
- **State:** `updatesAvailable` (id → newer catalogue version), `rollbackAvailable`,
  and `updateCheckDone`, plus `checkForUpdates()` and `rollback(id)`.
- **UI:** one `IconButton` on the existing header (check for updates), and one
  conditional `SpectaSecondaryButton` row on each card, shown only when there is
  genuinely something to do. `Update to <version>` re-installs the catalogue entry
  through the *normal* install pipeline, so manifest, compatibility and
  signature/trust gates all still run. `Restore previous` asks for confirmation,
  matching the existing `Remove extension` dialog pattern.

`checkForUpdates()` is user-initiated only and installs nothing by itself. A
catalogue that cannot be reached is not treated as a failure of the install list:
the message says so and the installed extensions are untouched.

### Defect found and fixed by the new tests

`rollback()` was **not idempotent**. The snapshot row is deliberately retained as
history, so a second rollback found the same snapshot, "restored" it, and returned
`true` — reporting a success that changed nothing. Both `rollback()` and
`isRollbackAvailable()` now refuse a rollback whose target is already the
installed version. The pre-existing manager test used a fixture where the current
record and the snapshot were both `1.0.0`, which cannot occur in the real flow (a
snapshot only exists because a newer version replaced it); that fixture was
corrected to model a real 2.0.0 → 1.0.0 upgrade rather than weakening the guard.

## Verification

- `dart format` — clean.
- `flutter analyze` — **No issues found!**
- `flutter test test/core/extensions test/features/extensions` — 384 passed,
  39 skipped, 0 failed.
- `flutter test` (full) — **1085 passed, 39 skipped, 0 failed.**
- No Android build and no device run in this phase.

## Database changes

None. No schema change and no migration. The catalogue is memoised in memory for
30 minutes rather than given a table; it is a discovery document, not media
metadata, and is safe to re-fetch on restart.

## Security

- HTTPS only; `http://` refused rather than silently upgraded.
- No GitHub authentication is used, required, or embedded. Raw GitHub URLs work.
- Redirects re-validated per hop, so a permitted URL cannot be used to reach a
  forbidden one.
- Loopback/private/link-local targets refused, matching the sandbox request policy.
- Body cap enforced while streaming; extension ids sanitised before use as a
  filename.
- The catalogue is not a trust authority and carries no signature field.
- No credential, API key, or secret was added. In particular, no TMDB key was
  requested or accepted — the existing `--dart-define` mechanism is unchanged.

## Known limitations — gap 2 is closed; 1, 3 and 4 are deferred

Gap 2 (update-check and rollback UI) is **done** — see the D7 section above.

Still open, explicitly deferred rather than forgotten:

1. **No real-device verification → deferred to Phase F (device QA).** D1 asks for
   real Android behaviour; the SAF import path, the URL install path and the new
   update/restore controls are all covered by automated tests only. Phase F runs
   them on real hardware.
2. ~~No update check and no rollback UI.~~ **Closed.**
3. **The `SPECTA-Extensions` repository does not exist → deferred to a separate
   publishing task.** The default catalogue URL fails to load until the repository
   is created. The failure is handled and shown honestly in the sheet, but the
   catalogue feature cannot be demonstrated end to end until it is published.
   Publishing also needs a decision on who holds the signing key.
4. **No live network test → deferred to Phase F (device QA).** Catalogue and
   download paths are proven against an injected transport; a live run against the
   published repository belongs with the device work.

## Note on the TMDB key

The key was deliberately not accepted. It is already wired through
`--dart-define=TMDB_API_KEY=...`, is compiled into the binary rather than stored,
and `TmdbClient` reads through `MetadataCacheDao` (30-day TTL), so repeat
titles/pages cost zero TMDB calls. The device runs in the previous phase made no
TMDB request at all, because no key was present in those builds.