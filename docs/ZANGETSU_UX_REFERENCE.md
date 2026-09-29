# Zangetsu - Android UX Reference

**Observed:** 2026-09-29
**Reference app:** `com.spyou.watch_app` (`MainActivityCrescent`)
**Platform:** Flutter release build, captured on device `SM-A065F`, 720x1600
**Evidence:** 26 `uiautomator` XML dumps (`z_*.xml`) in `docs/zangetsu_evidence/`. Screenshots were captured and used during analysis but are **not retained** in this repository: they are third-party app imagery, and this repository is public. The XML dumps are the primary and sufficient evidence, because Flutter exposes structure through `content-desc` semantics (see Method).
**Android version:** NOT CAPTURED directly - the device disconnected before `getprop` could run. **Inferred, Unverified:** the capture device `SM-A065F` is a Galaxy A06, the same model as SPECTA's own reference device (`R83L20FRDFM`), which runs Android 16 (`SOURCE_RUN_REPORT.md` section 13.4). Android 16 is therefore likely, but it was not observed on the capture device.

This document records what a comparable Android app does, so SPECTA can decide what is worth copying. It is a reference only. No SPECTA code was read or changed while capturing it.

## How this was captured, and why it matters

Zangetsu is a Flutter app. Flutter renders to a single surface and exposes its structure through `content-desc` accessibility semantics, so screenshots alone are not a reliable signal for hierarchy. The `adb shell uiautomator dump` XML was treated as the primary evidence; screenshots were used only to confirm visual arrangement, and were not kept (see Evidence).

Every claim below is labelled:

- **Observed** - present in an XML dump.
- **Unverified** - inferable, but not directly captured.

---

## 1. Navigation

**Observed.** A bottom bar with four destinations:

| Tab |
|---|
| Home |
| My List |
| Sources |
| Profile |

A green circular play control sits in the bar as a decorative element. It is not a destination.

Note the shape of this bar: there is no Search tab and no Downloads tab. Search is reached from inside screens (for example the magnifier in the Sources header), and downloads are handled per-episode from the title page.

---

## 2. Home

**Observed.** A featured carousel at the top (Gintama: THE FINAL 9.1, Sousou no Frieren 9.1, Gintama 9.0), then a stack of horizontally scrolling card rails. Rail cards sit three across, each carrying a star badge with a score, and each rail header has a `See All` affordance.

Rails observed, in order:

1. Recently released
2. Trending
3. Popular this season
4. Upcoming next season
5. All-time popular
6. Top rated
7. Genre rails - Action, Romance

Two entry tiles sit among these:

- **Schedule & lists** (left)
- **Genres** (right)

These are navigation into deeper browse surfaces, not content rails.

---

## 3. Genres

**Observed - two distinct routes, which is easy to miss.**

Route (a), reached from the Home tile, is a plain page: a back bar and a flat list of genre chips. Eighteen genres were present:

Action, Adventure, Comedy, Drama, Ecchi, Fantasy, Horror, Mahou Shoujo, Mecha, Music, Mystery, Psychological, Romance, Sci-Fi, Slice of Life, Sports, Supernatural, Thriller

Route (b), reached from a rail `See All`, is a grid: three columns of posters, each with title and rating.

So Genres is both a chooser and a destination. The chooser is a flat chip list with no grouping, no icons and no counts.

---

## 4. Schedule and lists

**Observed.** Reached from the Home tile. It contains a single section:

`BROWSE`
- **Schedule** - subtitle "What is airing, day by day"

Only one entry exists. The plural name of the tile is not reflected in the body; there is no list-building surface behind it, and My List is a separate nav tab.

---

## 5. Sources

**Observed.** Header plus a search icon, then three tabs:

| Tab | Content |
|---|---|
| Streaming (1 of 3) | Pinned: VegaMovies. Sources: HDHub4u, HiAnime, MultiMovies, UHD Movies |
| Manga (2 of 3) | "No sources installed." |
| Novel (3 of 3) | "No sources installed." |

Every row is subtitled `zangetsu-providers` and is clickable with a trailing chevron. Only the pinned row exposes a pin toggle.

Two things worth recording:

- The Manga and Novel tabs are **empty in this build**. They are taxonomy with nothing behind them.
- `zangetsu-providers` on every row, together with the "No sources installed" wording, indicates the sources are **bundled with the app** rather than installable add-ons. The label is Observed; the bundled-versus-installable conclusion is **Unverified** from the UI alone.

---

## 6. Source detail

**Observed.** Back, title, `Search this source`, and `Show menu`.

- Header: icon, source name, chips `ZANGETSU` and `MOVIE`
- Card rows: `Latest`, `Netflix`, `Amazon Prime` - each with `See All`
- The overflow menu contains exactly **one** action: `Source domain`

There is no per-source settings screen. The `Show menu` is otherwise empty.

---

## 7. Title page

**Observed.** The densest screen in the app.

- **Hero: an autoplaying trailer**, with `Pause trailer` and `Unmute` exposed as semantics. The trailer upstream source was not captured - **Unverified**.
- Actions: `Play`, `Download E1`, and **`Auto Resolve (HiAnime)`** with an adjacent dropdown
- Description with `Read more`
- A resolved-title row carrying **`Wrong title?`**
- `Starring: ... more`
- `Genres:`
- `Creators:`
- A bar: `My List`, `Notify`, `Share`, `Web`

Then four tabs:

| Tab | Observed content |
|---|---|
| Episodes | Grid, refresh control, per-episode download, rating, runtime, airdate |
| Cast | Character mapped to voice actor |
| Relations | Grouped by relation type, for example `OTHER`, `SEQUEL` |
| Details | Source: AniList, Status, Year, Episodes, Studio, Format, Duration, Score 8.3/10, Popularity 637,344, Country, Aired, Native title |

---

## 8. Auto Resolve sheet

**Observed.** Reached from the `Auto Resolve (HiAnime)` control on the title page. This is the most transferable single feature in the app.

- Tabs: `All (1 of 2)` and `Zangetsu (2 of 2)`
- A selectable entry: **`Auto Resolve`** - "Try every installed source until one matches"
- Below it, the same `PINNED` / `SOURCES` grouping used on the Sources screen

The resolve strategy is chosen **per title**, and the user can either let the app sweep every source or pin a specific one.

---

## 9. Corrections to earlier assumptions

- **Metadata source is AniList, not TMDB.** Stated explicitly on the Details tab. No TMDB or trailer-related strings appeared in logcat.
- **Sources appear bundled, not external.** See Section 5.
- **Manga/Novel are declared but empty.** This is not evidence of a working feature.

## Still unverified

Actual playback behaviour, what `Wrong title?` does when pressed, the `Share`/`Notify`/`Web` actions, the contents of My List and Profile, and the trailer provider. None of these were exercised during capture, and this document should not be read as claiming they work.
