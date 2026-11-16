#!/usr/bin/env python3
"""Generates the Play Store feature graphic (1024x500) for ExamVault.

Play requires a 1024x500 feature graphic before an app can be published, and the
repo had none — `docs/PLAY_STORE.md` carried a "still to make" note where the
Console expects an upload. This script draws it.

## Why SVG-then-Chrome, not PIL

`make_icons.py` needs Pillow, which this environment does not have (no `pip`, no
PIL, no ImageMagick). The brand assets still have to be regenerable from a clean
checkout, so this script emits an SVG using nothing but the standard library and
rasterises it with the headless Chrome that is already installed. No third-party
imports, no binary assets checked in by hand.

## What it draws, and why it draws only that

Only things the app can back up:

  * the navy canvas (`#0B0F19`) and accent ramp (`#3B82F6` / `#2563EB` /
    `#60A5FA`) the UI already uses;
  * the shield-and-keyhole mark, reusing the exact geometry from
    `tools/branding/make_icons.py` (`_shield`) so the graphic and the launcher
    icon are the same object;
  * the wordmark set in the app's own bundled Plus Jakarta Sans, embedded as a
    data URI so the render never depends on system fonts;
  * the five exam families the app actually tracks (`ExamCategory`: SSC, UPSC,
    Banking, Railways, State PSC).

Deliberately absent: stock photography, invented statistics ("10 lakh users"),
star ratings, device mockups, and screenshots of features that do not exist. A
feature graphic is an advertisement; anything here that the app cannot do is a
policy problem, not just a design one.

## Usage

    python3 tools/branding/make_feature_graphic.py

Writes, relative to the repo root:

    design/exports/feature_graphic_1024x500.svg   (the source, inspectable)
    design/exports/feature_graphic_1024x500.png   (exactly 1024x500, the upload)

The rasterising step is this exact command, run from the repo root:

    google-chrome --headless --disable-gpu --no-sandbox --hide-scrollbars \\
        --force-device-scale-factor=1 --window-size=1024,500 \\
        --user-data-dir="$TMPDIR/ev-feature-graphic" \\
        --screenshot=design/exports/feature_graphic_1024x500.png \\
        "file://$PWD/design/exports/feature_graphic_1024x500.svg"

It is re-runnable and deterministic: the fonts are embedded, the layout is fixed
pixel geometry, and two runs produce byte-identical output. The script fails
loudly if the produced PNG is not exactly 1024x500.

Requirements: `python3` (stdlib only) and `google-chrome` on PATH.
"""

from __future__ import annotations

import base64
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "app" / "assets" / "google_fonts"
OUT = ROOT / "design" / "exports"

# --- brand tokens -----------------------------------------------------------
# Same values as `lib/core/theme/theme_tokens.dart` and `make_icons.py`. The
# accent ramp is the mark's own gradient (light at the top edge, deep at the
# foot) so the graphic and the launcher icon read as one product.
NAVY = "#0B0F19"
BLUE = "#3B82F6"
BLUE_DEEP = "#2563EB"
BLUE_LIGHT = "#60A5FA"
BLUE_TEXT = "#93C5FD"
WHITE = "#F9FAFB"
GREY = "#9CA3AF"
GREY_DIM = "#7C8AA3"

W, H = 1024, 500

# --- geometry (fixed, so the output is byte-stable across runs) -------------
MARK_BOX = 136.0  # the rounded app-icon tile
# Horizontally centred as a block: the tile, the gap, and the widest text line
# ("Live result radar · instant roll-number checks", ~480px at 23px) measure
# ~674px, so a 175px left margin leaves the same margin on the right. Play
# crops this asset on some surfaces; a centred block survives that.
MARK_X, MARK_Y = 175.0, (H - MARK_BOX) / 2
TEXT_X = MARK_X + MARK_BOX + 58


