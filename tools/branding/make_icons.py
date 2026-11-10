#!/usr/bin/env python3
"""Generates the ExamVault launcher and store icons.

The app shipped Flutter's default logo until this script existed — the single
most visible sign of an unfinished build, and the first thing a store reviewer
sees.

The mark is drawn rather than downloaded so it can be regenerated forever, and it
uses the app's own tokens (`#0B0F19` canvas, `#3B82F6` accent) so the icon and the
UI are visibly the same product.

Drawn at 4× and downsampled: Android renders a 48px icon on mdpi devices, and a
naive 1× polygon shows aliased edges at that size.

    python3 tools/branding/make_icons.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

NAVY = (11, 15, 25)
BLUE = (59, 130, 246)
BLUE_L = (96, 165, 250)
WHITE = (255, 255, 255)

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
WEB = ROOT / "app" / "web"
BRAND = ROOT / "app" / "assets" / "branding"

#: mdpi..xxxhdpi, the five densities Flutter's template ships.
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def _shield(cx: float, cy: float, w: float, h: float) -> list[tuple[float, float]]:
    """A shield: flat top, bevelled shoulders, pointed foot."""
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


def make(size: int, *, with_bg: bool = True, pad_frac: float = 0.0) -> Image.Image:
    """Renders the mark at [size]×[size].

    `with_bg=False` produces an adaptive-icon foreground, which the launcher
    masks itself — so it must be transparent and inset, or the shield's point gets
    cropped on a circular mask.
    """
    scale = 4
    side = size * scale
    base = Image.new(
        "RGBA", (side, side), NAVY + (255,) if with_bg else (0, 0, 0, 0)
    )

    pad = side * pad_frac
    inner = side - 2 * pad
    cx = cy = side / 2

    if with_bg:
        # Radial glow, composited rather than drawn with alpha fills: an alpha fill
        # *replaces* the navy and produced a white disc.
        glow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        for i, alpha in enumerate((34, 24, 15, 9)):
            r = inner * (0.46 - i * 0.045)
            gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLUE + (alpha,))
        base = Image.alpha_composite(
            base, glow.filter(ImageFilter.GaussianBlur(side * 0.012))
        )

    w, h = inner * 0.44, inner * 0.56

    # A soft shadow keeps the shape readable against a busy wallpaper.
    shadow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(
        _shield(cx, cy + inner * 0.020, w * 1.03, h * 1.02), fill=(0, 0, 0, 90)
    )
    base = Image.alpha_composite(
        base, shadow.filter(ImageFilter.GaussianBlur(side * 0.014))
    )

    d = ImageDraw.Draw(base)
    body = _shield(cx, cy, w, h)
    d.polygon(body, fill=BLUE)
    # A lighter bevel is what keeps the edge legible at 48px.
    d.line(body + [body[0]], fill=BLUE_L + (255,), width=max(2, int(inner * 0.012)))

    # Keyhole: the "vault" in ExamVault.
    kr = inner * 0.050
    ky = cy - inner * 0.040
    d.ellipse([cx - kr, ky - kr, cx + kr, ky + kr], fill=WHITE + (255,))
    d.polygon(
        [
            (cx - kr * 0.52, ky + kr * 0.45),
            (cx + kr * 0.52, ky + kr * 0.45),
            (cx + kr * 0.26, ky + kr * 2.45),
            (cx - kr * 0.26, ky + kr * 2.45),
        ],
        fill=WHITE + (255,),
    )

    return base.resize((size, size), Image.LANCZOS)


def main() -> int:
    for name, size in DENSITIES.items():
        out = RES / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)
        make(size).save(out / "ic_launcher.png")
        make(size).save(out / "ic_launcher_round.png")
        make(size, with_bg=False, pad_frac=0.11).save(
            out / "ic_launcher_foreground.png"
        )
        print(f"android  {name:<8} {size}px")

    BRAND.mkdir(parents=True, exist_ok=True)
    icon512 = make(512)
    icon512.save(BRAND / "app_icon_512.png")
    make(512, with_bg=False, pad_frac=0.11).save(
        BRAND / "app_icon_foreground_512.png"
    )

    icons = WEB / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    for fname, size in (("Icon-192.png", 192), ("Icon-512.png", 512)):
        icon512.resize((size, size), Image.LANCZOS).save(icons / fname)

    # Maskable icons are cropped to ~80% by the platform, so the art is inset.
    for fname, size in (("Icon-maskable-192.png", 192), ("Icon-maskable-512.png", 512)):
        canvas = Image.new("RGBA", (size, size), NAVY + (255,))
        inner = int(size * 0.80)
        art = icon512.resize((inner, inner), Image.LANCZOS)
        canvas.paste(art, ((size - inner) // 2, (size - inner) // 2), art)
        canvas.save(icons / fname)

    icon512.resize((64, 64), Image.LANCZOS).save(WEB / "favicon.png")
    print("branding + web icons written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
