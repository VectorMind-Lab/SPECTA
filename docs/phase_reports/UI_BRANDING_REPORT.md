# Phase report — App identity: launcher icon, splash, TMDB attribution, developer dot

Date: 2026-09-27
Status: **VERIFIED offline** (analyze clean; full suite 1146 passed / 39 skipped /
0 failed; debug APK built). **Not verified on a device** — the owner's phone was
not connected during this session.

---

## 0. Scope actually delivered

| # | Item | State |
| --- | --- | --- |
| 1 | App launcher icon (Android, all densities) | **Done, built** |
| 2 | Adaptive icon (API 26+) | **Done, built** |
| 3 | Round icon (`android:roundIcon`) | **Done, built** |
| 4 | Native launch window branding | **Done, built** |
| 5 | Flutter splash redesign | **Done, tested** |
| 6 | In-app brand asset | **Done** |
| 7 | TMDB attribution (official logo + required notice) | **Done, tested** |
| 8 | Developer dot (green) | **Done, tested** |
| 9 | Disk recovery | **Done** |

---

## 1. The app icon

Before this phase the application shipped the **stock Flutter launcher icon** —
the template files from `flutter create`, 442–1443 bytes each, dated
2026-09-11. Nothing had ever replaced them. The owner supplied the designed mark
as a 1600x1600 JPEG.

### 1.1 Why there is a generator script

`tool/generate_icons.py` produces every icon artefact from the single master, so
the four Android shapes cannot drift apart and a future re-export is one command
rather than six hand-edited binaries.

| Output | Purpose |
| --- | --- |
| `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` (48–192px) | legacy icon, Android < 8.0 |
| `mipmap-*/ic_launcher_round.png` | round icon for pre-API-26 launchers |
| `mipmap-anydpi-v26/ic_launcher.xml`, `ic_launcher_round.xml` | adaptive descriptors |
| `drawable/ic_launcher_foreground.png` (432px) | adaptive foreground layer |
| `values/ic_launcher_background.xml` | adaptive background colour |
| `drawable-*/specta_launch_icon.png` | native launch-window mark |
| `assets/images/app_icon.png` (512px) | in-app brand asset |

Every legacy size is a single Lanczos downscale from the 1600px master. Nothing
is upscaled, stretched or blurred.

### 1.2 The honest problem with the adaptive icon

The obvious approach — cut the "S" out onto transparency — **does not work on
this artwork, and the first attempt at it produced a bad asset.**

The mark and the lower-right glow are the same hue at nearly the same
brightness. Measured on the master:

```
mark  (image centre) luma ≈ 137
glow  (bottom-right) luma ≈ 104   (sampled RGB (0, 142, 182))
```

A luminance key cannot separate those, and the two are connected, so a flood
fill cannot either. The first generator run produced a **1189x1288 blob spanning
both**, which would have baked the glow into the mark's silhouette.

The fix is to stop extracting and scale the **whole master** instead:

* the master's outer edge is flat dark navy that already matches the measured
  ground colour, so it meets the background invisibly;
* at the chosen scale the master's own edge falls **outside** the 72dp
  guaranteed-visible zone, so the launcher's mask crops it away exactly as
  adaptive icons intend;
* the glow is cropped by the mask rather than being part of the silhouette.

The mark's position and size are **measured**, not assumed, by high-pass
filtering the master (the mark has sharp edges; the glow is smooth) and taking
the bounding box of the response. The script fails loudly if that detection
yields nothing, instead of silently emitting a mis-scaled icon.

### 1.3 Verified geometry

Measured on the generated 432px adaptive foreground:

```
mark furthest pixel radius   141.3   vs visible radius 144.1   → 0 pixels clipped
master artwork corner radius 215.7   vs visible radius 144.1   → edge masked away
```

`MARK_FRACTION` is 0.52. It is documented in the script with the measurement
that produced it: at 0.54 the mark's furthest pixel sat at radius 146.4 and 97
pixels were clipped by a circular mask. The mark's furthest pixel lies at
0.628 x its edge length from the centre, so the largest safe edge is 229px, or
0.531 of the canvas; 0.52 leaves a deliberate ~3px margin.

### 1.4 Ground colour