def _shield(cx: float, cy: float, w: float, h: float) -> list[tuple[float, float]]:
    """A shield: flat top, bevelled shoulders, pointed foot.

    Copied verbatim from `make_icons.py` — this is the brand mark, and a second
    hand-drawn approximation would drift from the launcher icon the first time
    either file changed.
    """
    top, left, right = cy - h / 2, cx - w / 2, cx + w / 2
    shoulder = top + h * 0.44
    return [
        (left, top + h * 0.12),
        (left + w * 0.10, top),
        (right - w * 0.10, top),
        (right, top + h * 0.12),
        (right, shoulder),
        (cx, cy + h / 2),
        (left, shoulder),
    ]


def _poly(points: list[tuple[float, float]]) -> str:
    return " ".join(f"{x:.2f},{y:.2f}" for x, y in points)


def _font_face(family: str, weight: int, filename: str) -> str:
    """A @font-face rule with the TTF inlined as base64.

    WHY embed: headless Chrome has no Plus Jakarta Sans installed, and without
    the font the wordmark silently falls back to DejaVu — a different product.
    Inlining also removes the only environmental dependency from the render.
    """
    data = base64.b64encode((FONTS / filename).read_bytes()).decode("ascii")
    return (
        "@font-face {"
        f' font-family: "{family}"; font-weight: {weight}; font-style: normal;'
        f' src: url(data:font/ttf;base64,{data}) format("truetype");'
        "}"
    )


def build_svg() -> str:
    """The whole graphic. One fixed composition, no randomness, no clock."""
    cx = MARK_X + MARK_BOX / 2
    cy = MARK_Y + MARK_BOX / 2
    # Mark proportions mirror make_icons.py: the shield is 44% wide, 56% tall of
    # the inner box, with a white keyhole at 5% radius. Slightly enlarged here
    # because the tile has no launcher-mask padding to absorb.
    w, h = MARK_BOX * 0.48, MARK_BOX * 0.60
    kr = MARK_BOX * 0.054
    ky = cy - MARK_BOX * 0.042

    styles = "".join(
        [
            _font_face("Plus Jakarta Sans", 800, "PlusJakartaSans-ExtraBold.ttf"),
            _font_face("Plus Jakarta Sans", 600, "PlusJakartaSans-SemiBold.ttf"),
            _font_face("Plus Jakarta Sans", 500, "PlusJakartaSans-Medium.ttf"),
            _font_face("IBM Plex Mono", 600, "IBMPlexMono-SemiBold.ttf"),
        ]
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <style>{styles}</style>
  <!-- The accent wash behind the mark: the same radial glow the launcher icon
       carries, scaled up. It gives the left third a light source without
       introducing a second colour into the brand. -->
  <radialGradient id="glow" cx="0%" cy="50%" r="62%">
    <stop offset="0%" stop-color="{BLUE}" stop-opacity="0.30"/>
    <stop offset="55%" stop-color="{BLUE}" stop-opacity="0.10"/>
    <stop offset="100%" stop-color="{BLUE}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="mark" x1="0%" y1="0%" x2="100%" y2="100%">
    <stop offset="0%" stop-color="{BLUE_LIGHT}"/>
    <stop offset="60%" stop-color="{BLUE_DEEP}"/>
    <stop offset="100%" stop-color="#1D4ED8"/>
  </linearGradient>
  <linearGradient id="tile" x1="0%" y1="0%" x2="100%" y2="100%">
    <stop offset="0%" stop-color="#16213A"/>
    <stop offset="100%" stop-color="#0E1524"/>
  </linearGradient>
  <linearGradient id="rule" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="{BLUE}"/>
    <stop offset="100%" stop-color="{BLUE}" stop-opacity="0"/>
  </linearGradient>
</defs>

<rect width="{W}" height="{H}" fill="{NAVY}"/>
<rect width="{W}" height="{H}" fill="url(#glow)"/>

<!-- App icon tile, then the mark itself. The tile is the icon's own navy
     surface, so the shield sits on the same background as on a home screen. -->
<rect x="{MARK_X}" y="{MARK_Y}" width="{MARK_BOX}" height="{MARK_BOX}" rx="30"
      fill="url(#tile)" stroke="#243044" stroke-width="1.5"/>
<polygon points="{_poly(_shield(cx, cy, w, h))}" fill="url(#mark)"/>
<polygon points="{_poly(_shield(cx, cy, w, h))}" fill="none"
         stroke="{BLUE_LIGHT}" stroke-width="2.4" stroke-linejoin="round"/>
<circle cx="{cx:.2f}" cy="{ky:.2f}" r="{kr:.2f}" fill="{WHITE}"/>
<polygon points="{_poly([
        (cx - kr * 0.52, ky + kr * 0.45),
        (cx + kr * 0.52, ky + kr * 0.45),
        (cx + kr * 0.26, ky + kr * 2.45),
        (cx - kr * 0.26, ky + kr * 2.45),
    ])}" fill="{WHITE}"/>

