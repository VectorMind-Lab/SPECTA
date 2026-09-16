# SPECTA — Development Environment Setup Log

Date: **2026-09-15**
Operator: implementation AI (Phase 0), acting with the project owner's
authorisation to configure this machine's development environment.

This file records what was inspected, what was installed or configured, what
failed, and why each decision was made. Nothing here is inferred: every result
quoted below came from a command that was actually run on this machine.

---

## 1. Initial inspection

| Item | Finding |
| --- | --- |
| Flutter SDK | **Missing** — not on `PATH`, not in `C:\flutter`, `C:\src\flutter`, `~/fvm`, and no Flutter plugin bundle inside Android Studio |
| Dart SDK | **Missing** |
| Android SDK | Present: `C:\Users\PORTCR\AppData\Local\Android\Sdk` with `platforms` (android-36, 36.1), `build-tools` (35.0.0–37.0.0), `ndk`, `cmake`, `emulator`, `platform-tools`, `licenses` |
| Android cmdline-tools | **Missing** (only needed for `sdkmanager` / licence management) |
| JDK | OpenJDK 21.0.10 (Android Studio JBR); `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr` |
| Git | 2.54.0.windows.1 |
| curl | 8.19.0 (Schannel) |
| Node / npm | v24.16.0 / present |
| Gradle | Not installed system-wide — correct, Flutter supplies its own wrapper |
| Free disk | **C: 4.4 GB of 281 GB (99 % used)**; H: 42 GB free |

Project folder inspected before any change: it contained `miru-app-dev/`
(an unrelated Flutter streaming app used as a design reference, not SPECTA
code), `miru-app-dev.zip`, and the Phase 0 brief. No SPECTA code, no
`PROJECT_STATE.txt`.

## 2. Blocker found and how it was resolved

`flutter_windows_3.47.4-stable.zip` is **1,931,293,116 bytes (1.93 GB)**.
Extracting it needs ~3.5–4 GB, and pub cache + Gradle + build output need
roughly another 1 GB. That is ~5–6 GB against 4.4 GB free on the only mounted
drive at the time.

Filling a Windows system drive to zero free space risks OS instability and
corrupt writes, so the install was **stopped and reported** rather than forced.
The project owner then supplied drive **H:** (`H:\Projects\App sdk and tools`),
which has 42 GB free, and the install was moved there:

