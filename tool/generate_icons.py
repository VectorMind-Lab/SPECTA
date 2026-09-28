#!/usr/bin/env python3
"""Generate SPECTA's Android launcher icons from the supplied master artwork.

The master is a 1600x1600 designed tile: a bright cyan "S" mark on a dark navy
ground, with a soft cyan glow in its lower-right. Android needs that artwork in
several different shapes, and every one is derived from the SAME master so the
brand can never drift between them:

  1. Legacy launcher icons (`mipmap-*/ic_launcher.png`) for Android < 8.0.
     These use the master tile whole and unmodified, which is what the designer
     drew, downscaled once with Lanczos (never repeatedly, and never upscaled).

  2. A legacy CIRCULAR icon (`mipmap-*/ic_launcher_round.png`) for launchers
     that ask for a round icon before API 26.

  3. An ADAPTIVE icon (`mipmap-anydpi-v26/`) for API 26+, which the launcher
     masks to whatever shape the device uses. This cannot be pre-composed as a
     flat tile:
       * the `background` layer is the tile's own ground colour, MEASURED from
         the artwork rather than invented;
       * the `foreground` layer is the whole master, scaled so the mark sits
         inside the 72dp guaranteed-visible zone and centred on transparency.
     Scaling the whole master (rather than cutting the mark out) is deliberate:
     see "Why the whole master" below.

  4. `assets/images/app_icon.png`, the in-app brand asset used by the splash and
     the About surface, with the tile's rounded corners made transparent so it
     composites cleanly onto any background.

Why the whole master, not a cut-out mark
----------------------------------------
Cutting the mark out is not possible honestly here. The mark and the lower-right
glow are the SAME hue and nearly the same brightness (measured: mark luma ~137,
glow luma ~104), so no luminance key separates them, and they are connected, so
no flood fill separates them either. A luminance key produced a 1189x1288 blob
spanning both, which would have baked the glow into the silhouette.

Scaling the whole master sidesteps this and is actually cleaner: the master's
outer edge is flat dark navy that already matches the measured background
colour, and at the chosen scale the master's edge falls OUTSIDE the 72dp
visible zone in every mask shape. The background therefore meets the master
edge invisibly, and the glow is cropped away by the mask exactly as the
launcher intends.

The mark's position and size are MEASURED, not assumed, by high-pass filtering
the master (the mark has sharp edges, the glow is smooth) and taking the
bounding box of the response. If the detection ever fails, this script says so
instead of silently emitting a mis-scaled icon.

Usage:
    python tool/generate_icons.py [path/to/master.png]

The master itself is intentionally NOT kept in the repository; the generated
PNGs are the committed artefacts.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# --- Layout constants -------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = REPO_ROOT / "android" / "app" / "src" / "main" / "res"
APP_ASSET = REPO_ROOT / "assets" / "images" / "app_icon.png"

DEFAULT_MASTER = Path(r"C:\Users\PORTCR\Music\lib\app icon.jpg")

# Density bucket -> legacy icon edge length in pixels.
LEGACY_SIZES: dict[str, int] = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Adaptive icons are authored on a 108dp canvas. The launcher guarantees only
# the centre 72dp is visible, so 432px is the 108dp canvas at 4x (xxxhdpi).
ADAPTIVE_CANVAS_PX = 432

# The mark's longest edge as a fraction of the 108dp canvas. The guaranteed
# visible area is 72/108 = 0.667 (a 144px radius on the 432px canvas), so the
# mark must not reach past that.
#
# Measured, not guessed: at 0.54 the mark's furthest pixel sat at radius 146.4
# and 97 pixels were clipped by circular masks. The mark's furthest pixel sits
# at 0.628 x its edge length from the centre, so the largest edge that clears a
# 144px radius is 144 / 0.628 = 229px, i.e. 0.531 of the canvas. 0.52 leaves a
# deliberate ~3px safety margin on top of that.
MARK_FRACTION = 0.52

# In-app brand asset edge length.
APP_ASSET_PX = 512

# Edge length, in dp, of the mark shown on the native launch window (the frame
# Android draws before Flutter's first frame). Emitted per density so it is the
# same physical size on every device.
LAUNCH_ICON_DP = 96

# Corner radius of the in-app asset, as a fraction of its edge. Matches the
# rounded-square proportion of the supplied master.
APP_ASSET_CORNER = 0.225

# High-pass detection: blur radius (in master pixels) and the response floor.
# A larger radius suppresses more of the smooth glow; the floor rejects the
# last of it plus JPEG ringing.
HIGHPASS_BLUR_RADIUS = 40
HIGHPASS_FLOOR = 35


def measure_mark(master: Image.Image) -> tuple[int, int, int, int]:
    """Locate the mark in [master] and return its bounding box.

    The mark is the image's sharp high-contrast structure; the glow is a smooth
    gradient. Subtracting a heavily blurred copy therefore keeps the mark and
    flattens the glow to near zero, which is what makes the two separable.
    """
    grey = master.convert("L")
    blurred = grey.filter(ImageFilter.GaussianBlur(HIGHPASS_BLUR_RADIUS))
    highpass = ImageChops.difference(grey, blurred)

    response = highpass.point(lambda value: 255 if value >= HIGHPASS_FLOOR else 0)
    bbox = response.getbbox()
    if bbox is None:
        raise SystemExit(
            "Could not locate the mark in the master artwork. "
            "Adjust HIGHPASS_BLUR_RADIUS / HIGHPASS_FLOOR and re-run."
        )
    return bbox


def measure_ground_colour(master: Image.Image) -> tuple[int, int, int]:
    """Return the tile's ground colour, measured from the master's border ring.

    The median (not the mean) is used deliberately: the master's lower-right
    corner carries a bright glow, and an average of the four corners came out
    as a teal #012B3F that is nothing like the actual ground. The median of the
    whole border ring ignores that outlier and returns the real dark navy.
    """
    rgb = master.convert("RGB")
    width, height = rgb.size
    band = max(1, min(width, height) // 50)

    ring = [
        rgb.crop((0, 0, width, band)),  # top
        rgb.crop((0, height - band, width, height)),  # bottom
        rgb.crop((0, 0, band, height)),  # left
        rgb.crop((width - band, 0, width, height)),  # right
    ]

    channels: list[list[int]] = [[], [], []]
    for strip in ring:
        for pixel in strip.get_flattened_data():
            for index in range(3):
                channels[index].append(pixel[index])

    return tuple(sorted(channel)[len(channel) // 2] for channel in channels)  # type: ignore[return-value]


def write_legacy_icons(master: Image.Image) -> list[Path]:
    """Write the square legacy icons, one Lanczos downscale per density."""
    written: list[Path] = []
    for bucket, size in LEGACY_SIZES.items():
        target_dir = ANDROID_RES / f"mipmap-{bucket}"
        target_dir.mkdir(parents=True, exist_ok=True)

        square = master.convert("RGB").resize((size, size), Image.LANCZOS)
        square_path = target_dir / "ic_launcher.png"
        square.save(square_path, "PNG", optimize=True)
        written.append(square_path)

        # Round variant for pre-API-26 launchers that request one. The mask is
        # drawn at 4x and downscaled so the circle's edge is anti-aliased
        # instead of visibly stepped, which a direct 48px mask would be.
        supersample = 4
        mask = Image.new("L", (size * supersample, size * supersample), 0)
        ImageDraw.Draw(mask).ellipse(
            (0, 0, size * supersample - 1, size * supersample - 1), fill=255
        )
        mask = mask.resize((size, size), Image.LANCZOS)

        round_icon = square.convert("RGBA")
        round_icon.putalpha(mask)
        round_path = target_dir / "ic_launcher_round.png"
        round_icon.save(round_path, "PNG", optimize=True)
        written.append(round_path)

    return written


def write_adaptive_icon(master: Image.Image, mark: tuple[int, int, int, int], ground: tuple[int, int, int]) -> list[Path]:
    """Write the adaptive foreground, its ground colour, and both descriptors."""
    master_size = master.size[0]
    mark_edge = max(mark[2] - mark[0], mark[3] - mark[1])

    # Scale the WHOLE master so the MEASURED mark lands at MARK_FRACTION of the
    # 108dp canvas. Using the measured size means the result does not depend on
    # how much padding the master happened to ship with.
    scale = (MARK_FRACTION * ADAPTIVE_CANVAS_PX) / mark_edge
    art_edge = max(1, round(master_size * scale))

    art = master.convert("RGBA").resize((art_edge, art_edge), Image.LANCZOS)

    foreground = Image.new("RGBA", (ADAPTIVE_CANVAS_PX, ADAPTIVE_CANVAS_PX), (0, 0, 0, 0))
    foreground.alpha_composite(art, ((ADAPTIVE_CANVAS_PX - art_edge) // 2,) * 2)

    written: list[Path] = []

    drawable = ANDROID_RES / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    foreground_path = drawable / "ic_launcher_foreground.png"
    foreground.save(foreground_path, "PNG", optimize=True)
    written.append(foreground_path)

    values = ANDROID_RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    ground_path = values / "ic_launcher_background.xml"
    ground_path.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Generated by tool/generate_icons.py from the SPECTA master artwork.\n"
        "     Re-run the generator instead of hand-editing. -->\n"
        "<resources>\n"
        f'    <color name="ic_launcher_background">'
        f"#{ground[0]:02X}{ground[1]:02X}{ground[2]:02X}</color>\n"
        "</resources>\n",
        encoding="utf-8",
    )
    written.append(ground_path)

    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        descriptor = anydpi / name
        descriptor.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tool/generate_icons.py from the SPECTA master artwork. -->\n"
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n",
            encoding="utf-8",
        )
        written.append(descriptor)

    return written


def write_launch_icons(master: Image.Image) -> list[Path]:
    """Write the native launch-window mark, one per density bucket.

    These are what removes the stock white flash: `launch_background.xml`
    referenced `@android:color/white` before, so a light-mode device showed a
    white rectangle before Flutter drew its first frame.

    A separate asset is required rather than reusing `@mipmap/ic_launcher`,
    because from API 26 that name resolves to an XML `<adaptive-icon>` — which
    a `<bitmap>` item cannot draw, so the launch screen would fail to build.
    """
    written: list[Path] = []
    for bucket, legacy_px in LEGACY_SIZES.items():
        size = round(LAUNCH_ICON_DP * legacy_px / LEGACY_SIZES["mdpi"])
        target_dir = ANDROID_RES / f"drawable-{bucket}"
        target_dir.mkdir(parents=True, exist_ok=True)

        # Alpha-round the corners so the mark composites onto the launch
        # window's own background colour with no visible square edge.
        supersample = 4
        mask = Image.new("L", (size * supersample,) * 2, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, size * supersample - 1, size * supersample - 1),
            radius=round(size * supersample * APP_ASSET_CORNER),
            fill=255,
        )
        mask = mask.resize((size, size), Image.LANCZOS)

        icon = master.convert("RGBA").resize((size, size), Image.LANCZOS)
        icon.putalpha(mask)
        path = target_dir / "specta_launch_icon.png"
        icon.save(path, "PNG", optimize=True)
        written.append(path)

    return written


def write_app_asset(master: Image.Image) -> Path:
    """Write the in-app brand asset with transparent rounded corners."""
    APP_ASSET.parent.mkdir(parents=True, exist_ok=True)

    supersample = 4
    mask = Image.new("L", (APP_ASSET_PX * supersample,) * 2, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, APP_ASSET_PX * supersample - 1, APP_ASSET_PX * supersample - 1),
        radius=round(APP_ASSET_PX * supersample * APP_ASSET_CORNER),
        fill=255,
    )
    mask = mask.resize((APP_ASSET_PX, APP_ASSET_PX), Image.LANCZOS)

    asset = master.convert("RGBA").resize((APP_ASSET_PX, APP_ASSET_PX), Image.LANCZOS)
    asset.putalpha(mask)
    asset.save(APP_ASSET, "PNG", optimize=True)
    return APP_ASSET


def main() -> int:
    master_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_MASTER
    if not master_path.exists():
        print(f"Master artwork not found: {master_path}", file=sys.stderr)
        return 1

    master = Image.open(master_path)
    print(f"master       : {master_path}")
    print(f"             : {master.format} {master.mode} {master.width}x{master.height}")

    mark = measure_mark(master)
    mark_edge = max(mark[2] - mark[0], mark[3] - mark[1])
    print(
        f"mark         : bbox {mark}  {mark[2] - mark[0]}x{mark[3] - mark[1]}"
        f"  ({(mark[2] - mark[0]) / master.width:.3f} of master)"
    )

    ground = measure_ground_colour(master)
    print(f"ground       : #{ground[0]:02X}{ground[1]:02X}{ground[2]:02X}")

    scale = (MARK_FRACTION * ADAPTIVE_CANVAS_PX) / mark_edge
    print(
        f"adaptive     : master scaled {scale:.3f} -> {round(master.width * scale)}px "
        f"on a {ADAPTIVE_CANVAS_PX}px canvas (mark at {MARK_FRACTION:.0%})"
    )

    for path in write_legacy_icons(master):
        print(f"legacy       : {path.relative_to(REPO_ROOT)}")

    for path in write_adaptive_icon(master, mark, ground):
        print(f"adaptive     : {path.relative_to(REPO_ROOT)}")

    print(f"in-app asset : {write_app_asset(master).relative_to(REPO_ROOT)}")

    for path in write_launch_icons(master):
        print(f"launch icon  : {path.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