<!-- Wordmark. "ExamVault" is the exact listing name; no tagline invention.
     The whole text block is vertically centred against the mark: the block
     spans the wordmark's cap-top (~183) to the mono line's baseline (~398) and
     is shifted up so its centre lands on the tile's centre at y=250. -->
<text x="{TEXT_X}" y="196" font-family="Plus Jakarta Sans" font-weight="800"
      font-size="72" letter-spacing="-1.8" fill="{WHITE}">ExamVault</text>

<rect x="{TEXT_X + 2}" y="222" width="196" height="3" rx="1.5" fill="url(#rule)"/>

<!-- Three capabilities, each verifiable in the app: the encrypted vault
     (secure_vault_store.dart), the live radar (live_feed_repository.dart) and
     the roll-number checker (roll_index_engine.dart). -->
<text x="{TEXT_X}" y="268" font-family="Plus Jakarta Sans" font-weight="600"
      font-size="23" fill="{BLUE_TEXT}">Encrypted admit-card vault</text>
<text x="{TEXT_X}" y="302" font-family="Plus Jakarta Sans" font-weight="500"
      font-size="23" fill="{GREY}">Live result radar · instant roll-number checks</text>

<!-- The five exam families the app tracks (ExamCategory.values). -->
<text x="{TEXT_X}" y="358" font-family="IBM Plex Mono" font-weight="600"
      font-size="14" letter-spacing="2.6" fill="{GREY_DIM}">SSC · UPSC · BANKING · RAILWAYS · STATE PSC</text>
</svg>
"""


def png_size(path: Path) -> tuple[int, int]:
    """Reads width/height from the PNG IHDR chunk — no image library needed."""
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    width, height = struct.unpack(">II", raw[16:24])
    return width, height


def render_png(svg_path: Path, png_path: Path) -> None:
    """Rasterises the SVG with headless Chrome at exactly 1024x500.

    The flags that matter:
      --window-size=1024,500        the screenshot is the window size
      --force-device-scale-factor=1 headless Chrome otherwise honours the host
                                    DPI and silently emits 2048x1000 on a 2x box
      --hide-scrollbars             an SVG taller than the window would grow a bar
      --user-data-dir=<temp>        avoids the "profile is already in use" failure
                                    when a browser is open, and keeps the render
                                    independent of local profile state
    """
    png_path.parent.mkdir(parents=True, exist_ok=True)
    # A throwaway profile in the system temp dir: reusing the user's real Chrome
    # profile fails with "profile is already in use", and keeping the profile
    # under design/exports/ would leave render debris in the repo.
    with tempfile.TemporaryDirectory(prefix="ev-feature-graphic-") as profile:
        chrome = [
            "google-chrome",
            "--headless",
            "--disable-gpu",
            "--no-sandbox",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--window-size=1024,500",
            f"--user-data-dir={profile}",
            f"--screenshot={png_path}",
            svg_path.as_uri(),
        ]
        subprocess.run(chrome, check=True, capture_output=True)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    svg_path = OUT / "feature_graphic_1024x500.svg"
    png_path = OUT / "feature_graphic_1024x500.png"

    svg_path.write_text(build_svg(), encoding="utf-8")
    render_png(svg_path, png_path)

    width, height = png_size(png_path)
    if (width, height) != (W, H):
        raise SystemExit(
            f"feature graphic is {width}x{height}, Play requires {W}x{H}"
        )
    print(f"wrote {svg_path.relative_to(ROOT)}")
    print(f"wrote {png_path.relative_to(ROOT)} ({width}x{height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