Sampled by **median of the border ring**, not by averaging the four corners. An
average came out as `#012B3F` — a teal that is nothing like the tile — because
the bright lower-right glow dominates it. The median returns `#010F1E`.

---

## 2. A real defect found and fixed: the white launch flash

`android/app/src/main/res/drawable/launch_background.xml` was still the Flutter
template:

```xml
<item android:drawable="@android:color/white" />
```

and both `styles.xml` files parented off `Theme.Light.NoTitleBar`. The effect:
on a light-mode device SPECTA showed a **white rectangle for the entire engine
start-up**, then a dark app. This was not reported by the owner and no test
covered it.

Changed:

* new `values/colors.xml` defining `specta_launch_background` = `#FF080B11`,
  documented as matching `SpectaColors.background`;
* `drawable/launch_background.xml` and `drawable-v21/launch_background.xml` —
  the canvas colour with the brand mark centred;
* `values/styles.xml` and `values-night/styles.xml` — both `LaunchTheme` and
  `NormalTheme` now use `Theme.Black.NoTitleBar` and an explicit dark
  `windowBackground`, so the window behind the Flutter UI is dark too.

The native launch window now draws the same mark on the same colour as the
Flutter splash, so the hand-off is one continuous image.

---

## 3. Splash redesign

The previous splash layered four things on the first frame: a stock "man facing
the city" illustration, a glowing logo wordmark, a feature-pillar tagline block
("MORE SOURCES / MORE POSSIBILITIES"), and a manual **"Enter SPECTA"** button.
The owner's assessment was that the launch image "is not that cool, it has some
issues", and asked for a Netflix-style launch.

`lib/features/splash/splash_page.dart` is now a single centred reveal:

* SPECTA's canvas colour with a soft accent halo;
* the app mark settling in (scale 0.78 → 1.0) with a highlight sweeping across
  it — the sweep is a `ShaderMask` in `BlendMode.srcATop`, so it follows the
  mark's own rounded silhouette rather than banding across its transparent
  corners;
* the SPECTA wordmark fading up, then the tagline;
* nothing else. No button, no illustration, no pillar block.

Behaviour that did **not** change: it still auto-advances after
`SplashState.autoTransitionDelay`, and still records `hasSeenSplash`.

---

## 4. TMDB attribution

### 4.1 What the terms actually require

The owner's concern was that a TMDB logo must be shown to avoid being banned,
and asked for it to be "hidden somewhere in the settings". Reading TMDB's own
FAQ, the requirement is more specific than that — and the settings placement is
not a compromise, it is where TMDB says it must go:

> "You shall use the TMDB logo to identify your use of the TMDB APIs. You shall
> place the following notice **prominently** on your application: *'This product
> uses the TMDB API but is not endorsed or certified by TMDB.'*"
>
> "...the attribution **must be within your application's 'About' or 'Credits'
> type section**."

Also binding:

* the logo must be one of TMDB's **approved** logos, and must not be modified in
  colour, aspect ratio, flipped or rotated;
* the logo must be **less prominent** than the mark that describes SPECTA.

### 4.2 Implementation

`tool/render_tmdb_logo.py` fetches TMDB's "Primary short (blue)" mark from their
logo page and rasterizes it with headless Chrome (Chrome is present on the build
machine; Flutter cannot read SVG without adding `flutter_svg`, which is not
worth a new dependency for one static image). Output is
`assets/images/tmdb_logo.png`, 900x117, transparent, at the SVG's exact aspect
ratio.

`lib/features/settings/settings_view.dart` gains an **About & Credits** section
containing SPECTA's own mark, then a `METADATA` sub-heading with the approved
logo, the required sentence verbatim, the `themoviedb.org` address as selectable
text, and a line stating plainly that TMDB supplies artwork and descriptions
while **playback sources come only from installed extensions**.

The address is **not** a tappable control: SPECTA ships no URL launcher, and a
button that cannot open anything would be a dead control, which this codebase
forbids. The notice and address are always visible rather than collapsed, which
is what "prominently" requires.

The required sentence and the address are exported as `tmdbAttributionNotice`
and `tmdbHomepageUrl` so the test can assert the wording has not drifted — a
reworded notice is not compliant and nothing else would catch it.

### 4.3 A test that had to change, and why

