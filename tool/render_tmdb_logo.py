#!/usr/bin/env python3
"""Fetch and rasterize the official TMDB logo into a SPECTA app asset.

Why this is a script and not a checked-in binary alone
------------------------------------------------------
TMDB's terms of use require the logo to be one of THEIR APPROVED logos, used
unmodified: "Our logo should not be modified in color, aspect ratio, flipped or
rotated." So the asset must come from TMDB, not be redrawn, recoloured or
recomposed by us. Keeping the fetch here records exactly where it came from and
lets it be re-derived if TMDB ever revises the artwork.

Source of truth: https://www.themoviedb.org/about/logos-attribution
The specific file is their "Primary short (blue)" mark.

Why Chrome
----------
The approved logo is an SVG and Flutter cannot rasterize SVG without adding
`flutter_svg` as a dependency, which is not worth it for a single static
attribution image. Headless Chrome is already present on the build machine, so
it renders the SVG at a fixed size and writes a transparent PNG.

Note on Chrome: it can hang after writing the screenshot, so this waits for the
file to appear and then terminates the process rather than waiting for exit.

Usage:
    python tool/render_tmdb_logo.py
"""

from __future__ import annotations

import base64
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "assets" / "images" / "tmdb_logo.png"

# TMDB's "Primary short (blue)" mark, as linked from their logos & attribution
# page. The hash in the filename is TMDB's own content-addressable asset name.
LOGO_URL = (
    "https://www.themoviedb.org/assets/v4/logos/v2/"
    "blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg"
)

# The SVG's intrinsic aspect ratio is 273.42 x 35.52. Rendering at 900px wide
# gives a 4x-plus asset for the ~180dp the credit row displays, so it stays
# crisp on high-density screens without shipping anything oversized.
RENDER_WIDTH = 900

CHROME_CANDIDATES = (
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
)


def find_chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    raise SystemExit(
        "No Chrome/Chromium found. Install one or rasterize LOGO_URL by hand."
    )


def download_svg() -> str:
    request = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=45) as response:
        body = response.read().decode("utf-8", "replace")
    if "<svg" not in body:
        raise SystemExit(f"Did not receive an SVG from {LOGO_URL}")
    return body


def render(chrome: str, svg: str, width: int, height: int, target: Path) -> None:
    payload = base64.b64encode(svg.encode()).decode()
    html = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<style>html,body{margin:0;padding:0;background:transparent}"
        f"img{{width:{width}px;height:{height}px;display:block}}</style></head>"
        f"<body><img src='data:image/svg+xml;base64,{payload}'></body></html>"
    )

    with tempfile.TemporaryDirectory() as work:
        page = Path(work) / "logo.html"
        page.write_text(html, encoding="utf-8")

        process = subprocess.Popen(
            [
                chrome,
                "--headless=new",
                "--disable-gpu",
                "--no-sandbox",
                "--hide-scrollbars",
                "--force-device-scale-factor=1",
                # Transparent background, so the logo composites onto whatever
                # surface it is placed on.
                "--default-background-color=00000000",
                f"--window-size={width},{height}",
                f"--screenshot={target}",
                page.as_uri(),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Chrome is known to hang after writing the screenshot on Windows, so
        # poll for the artefact rather than waiting on process exit.
        deadline = time.time() + 60
        try:
            while time.time() < deadline:
                if target.exists() and target.stat().st_size > 0:
                    # Give it a moment to finish flushing the PNG.
                    time.sleep(0.5)
                    return
                if process.poll() is not None:
                    return
                time.sleep(0.25)
            raise SystemExit("Chrome did not produce a screenshot in time.")
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()


def main() -> int:
    svg = download_svg()
    # Preserve TMDB's aspect ratio exactly; any other ratio would be a
    # modification of the mark.
    height = round(RENDER_WIDTH * 35.52 / 273.42)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    render(find_chrome(), svg, RENDER_WIDTH, height, OUTPUT)

    if not OUTPUT.exists() or OUTPUT.stat().st_size == 0:
        print("Rasterization produced no file.", file=sys.stderr)
        return 1

    print(f"source  : {LOGO_URL}")
    print(f"output  : {OUTPUT.relative_to(REPO_ROOT)}")
    print(f"size    : {RENDER_WIDTH}x{height} px (unmodified aspect ratio)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