| Artefact | Location at setup time | Final location |
| --- | --- | --- |
| Flutter SDK | `H:\Projects\App sdk and tools\flutter` | `H:\flutter` |
| Download staging / logs | `H:\Projects\App sdk and tools\` | `H:\Projects\App sdk and tools\` (kept for the record) |
| `PUB_CACHE` | `H:\Projects\App sdk and tools\pub-cache` | `H:\pub-cache` |
| `GRADLE_USER_HOME` | `H:\Projects\App sdk and tools\gradle-home` (planned) | `H:\gradle-home` |

The project itself stays where the owner asked for it:
`C:\Users\PORTCR\Music\SPECTA APK\SPECTA`.

## 3. Version selection

Stable channel metadata was read from
`https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`:

```
STABLE_VERSION = 3.47.4
DART_SDK       = 3.13.3
ARCHIVE        = flutter_windows_3.47.4-stable.zip
SHA256         = 31173300481bd06e377fd55ee84214689648b1817563efd7b450b7b78bdf351a
```

The archive is verified against that published SHA-256 after download, so a
mirror that served different bytes cannot go unnoticed.

## 4. Why a custom downloader was needed

Measured throughput from this machine on 2026-09-15:

| Host | Measured |
| --- | --- |
| `storage.googleapis.com` (Flutter's release host) | 70–130 KB/s, occasionally ~450 KB/s |
| `services.gradle.org` | ~484 KB/s |
| `codeload.github.com` | ~147–500 KB/s |
| `mirror.nju.edu.cn` (Flutter mirror) | ~91 KB/s |
| `storage.flutter-io.cn` | ~152 KB/s |
| `mirrors.cloud.tencent.com` | ~35 KB/s, frequently 0-byte responses |
| `mirrors.ustc.edu.cn`, `mirrors.sjtug.sjtu.edu.cn`, `mirrors.aliyun.com`, `mirrors.huaweicloud.com` | 404 — Flutter archive not mirrored |

At 130 KB/s a single-connection download would have taken ~4–5 hours. Eight
parallel connections **to one host** gave the same 128 KB/s aggregate, i.e. the
limit is per host, not per connection. Downloading ranges from several mirrors
in parallel therefore raises aggregate throughput.

Implemented tooling (kept outside the application project, in
`SPECTA APK\_setup\`):

- `fetch_flutter_sdk.sh` (v1) — 16 ranges across 4 mirrors. It reached ~330 KB/s
  but 16 concurrent connections provoked mirror throttling: repeated instant
  empty responses burned the per-chunk retry budget.
- `fetch_flutter_sdk_v2.sh` — same 16 chunk boundaries (so already-downloaded
  data is reused), but 6 workers, 120 s deadlines per transfer, a 3 s backoff
  after an empty response, and 3 mirrors. Aggregate ≈ 560 KB/s.
- Both scripts are resumable and both end by verifying size + SHA-256.

Manual alternatives that were considered and rejected: `git clone` of
`flutter/flutter` (the tool source is smaller, but the Dart SDK and engine
artefacts are still fetched from the slow host afterwards), and asking the
owner to install Flutter by hand (the owner explicitly authorised doing the
setup work directly).

## 5. Verification status of this log

Sections 1–4 are complete and were produced by executed commands.
The SDK extraction, `PATH`/cache configuration and `flutter doctor` results are
recorded below.

---

## 6. Extraction, verification and relocation (appended 2026-09-15)

- All 16 chunks completed. On assembly the archive had the exact expected size
  but **failed** SHA-256 (`4ada96ec…` vs expected `3117330…`). `unzip -t`
  isolated one corrupt member (`flutter/bin/cache/artifacts/engine/
  android-arm-profile/flutter.jar`) lying entirely inside chunk 04; the chunk
  was re-fetched (`_setup/refetch_chunk4.sh`), reassembled, and the archive
  then **passed** SHA-256. Lesson: per-chunk size checks cannot catch corrupt
  content; the final whole-file hash is what caught this.
- Extracted to the path originally planned (`H:\Projects\App sdk and tools\`).
- `flutter --version`: 3.47.4 stable, Dart 3.13.3. `flutter doctor`: OK except
  Android cmdline-tools (missing), Android licences (unsigned) and the Windows
  desktop VS toolchain (absent, not needed).

**Relocation:** with the SDK installed under a path containing a space,
`flutter test` failed to build native assets (`'H:\Projects\App' is not
recognized as an internal or external command` — the native-assets hook runner
spawns the Dart toolchain through an unquoted path). The SDK and pub cache were
moved to space-free paths and all later commands use them:

| Artefact | Final location |
| --- | --- |
| Flutter SDK | `H:\flutter` |
| Pub cache (`PUB_CACHE`) | `H:\pub-cache` |
| Gradle home (`GRADLE_USER_HOME`) | `H:\gradle-home` |

**NDK repair:** `%LOCALAPPDATA%\Android\Sdk\ndk\28.2.13676358` was a malformed
1 KB stub (AGP error CXX1101, missing `source.properties`). The stub was
deleted; the subsequent APK build had AGP re-download NDK 28.2 properly, and
`ndkVersion` is pinned to the healthy `27.1.12297006` in the app Gradle file as
a fallback. NDK/toolchain downloads on this link take a long time and should be
run detached with log polling.

Verification of the SPECTA code itself (analyze / test / build) is recorded in
`docs/PHASE_0_REPORT.md` §A.

---

## 7. Correction recorded 2026-09-16 (Phase 1 second audit)

Section 6 states that the pub cache was moved to `H:\pub-cache`. That does not
match the system as it actually resolves packages today: `.dart_tool/
package_config.json` resolves `flutter_js`, `cryptography` and
`cryptography_flutter` under
`C:\Users\PORTCR\AppData\Local\Pub\Cache` — the default location. The SDK itself
really is at `H:\flutter`, and `GRADLE_USER_HOME` is not set in the shell used
for verification, so Gradle uses its default home under the user profile on C:.
The relocation of the SDK (section 6) is what actually mattered; the pub-cache
line should be read as the intended setting, not the observed one. `PROJECT_STATE.txt`
records the observed paths.