`test/features/settings/settings_view_test.dart` asserted:

```dart
expect(find.textContaining('TMDB'), findsNothing);
```

That was a **proxy** for "no credential control". It is now false by design,
because SPECTA is *required* to name TMDB in an About section. The guard was
restated directly at what it always meant — no input exists on the screen:

```dart
expect(find.text('Add API key'), findsNothing);
expect(find.textContaining('API key'), findsNothing);
expect(find.byType(TextField), findsNothing);
```

This was a deliberate, documented edit of an existing assertion, not a
relaxation to make a test pass.

---

## 5. The developer dot

### 5.1 The rule

The owner confirmed the gate: **a valid Ed25519 manifest signature verified
against SPECTA's published key**, i.e. `TrustLevel.official`. Nothing weaker is
accepted:

* **not** an id allowlist — an id is a string the extension chooses for itself;
* **not** a repository listing — `ExtensionCatalogueEntry` carries **no**
  signature field, by explicit design;
* **not** the download host — GitHub is distribution, not identity.

This is documented at length in the widget itself, because the dangerous future
change is someone wiring the dot to a cheaper signal.

### 5.2 Implementation

`lib/ui/widgets/specta_developer_dot.dart` — a 7px circle in the existing
`SpectaColors.success`, with the existing palette reused and no new colour
introduced. It is wrapped in `ExcludeSemantics`: it is a private signal, so a
screen reader must announce neither it nor an explanatory label.

Rendered in `extensions_view.dart` on the installed-extension card, immediately
after the (flexible) name so a truncated title cannot hide it.

### 5.3 Where the dot is NOT shown, and why

The original request was for the dot on the installed list **and** the
repository/catalogue lists. **It is only on the installed list**, and this is a
deliberate honesty decision rather than an omission:

**Nothing in a repository listing has been verified.** The catalogue document
deliberately has no signature field — `extension_catalogue.dart` says so in its
own header, warning that adding one "would invite exactly the wrong inference:
that 'listed officially' means 'trusted'". A catalogue entry is a claim by a
document the user supplied. Drawing a trust mark from it would mean the dot
proves nothing, which is precisely the failure mode the mark must avoid.

Showing the dot in the repository list would require downloading and verifying
every listed entry on browse. That is a real feature, not a rendering change,
and it was not in scope. **It is offered as a follow-up, not claimed.**

### 5.4 An unresolved design conflict, raised not hidden

The installed-extension card **already had** a `_TrustBadge` that displays
**"Official"** or **"Unverified"** in text, derived from the same
`TrustLevel`. So the meaning of the dot is currently spelled out on the same
card. The owner's original brief was that the dot needs no label because "only I
will know" — but with the text badge beside it, the dot is not a private signal
at all.

The existing badge was left in place rather than deleted unilaterally, because
it is pre-existing, honest, and tells a non-developer user something useful.
**This needs an owner decision:** remove the text badge so the dot is genuinely
private, or keep both and accept that the dot is decorative redundancy.

---

## 6. Verification

```
flutter analyze  -> No issues found!
flutter test     -> 1146 passed, 39 skipped, 0 failed
```

Baseline before this phase was **1135 passed / 39 skipped / 0 failed**. The
suite grew by exactly the 11 tests added here:

* `test/features/extensions/developer_dot_test.dart` — 4 new
* `test/features/splash/splash_view_test.dart` — 4 new
* `test/features/settings/settings_view_test.dart` — 3 new (new group)

`flutter build apk --debug --target-platform android-arm64` — **SUCCESS**, which
is what proves the new Android resources (adaptive descriptors, both launch
backgrounds, the round icon, `colors.xml`, the re-parented themes) actually
compile. A malformed resource reference would fail here and nowhere else.

### Two defects found by testing, both in this phase's own new tests

1. `expect(find.byType(InkWell), findsNothing)` failed because `Switch` builds
   its own `InkWell`. Replaced with an ancestor check scoped to the credit.
2. `developer_dot_test.dart` **hung** — real file I/O awaited inside a
   `testWidgets` body never completes, because widget tests run in a FakeAsync
   zone. Fixed with `tester.runAsync`, matching the pattern in
   `extensions_view_test.dart`.

### Not verified

* **Nothing was run on a device.** The owner's phone was not connected. The
  launcher icon, adaptive masking, the rounded/round variants, the native launch
  window and the splash reveal are all **built and unit-tested but unconfirmed
  on hardware**.
* The icon was verified **numerically** (clipping and edge analysis on the
  generated PNGs), not by eye on a launcher.

---

## 7. Disk

The owner reported unexplained disk consumption. Root cause found:

**`SPECTA/.._final_audit.txt` — 8.24 GB.** A previous session ran a recursive
`grep` that appended its own output back into itself; the tail is literally
`.._final_audit.txt : 19673 : .._final_audit.txt : 19651 : ...` indefinitely.
Untracked, reproducible, zero unique content. Deleted.

Also removed: `_t.txt`, `_t2.txt`, `.phasec_audit.txt` (31 KB of scratch —
captured `flutter test` logs from a previous disk-full crash and a Phase C grep
audit, both already written up in `docs/phase_reports/`).

Then, when C: hit **230 MB free** and the test runner began hanging with `The
Dart compiler exited unexpectedly` — the same symptom the handover records as
the misleading "The target device is full" error:

* `build/` (1.5 GB) — regenerable Flutter build output, removed. It reaches
  ~1.5 GB on every `flutter build apk` and is the recurring cause of this.
* `AppData/Local/npm-cache` (4.1 GB) — a pure package cache with no bearing on
  Flutter/Dart development.

Net: **C: went 4.3 GB → ~5 GB free**, having peaked at 230 MB free mid-session.

**Open, and needs the owner:** C: is 281 GB with ~277 GB used and only 33 GB of
that under `C:\Users`. `hiberfil.sys` (6.4 GB) and `pagefile.sys` (16.2 GB) are
Windows-managed and were not touched. The remainder was not located — a full
audit needs a tool that is not available here (`du` and Python walks time out on
this volume). `C:\Models` is a candidate worth checking. **Development on this
machine is disk-constrained and will keep failing intermittently until it is
resolved.**

---

## 8. Files changed

| File | Change |
| --- | --- |
| `tool/generate_icons.py` | **new** — icon generator, measurement documented |
| `tool/render_tmdb_logo.py` | **new** — approved TMDB logo fetch + rasterize |
| `android/.../mipmap-*/ic_launcher.png` | replaced (were stock Flutter) |
| `android/.../mipmap-*/ic_launcher_round.png` | **new** |
| `android/.../mipmap-anydpi-v26/ic_launcher{,_round}.xml` | **new** |
| `android/.../drawable/ic_launcher_foreground.png` | **new** |
| `android/.../values/ic_launcher_background.xml` | **new** |
| `android/.../drawable-*/specta_launch_icon.png` | **new** |
| `android/.../values/colors.xml` | **new** |
| `android/.../drawable{,-v21}/launch_background.xml` | white flash removed |
| `android/.../values{,-night}/styles.xml` | dark window themes |
| `android/app/src/main/AndroidManifest.xml` | `android:roundIcon` added |
| `assets/images/app_icon.png` | 192px placeholder → 512px brand asset |
| `assets/images/tmdb_logo.png` | **new** — approved TMDB mark |
| `lib/ui/widgets/specta_developer_dot.dart` | **new** |
| `lib/features/splash/splash_page.dart` | redesigned |
| `lib/features/settings/settings_view.dart` | About & Credits section |
| `lib/features/extensions/extensions_view.dart` | dot on the installed card |
| `test/features/splash/splash_view_test.dart` | **new** — 4 tests |
| `test/features/extensions/developer_dot_test.dart` | **new** — 4 tests |
| `test/features/settings/settings_view_test.dart` | +3 tests, 1 assertion restated |

## 9. Remaining blockers

1. **No device verification** — everything above is offline-verified only.
2. **The green dot / "Official" badge conflict** (§5.4) needs an owner decision.
3. **The dot is not on repository listings** (§5.3) — offered as a follow-up.
4. **C: is critically full** (§7).
5. **Still no reference UI image.** `docs/ui image.png` is deleted in the working
   tree and the supplied reference for the wider UI overhaul never arrived, so
   the screen-by-screen work from the master prompt is **not started**.
6. **Nothing committed.** The working tree remains dirty by design.
