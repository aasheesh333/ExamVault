#!/usr/bin/env python3
"""ExamVault — 4-screen SVG sheet for pasting into Figma.

Geometry mirrors design/styles.css exactly: 393x852 frames, 16px gutters,
8px grid. Output is a single SVG whose top-level groups become frames when
pasted as plain text into Figma.
"""

W, H = 393, 852
GAP = 40
BOARD_W = W * 4 + GAP * 3

BG = "#0B0F19"
SURF = "#111827"
SURF2 = "#0E1522"
BORDER = "#1F2937"
BORDER2 = "#263246"
WALLET_BORDER = "#28374F"
BLUE = "#3B82F6"
BLUE_TEXT = "#93C5FD"
BLUE_BRIGHT = "#60A5FA"
GREEN = "#10B981"
GREEN_TEXT = "#6EE7B7"
AMBER = "#F59E0B"
AMBER_TEXT = "#FCD34D"
RED = "#EF4444"
RED_TEXT = "#FCA5A5"
TXT = "#F9FAFB"
TXT2 = "#9CA3AF"
TXT3 = "#8695AB"
ALABASTER = "#F8FAFC"
INK = "#0A0E17"          # always-dark ink (share card). Deliberately NOT #0B0F19
                         # so the theme mapper never inverts it.

# ============================== THEMES ====================================
# Two themes share one geometry. Only colour swaps.
DARK = {
    "bg": "#0B0F19", "surface": "#111827", "sunken": "#0E1522",
    "border": "#1F2937", "border2": "#263246", "wallet_border": "#28374F",
    "text": "#F9FAFB", "text2": "#9CA3AF", "text3": "#8695AB",
    "blue_text": "#93C5FD", "green_text": "#6EE7B7",
    "amber_text": "#FCD34D", "red_text": "#FCA5A5",
}

LIGHT = {
    "bg": "#F6F8FB", "surface": "#FFFFFF", "sunken": "#F1F5F9",
    "border": "#E2E8F0", "border2": "#CBD5E1", "wallet_border": "#C7D8EA",
    "text": "#0F172A", "text2": "#475569", "text3": "#5B6B80",
    "blue_text": "#1D4ED8", "green_text": "#047857",
    "amber_text": "#B45309", "red_text": "#B91C1C",
}

# literal hex -> light replacement. Anything absent keeps its value
# (brand hues, the navy pass cards, semantic status colours).
LIGHT_MAP = {
    # card / control surfaces
    "#111827": "#FFFFFF", "#0E1522": "#F1F5F9", "#1E293B": "#E2E8F0",
    "#1C2739": "#E8EEF6", "#222E41": "#E2E8F0", "#283650": "#CBD5E1",
    "#2A3547": "#E2E8F0", "#243044": "#E2E8F0", "#0F1624": "#F8FAFC",
    # borders
    "#1F2937": "#E2E8F0", "#263246": "#CBD5E1", "#28374F": "#C7D8EA",
    "#94A3B8": "#5B6B80",
    "#D8E4F4": "#0F172A",
    # text ramp (dark -> light)
    "#F9FAFB": "#0F172A", "#FFFFFF": "#0F172A",
    "#E9EDF4": "#0F172A", "#E8EDF4": "#0F172A", "#E7ECF3": "#0F172A",
    "#E4E9F1": "#0F172A", "#E3E9F1": "#0F172A", "#DDE4EE": "#0F172A",
    "#D6DEEA": "#1E293B", "#F3F6FB": "#0F172A", "#E9EEF6": "#0F172A",
    "#F1F5FA": "#0F172A", "#DDF5EA": "#065F46", "#DBEAFE": "#1E3A8A",
    "#BFDBFE": "#1D4ED8", "#AEB9C9": "#475569", "#B9C4D4": "#475569",
    "#B6C0CF": "#475569", "#C7D0DD": "#334155", "#DDE3EC": "#0F172A",
    "#9CA3AF": "#475569", "#8695AB": "#5B6B80", "#8B98AC": "#5B6B80",
    "#8494AB": "#5B6B80", "#94A2B8": "#5B6B80", "#8FA0B8": "#5B6B80",
    "#8291A8": "#5B6B80", "#8291A7": "#5B6B80", "#7C8DA6": "#5B6B80",
    "#718199": "#5B6B80", "#76859B": "#5B6B80", "#6D7C92": "#5B6B80",
    "#66758B": "#5B6B80", "#5B697E": "#7A8899", "#4A5768": "#7A8899",
    "#68778E": "#5B6B80", "#7C8AA3": "#5B6B80", "#7F8DA3": "#475569",
    "#8CA0BA": "#5B6B80", "#7E90A8": "#5B6B80", "#93C5FD": "#1D4ED8",
    "#6EE7B7": "#047857", "#FCD34D": "#B45309", "#FCA5A5": "#B91C1C",
    "#34D399": "#059669", "#E5E7EB": "#0F172A", "#94A3B8": "#CBD5E1",
    # the light "alabaster" share card needs a hairline once the page is light
    "#F8FAFC": "#FFFFFF", "#05070C": "#E8EDF4",
}

THEME = {"name": "dark", "row_y": 0}
CTX = {"on_navy": 0}


def C(hexstr, opacity=1.0):
    """Resolve a colour for the active theme.

    Low-opacity white/black is used for hairlines and inner highlights; on a
    light surface those must flip to dark ink or they vanish.
    """
    if not isinstance(hexstr, str):
        return hexstr
    # Inside the navy pass / wallet cards the surface stays dark in BOTH
    # themes, so its text must NOT be inverted.
    if CTX["on_navy"] > 0 and THEME["name"] == "light":
        return hexstr
    if hexstr.startswith("url(#"):
        return hexstr if THEME["name"] == "dark" else hexstr.replace(")", f"-l)")
    if hexstr == "none":
        return hexstr
    if THEME["name"] == "dark":
        return hexstr
    key = hexstr.upper()
    # hairlines / sheens / inner highlights
    if opacity < 0.4 and key == "#FFFFFF":
        return "#0F172A"
    if opacity < 0.4 and key == "#000000":
        return "#0F172A"
    if key == "#FFFFFF" and opacity >= 0.4:
        # solid white is used both as body text on navy cards (keep) and as
        # card faces (map). Callers pass the mapped token for faces already,
        # so keep white here — it is ink on the navy pass cards and buttons.
        return "#FFFFFF"
    return LIGHT_MAP.get(key, hexstr)


def set_theme(name):
    global BG, SURF, SURF2, BORDER, BORDER2, WALLET_BORDER
    global TXT, TXT2, TXT3, BLUE_TEXT, GREEN_TEXT, AMBER_TEXT, RED_TEXT
    THEME["name"] = name
    t = DARK if name == "dark" else LIGHT
    BG, SURF, SURF2 = t["bg"], t["surface"], t["sunken"]
    BORDER, BORDER2, WALLET_BORDER = t["border"], t["border2"], t["wallet_border"]
    TXT, TXT2, TXT3 = t["text"], t["text2"], t["text3"]
    BLUE_TEXT, GREEN_TEXT = t["blue_text"], t["green_text"]
    AMBER_TEXT, RED_TEXT = t["amber_text"], t["red_text"]


UI = "Plus Jakarta Sans"
MONO = "IBM Plex Mono"

# ---- real text metrics (same TTFs Figma uses) ------------------------------
from PIL import ImageFont

_FONTS = {
    (False, 700): "/usr/share/fonts/truetype/examvault/PlusJakartaSans-Bold.ttf",
    (False, 800): "/usr/share/fonts/truetype/examvault/PlusJakartaSans-ExtraBold.ttf",
    (False, 600): "/usr/share/fonts/truetype/examvault/PlusJakartaSans-SemiBold.ttf",
    (False, 500): "/usr/share/fonts/truetype/examvault/PlusJakartaSans-Medium.ttf",
    (True, 400): "/usr/share/fonts/truetype/examvault/IBMPlexMono-Regular.ttf",
    (True, 500): "/usr/share/fonts/truetype/examvault/IBMPlexMono-Medium.ttf",
    (True, 600): "/usr/share/fonts/truetype/examvault/IBMPlexMono-SemiBold.ttf",
}
_cache = {}


def tw(s, size, weight=500, mono=False, ls=0):
    """Measured advance width in px, letter-spacing included.

    PIL only accepts integer pixel sizes, so text is measured at 10x and scaled
    back — otherwise the fractional part (e.g. 26.5px) is lost and every word
    gap silently cancels out.
    """
    key = (mono, weight if mono else (700 if weight >= 700 else weight))
    path = _FONTS.get(key) or _FONTS[(mono, 500 if mono else 500)]
    probe = max(1, int(round(size * 10)))
    f = _cache.get((path, probe))
    if f is None:
        f = ImageFont.truetype(path, probe)
        _cache[(path, probe)] = f
    return f.getlength(s) * (size / probe) + ls * max(0, len(s) - 1)

out = []
defs = []


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def rect(x, y, w, h, fill="none", rx=0, stroke=None, sw=1, opacity=1, shadow=None):
    fill = C(fill, opacity)
    stroke = C(stroke, 0.9) if stroke else None
    a = [f'x="{x}"', f'y="{y}"', f'width="{w}"', f'height="{h}"', f'fill="{fill}"']
    if rx:
        a.append(f'rx="{rx}"')
    if stroke:
        a.append(f'stroke="{stroke}" stroke-width="{sw}"')
    if opacity != 1:
        a.append(f'opacity="{opacity}"')
    if shadow:
        a.append(f'filter="url(#{shadow}{SFX()})"')
    out.append("<rect " + " ".join(a) + "/>")


def line(x1, y1, x2, y2, stroke="#FFFFFF", sw=1, opacity=0.06, dash=None):
    stroke = C(stroke, opacity)
    d = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" '
        f'stroke-width="{sw}" opacity="{opacity}"{d}/>'
    )


def _word_layout(s, size, weight, mono, ls):
    """Split into words and return [(word, x_offset)] plus total width.

    Plus Jakarta Sans has a broken space/kern pair: a space immediately before
    a digit collapses to zero advance, so "Tier-1 2026" renders "Tier-12026".
    Words are therefore positioned explicitly, with the font's real space
    advance (0.178em UI / 0.6em mono). Deterministic across librsvg, Chrome
    and Figma.
    """
    # Space advance = font space glyph + one extra letter-spacing unit.
    # POSITIVE tracking was widening the gap, negative tracking was eating it,
    # which is what made "RESULT IS LIVE" collapse to "RESULTISLIVE".
    # Plus Jakarta Sans ships a narrow 0.178em space; the source CSS added
    # ~1.4px word-spacing at 17px, so UI text uses 0.26em here to match.
    space_adv = size * (0.6 if mono else 0.26)
    gap = space_adv + ls
    parts = s.split(" ")
    x = 0.0
    laid = []
    for w in parts:
        if w == "":
            x += gap
            continue
        laid.append((w, x))
        x += tw(w, size, weight, mono, ls) + gap
    total = x - gap if laid else 0.0
    return laid, total, gap


def txt(x, y, s, size=12, fill=TXT, weight=500, mono=False, anchor="start",
        ls=0, opacity=1, baseline="middle"):
    fam = MONO if mono else UI
    fill = C(fill, opacity)
    base = [f'font-family="{fam}"', f'font-size="{size}"',
            f'font-weight="{weight}"', f'fill="{fill}"']
    if ls:
        base.append(f'letter-spacing="{ls}"')
    if opacity != 1:
        base.append(f'opacity="{opacity}"')
    base.append(f'dominant-baseline="{baseline}"')

    laid, total, _gap = _word_layout(s, size, weight, mono, ls)
    ox = x
    if anchor == "middle":
        ox = x - total / 2
    elif anchor == "end":
        ox = x - total

    if len(laid) == 1:
        a = [f'x="{round(ox, 2)}"', f'y="{y}"'] + base
        out.append("<text " + " ".join(a) + ">" + esc(laid[0][0]) + "</text>")
        return

    out.append("<g>")
    for word, wx in laid:
        a = [f'x="{round(ox + wx, 2)}"', f'y="{y}"'] + base
        out.append("<text " + " ".join(a) + ">" + esc(word) + "</text>")
    out.append("</g>")


def circle(cx, cy, r, fill, opacity=1, stroke=None, sw=1, filt=None):
    fill = C(fill, opacity)
    stroke = C(stroke, 0.9) if stroke else None
    a = [f'cx="{cx}"', f'cy="{cy}"', f'r="{r}"', f'fill="{fill}"']
    if opacity != 1:
        a.append(f'opacity="{opacity}"')
    if stroke:
        a.append(f'stroke="{stroke}" stroke-width="{sw}"')
    if filt:
        a.append(f'filter="url(#{filt})"')
    out.append("<circle " + " ".join(a) + "/>")


ICON = {
    "vault": "M12 3l7 3v5.5c0 4.3-2.9 7.6-7 9.5-4.1-1.9-7-5.2-7-9.5V6l7-3z|C12 11m-2.4 0a2.4 2.4 0 0 1 4.8 0 2.4 2.4 0 0 1-4.8 0|M12 13.4V16",
    "bell": "M18 8a6 6 0 10-12 0c0 6-2 7-2 7h16s-2-1-2-7|M13.7 20a2 2 0 01-3.4 0",
    "copy": "M9 9h11v11H9z|M15 6.5V5a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2h1.5",
    "chev": "M9 5l7 7-7 7",
    "back": "M15 5l-7 7 7 7",
    "share": "M12 15V3m0 0L8 7m4-4l4 4|M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7",
    "x": "M6 6l12 12M18 6L6 18",
    "search": "M11 4.5a6.5 6.5 0 100 13 6.5 6.5 0 000-13z|M16 16l4 4",
    "download": "M12 3v11m0 0l-4-4m4 4l4-4|M4 18v1a2 2 0 002 2h12a2 2 0 002-2v-1",
    "check": "M4.5 12.5l5 5 10-11",
    "pdf": "M6 2.8h8l4 4V21H6z|M14 3v4.2h4.2|M8.5 16.5h7",
    "clock": "M12 3.5a8.5 8.5 0 100 17 8.5 8.5 0 000-17z|M12 7.5V12l3 2",
    "home": "M4 10.5L12 4l8 6.5V21h-6v-6h-4v6H4v-10.5z",
    "lock": "M4.5 10.5h15v10h-15z|M8 10.5V7.5a4 4 0 018 0v3",
    "radar": "M12 3.5a8.5 8.5 0 100 17 8.5 8.5 0 000-17z|M12 7.8a4.2 4.2 0 100 8.4 4.2 4.2 0 000-8.4z|M12 12l5-5",
    "users": "M9 4.8a3.2 3.2 0 100 6.4 3.2 3.2 0 000-6.4z|M3.5 20c0-3.2 2.5-5.4 5.5-5.4s5.5 2.2 5.5 5.4|M16 5.2a3 3 0 010 5.6M17.5 14.9c1.8.5 3 2.2 3 5.1",
    "external": "M14 4h6v6M20 4l-8 8|M18 14v5a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h5",
    "link": "M10 13.5a4 4 0 005.7 0l3-3a4 4 0 10-5.7-5.7L11.5 6.3|M14 10.5a4 4 0 00-5.7 0l-3 3a4 4 0 105.7 5.7l1.5-1.5",
    "spark": "M12 3l1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7L12 3z",
    "plus": "M12 5v14M5 12h14",
    "pin": "M12 21s7-6.1 7-11a7 7 0 10-14 0c0 4.9 7 11 7 11z|M12 7.4a2.6 2.6 0 100 5.2 2.6 2.6 0 000-5.2z",
    "send": "M21 3L3 10.5l7.2 2.8L13 20l8-17z|M10.2 13.3L21 3",
    "save": "M12 3v11m0 0l-4-4m4 4l4-4|M4 17v2a2 2 0 002 2h12a2 2 0 002-2v-2",
    "whatsapp": "M12 2.4a9.6 9.6 0 00-8.2 14.6L2.4 21.6l4.8-1.3A9.6 9.6 0 1012 2.4z",
}


def icon(name, x, y, size, color, sw=1.7, opacity=1):
    color = C(color, 0.9)
    d = ICON[name]
    scale = size / 24.0
    parts = []
    for seg in d.split("|"):
        if seg.startswith("M") and "a" in seg and seg.count("M") == 1 and seg[1:].startswith("12 "):
            parts.append(f'<path d="{seg}" fill="none" stroke="{color}" stroke-width="{sw * 24 / size:.2f}" stroke-linecap="round" stroke-linejoin="round"/>')
        else:
            parts.append(f'<path d="{seg}" fill="none" stroke="{color}" stroke-width="{sw * 24 / size:.2f}" stroke-linecap="round" stroke-linejoin="round"/>')
    out.append(
        f'<g transform="translate({x} {y}) scale({scale:.5f})" opacity="{opacity}">'
        + "".join(parts) + "</g>"
    )


def pill(x, y, h, label, color, text_color, dot=True, size=8.5, ls=0.5,
         anchor="start", min_w=0):
    """Auto-sized status pill. Returns its width so callers can lay out to it.

    Sizes were bumped from 7.5px to 8.5px: 7.5px uppercase mono is below the
    legible minimum on a 6.1" phone held at arm's length.
    """
    tw_label = tw(label, size, 600, mono=True, ls=ls)
    pad_l = 7 + (10 if dot else 0)
    w = max(min_w, tw_label + pad_l + 8)
    if anchor == "end":
        x = x - w
    rect(x, y, w, h, color, rx=6, opacity=0.12)
    rect(x, y, w, h, "none", rx=6, stroke=color, sw=1, opacity=0.3)
    cx = x + pad_l
    if dot:
        circle(x + 9, y + h / 2, 2.2, color)
    txt(cx, y + h / 2 + 0.5, label, size, text_color, 600, mono=True, ls=ls)
    return w


def SFX():
    return "" if THEME["name"] == "dark" else "-l"


def build_defs():
    """Every gradient / filter / clip for the ACTIVE theme, built once."""
    x = SFX()
    light = THEME["name"] == "light"

    # card shadow: on a light page a 0.55 black shadow reads as dirt
    op = 0.10 if light else 0.55
    blur = 14 if light else 12
    dy = 10 if light else 18
    defs.append(
        f'<filter id="cardShadow{x}" x="-30%" y="-30%" width="160%" height="180%">'
        f'<feDropShadow dx="0" dy="{dy}" stdDeviation="{blur}" flood-color="#0F172A" '
        f'flood-opacity="{op}"/></filter>'
    )

    for i in range(4):
        defs.append(
            f'<clipPath id="frameClip{i}{x}"><rect x="0" y="0" width="{W}" height="{H}"/></clipPath>'
        )

    glow = 0.07 if light else 0.14
    defs.append(
        f'<radialGradient id="topGlow{x}" cx="50%" cy="0%" r="65%">'
        f'<stop offset="0%" stop-color="{BLUE}" stop-opacity="{glow}"/>'
        f'<stop offset="100%" stop-color="{BLUE}" stop-opacity="0"/>'
        "</radialGradient>"
    )

    def g(gid, stops, vertical=False):
        x1, y1, x2, y2 = ("0%", "0%", "0%", "100%") if vertical else ("0%", "0%", "100%", "100%")
        body = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
        defs.append(
            f'<linearGradient id="{gid}{x}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{body}</linearGradient>'
        )

    # The pass / wallet cards stay deep-navy in BOTH themes on purpose: they are
    # physical objects (like Apple Wallet passes), not surfaces. It also keeps
    # the white roll-number text at full contrast.
    g("walletFront", [("0%", "#1E2C46"), ("42%", "#172136"), ("100%", "#121A29")])
    g("walletMid", [("0%", "#1A2438"), ("42%", "#131C2C"), ("100%", "#111A2B")])
    g("walletBack", [("0%", "#1C2433"), ("42%", "#141B28"), ("100%", "#101723")])
    g("passCard", [("0%", "#1A2437"), ("46%", "#141D2E"), ("100%", "#111A2A")])
    g("passGlow", [("0%", "#60A5FA"), ("100%", "#60A5FA")])

    g("markBlue", [("0%", "#60A5FA"), ("60%", "#2563EB"), ("100%", "#1D4ED8")])
    g("pillBlue", [("0%", "#4C8DF7"), ("100%", "#2563EB")])
    g("btnBlue", [("0%", "#4E90F9"), ("55%", "#2F74E8"), ("100%", "#2563EB")])
    g("btnGreen", [("0%", "#31E07A"), ("100%", "#1FBE63")])
    g("alertRed", [("0%", "#F05252"), ("100%", "#DC2626")])

    # sheen + right-edge fade for the chip row
    defs.append(
        f'<linearGradient id="sheen{x}" x1="0%" y1="0%" x2="100%" y2="100%">'
        '<stop offset="30%" stop-color="#FFFFFF" stop-opacity="0"/>'
        '<stop offset="46%" stop-color="#FFFFFF" stop-opacity="0.07"/>'
        '<stop offset="62%" stop-color="#FFFFFF" stop-opacity="0"/>'
        "</linearGradient>"
    )
    defs.append(
        f'<linearGradient id="chipFade{x}" x1="0%" y1="0%" x2="100%" y2="0%">'
        f'<stop offset="0%" stop-color="{BG}" stop-opacity="0"/>'
        f'<stop offset="100%" stop-color="{BG}" stop-opacity="1"/>'
        "</linearGradient>"
    )
    defs.append(
        f'<linearGradient id="dockFade{x}" x1="0%" y1="0%" x2="0%" y2="100%">'
        f'<stop offset="0%" stop-color="{BG}" stop-opacity="0"/>'
        f'<stop offset="100%" stop-color="{BG}" stop-opacity="1"/>'
        "</linearGradient>"
    )


def wa_icon(x, y, size, color, hole=None):
    """Filled WhatsApp bubble with a knocked-out handset."""
    if hole is None:
        hole = BG
    color = C(color, 0.95)
    hole = C(hole, 0.95)
    s = size / 24.0
    out.append(
        f'<g transform="translate({x} {y}) scale({s:.5f})">'
        f'<path d="M12 2.2a9.8 9.8 0 00-8.4 14.9L2.2 21.8l4.9-1.3A9.8 9.8 0 1012 2.2z" fill="{color}"/>'
        f'<path d="M8.6 7.9c.2-.5.5-.6.8-.6h.6c.2 0 .4.1.5.4l.7 1.7c.1.2 0 .5-.2.7l-.5.5c.6 1.2 1.5 2 2.7 2.6l.5-.6c.2-.2.5-.3.7-.2l1.7.8c.2.1.4.3.4.6v.6c0 .7-.6 1.3-1.4 1.4-3.6.4-7.4-3.4-6.9-7 .1-.4.2-.7.4-.9z" fill="{hole}"/>'
        "</g>"
    )


def bg_layer():
    rect(0, 0, W, 330, f"url(#topGlow)")


def statusbar():
    bar = TXT
    txt(26, 26, "9:41", 12.5, bar, 700)
    for i, hh in enumerate([5, 7, 9, 11]):
        rect(296 + i * 5, 31 - hh, 3, hh, bar if i < 3 else bar, rx=1,
             opacity=1 if i < 3 else 0.35)
    for r, op in [(9.5, 0.95), (5.5, 0.95)]:
        out.append(
            f'<path d="M{323 + 7.5 - r} 22a{r} {r} 0 0 1 {2 * r} 0" fill="none" '
            f'stroke="{bar}" stroke-width="1.5" stroke-linecap="round" opacity="{op}"/>'
        )
    circle(330.5, 26, 1.8, bar)
    rect(346, 20, 23, 11, "none", rx=3.5, stroke=bar, sw=1.2, opacity=0.55)
    rect(348, 22.2, 13, 6.6, bar, rx=1.5)
    rect(370, 23.5, 2, 4, bar, rx=1, opacity=0.55)
    # the Dynamic Island is device chrome: always black, in both themes
    rect(147.5, 9, 98, 26, "#020408", rx=13)
    circle(232, 22, 4, "#1E3A8A", opacity=0.55)


def home_indicator(y=838):
    rect(130.5, y, 132, 4, TXT, rx=2, opacity=0.28)


def icon_button(x, y, name, size=34, r=11, fill=SURF, bg_op=0.7, color="#B6C0CF", icon_size=16):
    if fill:
        rect(x, y, size, size, fill, rx=r, opacity=bg_op, stroke=BORDER, sw=1)
    icon(name, x + (size - icon_size) / 2, y + (size - icon_size) / 2, icon_size, color)


def mark(x, y, size=27, r=8, icon_size=15):
    rect(x, y, size, size, "url(#markBlue)", rx=r)
    icon("vault", x + (size - icon_size) / 2, y + (size - icon_size) / 2, icon_size, "#FFFFFF", sw=1.6)


# ============================ FRAME 1 =====================================
def frame1():
    g = [f'<g id="01-home-{THEME["name"]}" transform="translate(0 {THEME['row_y']})"><g clip-path="url(#frameClip0{SFX()})">']
    saved = out.copy(); out.clear()
    rect(0, 0, W, H, BG)
    bg_layer()
    statusbar()

    # app bar
    mark(16, 32)
    txt(52, 46, "EXAMVAULT", 10.5, "#E5E7EB", 600, mono=True, ls=2.6)
    icon_button(307, 30, "bell", 34)
    rect(325, 28, 13, 13, RED, rx=6.5)
    txt(331.5, 35, "3", 7.5, "#FFFFFF", 700, mono=True, anchor="middle")
    circle(360, 47, 16, "#1E293B", stroke="#93C5FD", sw=1)
    txt(360, 47.5, "A", 11.5, "#DBEAFE", 700, anchor="middle")

    # hero
    txt(16, 110, "SUNDAY · 08 NOV 2026", 9, "#7C8AA3", 400, mono=True, ls=1.7)
    txt(16, 140, "Command Center", 26.5, TXT, 700, ls=-0.2)
    _s1 = "3 exams tracked"
    txt(16, 164, _s1, 11.5, TXT2, 500)
    _x = 16 + tw(_s1, 11.5, 500) + 7
    txt(_x, 164, "·", 11.5, "#3A4658", 500)
    txt(_x + tw("·", 11.5, 500) + 7, 164, "3 live updates", 11.5, GREEN, 500)

    # chips
    chips = [("All Exams", 16, True), ("SSC", 0, False), ("UPSC", 0, False),
             ("IBPS/SBI", 0, False), ("Railways", 0, False), ("State PSC", 0, False)]
    _cx = 16
    for label, _x0, active in chips:
        w = tw(label, 11, 600) + 26
        rect(_cx, 180, w, 30, BLUE if active else SURF, rx=15, opacity=0.15 if active else 0.55)
        rect(_cx, 180, w, 30, "none", rx=15, stroke=BLUE if active else BORDER, sw=1,
             opacity=0.45 if active else 1)
        txt(_cx + w / 2, 195.5, label, 11, "#BFDBFE" if active else "#AEB8C7", 600, anchor="middle")
        _cx += w + 7
    # right fade so the 6th chip reads as "scroll for more"
    rect(345, 180, 48, 30, "url(#chipFade)")

    # section head  — "3 saved >" was a dead chevron; a vault needs an add path
    txt(16, 246, "MY ADMIT CARDS", 9, TXT3, 500, mono=True, ls=1.6)
    txt(272, 246, "3 saved", 9.5, "#7F8DA3", 600, anchor="end")
    rect(284, 234, 93, 24, BLUE, rx=12, opacity=0.14)
    rect(284, 234, 93, 24, "none", rx=12, stroke=BLUE, sw=1, opacity=0.4)
    icon("plus", 292, 241, 10, BLUE_TEXT, sw=2.2)
    txt(306, 246, "Add exam", 9.5, BLUE_TEXT, 600)

    # wallet stack — the pass objects keep their own dark surface
    CTX["on_navy"] += 1
    wcy = 264
    rect(36, wcy, 321, 164, "url(#walletBack)", rx=20, stroke=BORDER, sw=1, opacity=0.94, shadow="cardShadow")
    rect(36, wcy + 13, 1, 1, "none")
    pill(52, wcy + 13, 20, "RRB", AMBER, AMBER_TEXT, dot=False, size=8.5, ls=1.0)
    txt(102, wcy + 23, "RRB NTPC 2026", 11.5, "#D6DEEA", 600)
    txt(341, wcy + 23, "In 34 days", 8.5, "#8291A8", 400, mono=True, anchor="end")

    rect(26, wcy + 40, 341, 164, "url(#walletMid)", rx=20, stroke=BORDER, sw=1, opacity=0.97, shadow="cardShadow")
    pill(42, wcy + 53, 20, "IBPS", BLUE, "#BFDBFE", dot=False, size=8.5, ls=1.0)
    txt(94, wcy + 63, "IBPS PO Prelims 2026", 11.5, "#D6DEEA", 600)
    txt(351, wcy + 63, "In 21 days", 8.5, "#8291A8", 400, mono=True, anchor="end")

    fy = wcy + 88
    rect(16, fy, 361, 176, "url(#walletFront)", rx=20, stroke=WALLET_BORDER, sw=1, shadow="cardShadow")
    rect(36, fy + 1, 321, 1, "#FFFFFF", opacity=0.15)
    rect(16, fy, 361, 176, "url(#sheen)", rx=20)

    pill(32, fy + 17, 20, "SSC", BLUE, "#BFDBFE", dot=False, size=8.5, ls=1.0)
    txt(78, fy + 27, "CGL · TIER-1", 8.5, "#7C8DA6", 400, mono=True, ls=1.4)
    rect(268, fy + 16, 94, 22, AMBER, rx=11, opacity=0.11)
    rect(268, fy + 16, 94, 22, "none", rx=11, stroke=AMBER, sw=1, opacity=0.28)
    circle(277, fy + 27, 2.5, AMBER)
    txt(285, fy + 27.5, "IN 12 DAYS", 8.5, AMBER_TEXT, 600, mono=True, ls=0.9)

    txt(32, fy + 62, "SSC CGL Tier-1 2026", 17, "#F3F6FB", 700)
    txt(32, fy + 105, "ROLL NUMBER", 8.5, TXT3, 500, mono=True, ls=1.25)
    txt(32, fy + 128, "2201049821", 23, "#FFFFFF", 500, mono=True, ls=1.2)

    rect(292, fy + 100, 70, 31, "url(#pillBlue)", rx=15.5)
    icon("copy", 303, fy + 109, 12, "#FFFFFF", sw=1.7)
    txt(319, fy + 116, "Copy", 10, "#FFFFFF", 700)

    line(32, fy + 148, 361, fy + 148, "#FFFFFF", 1, 0.07)
    txt(32, fy + 159, "20 NOV 2026 · 09:00 AM", 9.5, TXT2, 400, mono=True, ls=0.55)
    _so = "SAVED OFFLINE"
    _sow = tw(_so, 8, 600, mono=True, ls=1.2)
    circle(361 - _sow - 10, fy + 159, 2, GREEN)
    txt(361, fy + 159, _so, 8, GREEN_TEXT, 600, mono=True, ls=1.2, anchor="end")

    CTX["on_navy"] -= 1

    # live radar
    circle(19, 552, 3, GREEN)
    txt(31, 552, "LIVE RADAR", 9, TXT3, 500, mono=True, ls=1.6)
    txt(377, 552, "UPDATED 12S AGO", 8.5, "#8695AB", 400, mono=True, ls=1.1, anchor="end")

    feed_top = 566
    rect(16, feed_top, 361, 179, SURF, rx=18, stroke=BORDER, sw=1)
    rows = [
        ("pdf", GREEN, GREEN_TEXT, "SSC CGL Tier-1 2026", "Direct PDF · 18.4 MB", "RESULT OUT", "2m"),
        ("clock", AMBER, AMBER_TEXT, "IBPS PO Prelims 2026", "4 mirrors live · no queue", "CARD LIVE", "18m"),
        ("radar", RED, RED_TEXT, "RRB NTPC 2026", "Application closes 11:59 PM", "CLOSING", "1h"),
    ]
    for i, (ic, color, tc, title, sub, status, t) in enumerate(rows):
        ry = feed_top + i * 59.5
        if i:
            line(29, ry, 364, ry, "#FFFFFF", 1, 0.05)
        rect(29, ry + 12.5, 34, 34, color, rx=11, opacity=0.11)
        rect(29, ry + 12.5, 34, 34, "none", rx=11, stroke=color, sw=1, opacity=0.22)
        icon(ic, 38, ry + 21.5, 16, tc)
        txt(74, ry + 24, title, 11.5, "#E9EDF4", 600)
        txt(74, ry + 38, sub, 9.5, "#76859B", 400)
        pill(364, ry + 12, 19, status, color, tc, anchor="end")
        txt(364, ry + 45, t, 8, "#8B98AC", 400, mono=True, ls=0.6, anchor="end")

    # tab bar — shipped tabs are Home / Vault / Radar / Share (EvTab in
    # root_shell.dart); "Groups" was never built.
    tb = 770
    rect(16, tb, 361, 58, SURF, rx=19, stroke=BORDER2, sw=1, opacity=1, shadow="cardShadow")
    tabs = [("home", "Home", True, False), ("lock", "Vault", False, False),
            ("radar", "Radar", False, True), ("share", "Share", False, False)]
    for i, (ic, label, active, dot) in enumerate(tabs):
        tx = 21 + i * 88.5
        if active:
            rect(tx, tb + 5, 80, 48, BLUE, rx=14, opacity=0.13)
        icon(ic, tx + 31, tb + 13, 18, BLUE_TEXT if active else "#68778E")
        txt(tx + 40, tb + 43, label, 8, BLUE_TEXT if active else "#68778E", 600, anchor="middle")
        if dot:
            circle(tx + 52, tb + 12, 2.5, RED)
    home_indicator()
    g.append("".join(out)); out.clear(); out.extend(saved)
    g.append("</g></g>")
    return "".join(g)


# ============================ FRAME 2 =====================================
def frame2():
    saved = out.copy(); out.clear()
    rect(0, 0, W, H, BG)
    bg_layer()
    statusbar()

    icon_button(16, 52, "back", 36, 11, None, 0, "#C7D0DD", 17)
    txt(196, 68, "Saved Pass", 13.5, "#E8EDF4", 600, anchor="middle")
    for _i in range(3):
        _on = _i == 0
        rect(186.5 + _i * 10, 80, 6 if _on else 4, 4, BLUE if _on else "#4B5563",
             rx=2, opacity=1 if _on else 0.8)
    icon_button(341, 52, "share", 36, 11, None, 0, "#C7D0DD", 17)

    # boarding pass — a physical pass, stays dark in both themes
    CTX["on_navy"] += 1
    py = 104
    ph = 296
    rect(16, py, 361, 296, "url(#passCard)", rx=20, stroke=WALLET_BORDER, sw=1, shadow="cardShadow")
    rect(36, py + 1, 321, 1, "#FFFFFF", opacity=0.15)
    txt(34, py + 24, "SSC · CGL TIER-1 2026", 9, BLUE_TEXT, 600, mono=True, ls=1.6)
    txt(34, py + 40, "Staff Selection Commission", 10.5, "#8291A7", 500)
    pill(344, py + 15, 21, "SAVED", GREEN, GREEN_TEXT, anchor="end")

    txt(34, py + 70, "ROLL NUMBER", 8.5, TXT3, 500, mono=True, ls=1.25)
    txt(34, py + 98, "2201049821", 31, "#FFFFFF", 500, mono=True, ls=1.6)
    rect(306, py + 78, 34, 34, BLUE, rx=10, opacity=0.13)
    rect(306, py + 78, 34, 34, "none", rx=10, stroke=BLUE, sw=1, opacity=0.3)
    icon("copy", 315, py + 87, 15, BLUE_TEXT)

    line(16, py + 126, 377, py + 126, "#FFFFFF", 1, 0.16, dash="4 4")
    _page = DARK["bg"] if THEME["name"] == "dark" else LIGHT["bg"]
    circle(16, py + 126, 8, _page)
    circle(377, py + 126, 8, _page)

    fields = [
        ("REGISTRATION ID", "SSC-CGL-26-884213", 34, py + 152),
        ("DOB / PORTAL PASSWORD", "14/03/1999", 206, py + 152),
        ("EXAM CENTER CODE", "DL-04-1187", 34, py + 200),
        ("EXAM DATE", "20/11/2026", 206, py + 200),
    ]
    for label, value, x, y in fields:
        txt(x, y, label, 8.5, TXT3, 500, mono=True, ls=1.25)
        txt(x, y + 17, value, 11.5, "#E7ECF3", 500, mono=True, ls=0.2)
        icon("copy", x + (128 if x == 34 else 92), y + 12, 12, "#5F7089")

    # barcode
    bx = 34
    for i in range(38):
        bw = 1 if i % 3 else 2
        rect(bx, py + 242, bw, 22, "#DDE3EC", opacity=0.55)
        bx += bw + 2
    txt(360, py + 253, "SAVED OFFLINE · 2:14 PM", 7.5, "#8B98AC", 400, mono=True, ls=0.9, anchor="end")

    CTX["on_navy"] -= 1

    # countdown
    cy = py + ph + 12
    rect(16, cy, 361, 72, SURF, rx=16, stroke=BORDER, sw=1)
    txt(31, cy + 27, "EXAM COUNTDOWN", 8.5, TXT3, 500, mono=True, ls=1.25)
    txt(31, cy + 43, "Report by 8:15 AM", 9.5, "#8B98AC", 500)
    units = [("12", "DAYS"), ("04", "HRS"), ("32", "MIN")]
    for i, (num, lab) in enumerate(units):
        ux = 208 + i * 48
        rect(ux, cy + 15, 36, 42, BG, rx=9, stroke="#222E41", sw=1)
        txt(ux + 18, cy + 30, num, 15, "#E9EEF6", 600, mono=True, anchor="middle")
        txt(ux + 18, cy + 45, lab, 6, "#5E6C81", 400, mono=True, anchor="middle", ls=0.8)
        if i < 2:
            txt(ux + 42, cy + 33, ":", 13, "#39465A", 400, mono=True, anchor="middle")

    # checklist
    ky = cy + 86
    rect(16, ky, 361, 158, SURF, rx=18, stroke=BORDER, sw=1)
    txt(31, ky + 21, "DOCUMENT CHECKLIST", 9, TXT3, 500, mono=True, ls=1.6)
    txt(362, ky + 21, "3 / 3 READY", 8, "#34D399", 600, mono=True, ls=1.1, anchor="end")
    items = [("Admit Card PDF saved", "18.4 MB · offline"),
             ("2 Passport photos", "Recent · 50×50 mm"),
             ("Original Aadhaar ID", "Carry physical copy")]
    for i, (title, sub) in enumerate(items):
        ry = ky + 34 + i * 42
        if i:
            line(31, ry - 7, 362, ry - 7, "#FFFFFF", 1, 0.05)
        rect(31, ry + 1, 22, 22, GREEN, rx=7, opacity=0.13)
        rect(31, ry + 1, 22, 22, "none", rx=7, stroke=GREEN, sw=1, opacity=0.36)
        icon("check", 36, ry + 6, 12, "#34D399", sw=2.1)
        txt(64, ry + 8, title, 11.5, "#E4E9F1", 600)
        txt(64, ry + 21, sub, 9, "#94A2B8", 400)
        txt(362, ry + 12, "DONE", 7.5, "#34D399", 600, mono=True, ls=1.1, anchor="end")

    # centre card
    ey = ky + 170
    rect(16, ey, 361, 58, SURF, rx=15, stroke=BORDER, sw=1)
    rect(28, ey + 13, 32, 32, BLUE, rx=10, opacity=0.11)
    rect(28, ey + 13, 32, 32, "none", rx=10, stroke=BLUE, sw=1, opacity=0.25)
    icon("pin", 36, ey + 21, 16, BLUE_TEXT)
    txt(70, ey + 18, "EXAM CENTER · DL-04-1187", 7, "#66758B", 500, mono=True, ls=1.1)
    txt(70, ey + 30, "Sector 12, Dwarka, New Delhi", 10.5, "#E4E9F1", 600)
    txt(70, ey + 42, "Gate 3 · report by 8:15 AM", 8.5, "#94A2B8", 400)
    txt(342, ey + 29, "MAP", 7.5, BLUE_TEXT, 600, mono=True, ls=0.9, anchor="end")
    icon("external", 346, ey + 24, 10, BLUE_TEXT)

    # dock
    rect(0, 745, 393, 107, BG, opacity=1)
    rect(16, 757, 300, 52, "url(#btnBlue)", rx=14, shadow="cardShadow")
    icon("download", 120, 774, 17, "#FFFFFF")
    txt(143, 783.5, "Open Admit Card", 12.5, "#FFFFFF", 700)
    rect(325, 757, 52, 52, SURF, rx=14, stroke=BORDER2, sw=1, opacity=0.75)
    icon("share", 342, 774, 18, "#B9C4D4")
    icon("lock", 120, 816, 9, "#34D399")
    txt(130, 820, "TAP ANY FIELD TO COPY · AES-256 · OFFLINE", 8, "#8B98AC", 400, mono=True, ls=0.55)
    home_indicator()

    g = [f'<g id="02-vault-{THEME["name"]}" transform="translate({(W + GAP)} {THEME['row_y']})"><g clip-path="url(#frameClip1{SFX()})">']
    g.append("".join(out)); out.clear(); out.extend(saved)
    g.append("</g></g>")
    return "".join(g)


# ============================ FRAME 3 =====================================
def frame3():
    saved = out.copy(); out.clear()
    rect(0, 0, W, H, BG)
    bg_layer()
    statusbar()

    icon_button(16, 52, "back", 36, 11, None, 0, "#C7D0DD", 17)
    txt(196, 72, "Result Radar", 13.5, "#E8EDF4", 600, anchor="middle")
    rect(321, 60, 56, 24, GREEN, rx=12, opacity=0.1)
    rect(321, 60, 56, 24, "none", rx=12, stroke=GREEN, sw=1, opacity=0.28)
    circle(332, 72, 2.5, GREEN)
    txt(340, 72.5, "LIVE", 8, GREEN_TEXT, 600, mono=True, ls=1.2)

    txt(16, 106, "UPSC · CIVIL SERVICES", 9, "#7C8AA3", 400, mono=True, ls=1.7)
    _title = "UPSC CSE Prelims 2026 Result"
    _laid, _tot, _g = _word_layout(_title, 22, 700, False, -0.2)
    for _w, _wx in _laid:
        txt(16 + _wx, 132, _w, 22, GREEN if _w == "Result" else TXT, 700, ls=-0.2)
    txt(16, 156, "RELEASED 09:12 IST · 08 NOV 2026", 9.5, TXT2, 400, mono=True, ls=0.55)

    # mirror card
    my = 174
    rect(16, my, 361, 154, SURF, rx=18, stroke=BORDER, sw=1)
    txt(30, my + 21, "MIRROR STATUS", 9, TXT3, 500, mono=True, ls=1.6)
    circle(258, my + 21, 2, GREEN)
    txt(266, my + 21, "AUTO-REFRESH 30s", 7.5, GREEN_TEXT, 400, mono=True, ls=0.9)
    rows = [
        ("Server 1", "upsc.gov.in", 0.74, AMBER, "BUSY", "1,204ms"),
        ("Direct PDF Mirror", "", 0.22, GREEN, "FAST", "82ms"),
        ("Vault Cache", "instant", 0.08, BLUE, "READY", "4ms"),
    ]
    for i, (name, sub, pct, color, state, ms) in enumerate(rows):
        ry = my + 34 + i * 44
        if i:
            line(30, ry, 363, ry, "#FFFFFF", 1, 0.05)
        nw = tw(name, 11, 600)
        txt(30, ry + 22, name, 11, "#DDE4EE", 600)
        if sub:
            txt(30 + nw + 5, ry + 22, "·", 9.5, "#5B697E", 400)
            txt(30 + nw + 13, ry + 22, sub, 9.5, "#8494AB", 400)
        rect(214, ry + 20, 52, 4, "#1C2739", rx=2)
        rect(214, ry + 20, max(4, 52 * pct), 4, color, rx=2)
        txt(325, ry + 22, state, 7.5, color, 600, mono=True, ls=0.7, anchor="end")
        txt(363, ry + 22, ms, 8, "#8B98AC", 400, mono=True, anchor="end")

    icon("spark", 18, my + 174, 10, "#4E5D73")
    txt(32, my + 179, "Server checked 4s ago · retrying automatically", 8, "#8B98AC", 400, mono=True, ls=0.4)

    # download — the fast mirror is the recommended route, so it gets the primary
    # button. Sending users to "Official" while labelling it BUSY was the single
    # biggest contradiction on this screen.
    by = my + 190
    rect(16, by, 361, 52, "url(#btnBlue)", rx=14, shadow="cardShadow")
    icon("download", 38, by + 17, 17, "#FFFFFF")
    txt(62, by + 27, "Download via fast mirror", 12.5, "#FFFFFF", 700)
    rect(300, by + 14, 63, 24, "#000000", rx=6, opacity=0.18)
    txt(331.5, by + 26.5, "82ms", 9.5, "#FFFFFF", 500, mono=True, anchor="middle", ls=0.3)

    rect(16, by + 60, 176, 44, SURF, rx=12, stroke=BORDER2, sw=1, opacity=0.7)
    icon("external", 52, by + 75, 14, "#8FA0B8")
    txt(72, by + 82.5, "Official site", 10.5, "#C7D0DD", 600)
    txt(182, by + 82.5, "BUSY", 7.5, AMBER, 600, mono=True, anchor="end", ls=0.5)
    rect(200, by + 60, 177, 44, SURF, rx=12, stroke=BORDER2, sw=1, opacity=0.7)
    icon("link", 248, by + 75, 14, "#8FA0B8")
    txt(268, by + 82.5, "Copy direct link", 10.5, "#C7D0DD", 600)

    # search
    sy = by + 126
    txt(16, sy, "FIND MY ROLL NUMBER", 9, TXT3, 500, mono=True, ls=1.6)
    txt(377, sy, "In PDF", 9.5, "#7F8DA3", 600, anchor="end")
    rect(16, sy + 12, 361, 52, SURF2, rx=14, stroke="#283650", sw=1)
    icon("search", 29, sy + 30, 17, "#718199")
    _q = "0812045678"
    txt(55, sy + 38.5, _q, 14, "#F1F5FA", 500, mono=True, ls=1.2)
    rect(55 + tw(_q, 14, 500, mono=True, ls=1.2) + 3, sy + 29, 1.5, 18, BLUE_BRIGHT)
    # clear affordance — the field had no way back to an empty state
    circle(262, sy + 38, 9, "#243044")
    icon("x", 258, sy + 34, 8, "#C7D0DD", sw=2.6)
    rect(280, sy + 19, 76, 38, "url(#pillBlue)", rx=10)
    txt(318, sy + 38.5, "Find", 10.5, "#FFFFFF", 700, anchor="middle")

    rect(16, sy + 72, 361, 54, GREEN, rx=12, opacity=0.07)
    rect(16, sy + 72, 361, 54, "none", rx=12, stroke=GREEN, sw=1, opacity=0.22)
    rect(27, sy + 86, 26, 26, GREEN, rx=8, opacity=0.15)
    rect(27, sy + 86, 26, 26, "none", rx=8, stroke=GREEN, sw=1, opacity=0.3)
    icon("check", 33, sy + 92, 13, "#34D399", sw=2.1)
    txt(63, sy + 93, "Roll number found", 11, "#DDF5EA", 600)
    txt(63, sy + 106, "Page 14 · 1 of 12,480 rows", 8, "#94A2B8", 400, mono=True)
    txt(336, sy + 100, "JUMP TO ROW", 9, "#34D399", 600, mono=True, ls=0.7, anchor="end")
    icon("chev", 352, sy + 95, 10, "#34D399")

    # recent
    ry2 = sy + 146
    txt(16, ry2, "RECENT CHECKS", 9, TXT3, 500, mono=True, ls=1.6)
    txt(377, ry2, "Manage", 9.5, "#7F8DA3", 600, anchor="end")
    rect(16, ry2 + 12, 361, 101, SURF, rx=16, stroke=BORDER, sw=1)
    recs = [("SSC CGL Tier-1 2025", "Checked 12 Mar 2026", "FOUND", GREEN, GREEN_TEXT),
            ("UPSC CSE Mains 2025", "Checked 04 Jan 2026", "AWAITED", AMBER, AMBER_TEXT)]
    for i, (title, sub, state, color, tc) in enumerate(recs):
        y = ry2 + 12 + i * 50
        if i:
            line(16, y, 377, y, "#FFFFFF", 1, 0.05)
        txt(28, y + 20, title, 11, "#E3E9F1", 600)
        txt(28, y + 32, sub, 8, "#93A1B5", 400, mono=True)
        pill(347, y + 16, 18, state, color, tc, dot=False, size=8, ls=0.5, anchor="end")
        icon("chev", 352, y + 22, 12, "#4F5D72")
    home_indicator()

    g = [f'<g id="03-radar-{THEME["name"]}" transform="translate({((W + GAP) * 2)} {THEME['row_y']})"><g clip-path="url(#frameClip2{SFX()})">']
    g.append("".join(out)); out.clear(); out.extend(saved)
    g.append("</g></g>")
    return "".join(g)


# ============================ FRAME 4 =====================================
def frame4():
    saved = out.copy(); out.clear()
    rect(0, 0, W, H, BG)
    bg_layer()
    statusbar()

    icon_button(16, 52, "x", 36, 11, None, 0, "#C7D0DD", 17)
    txt(196, 72, "Share Card", 13.5, "#E8EDF4", 600, anchor="middle")
    rect(316, 60, 61, 24, "#FFFFFF", rx=12, opacity=0.03)
    rect(316, 60, 61, 24, "none", rx=12, stroke=BORDER, sw=1)
    txt(346.5, 72.5, "PREVIEW", 8, "#7C8AA3", 600, mono=True, anchor="middle", ls=1.2)

    # share card — height 284 since the invented cut-off grid was removed
    # (the shipped card only renders cut-offs when a publisher actually
    # released them; these numbers were fiction).
    cx, cy, cw = 24, 100, 345
    rect(cx, cy, cw, 284, ALABASTER, rx=20, shadow="cardShadow")
    rect(cx, cy, cw, 38, "url(#alertRed)", rx=20)
    rect(cx, cy + 20, cw, 18, "url(#alertRed)")
    icon("bell", cx + 15, cy + 12, 13, "#FFFFFF")
    txt(cx + 32, cy + 19.5, "RESULT IS LIVE", 9.5, "#FFFFFF", 800, ls=1.3)
    txt(cx + cw - 17, cy + 19.5, "08 NOV 2026", 8, "#FFFFFF", 500, mono=True, ls=0.9, anchor="end", opacity=0.86)

    rect(cx + 18, cy + 53, 17, 17, "url(#markBlue)", rx=5)
    icon("vault", cx + 21, cy + 56, 10, "#FFFFFF", sw=1.6)
    txt(cx + 41, cy + 61, "EXAMVAULT", 8.5, "#64748B", 600, mono=True, ls=1.9)
    # The app's real CTA line (share_infographic.dart). The project owns no
    # domain, so the card never prints a URL; the fictional host that used to
    # sit here was never registered by anyone.
    txt(cx + cw - 18, cy + 61, "Ask in your study group", 8, "#64748B", 400, mono=True, ls=0.3, anchor="end")

    txt(cx + 18, cy + 92, "SSC CGL · TIER-1 2026", 8.5, "#2563EB", 600, mono=True, ls=1.5)
    txt(cx + 18, cy + 124, "RESULT", 39, "#0B0F19", 800, ls=-1.9)
    _is = "IS "
    _isw = tw(_is, 39, 800, ls=-1.9)
    txt(cx + 18, cy + 161, _is, 39, "#0B0F19", 800, ls=-1.9)
    _live = "LIVE"
    _lw = tw(_live, 39, 800, ls=-1.9)
    live_x = cx + 18 + _isw
    rect(live_x, cy + 148, _lw, 14, BLUE, opacity=0.24)
    rect(live_x, cy + 159, _lw, 3, BLUE, opacity=0.9)
    txt(live_x, cy + 161, _live, 39, "#0B0F19", 800, ls=-1.9)
    # Real subline for a published result (whatsapp_share_card_screen.dart).
    txt(cx + 18, cy + 186, "Official link & instant roll-number check", 11, "#475569", 600)

    # The invented CUT-OFF grid (UR 152.5 / OBC 149.0 / SC 141.0 / ST 138.5)
    # was removed — the app never fabricates cut-offs. CTA moves up to where
    # the grid used to be.
    ry = cy + 200
    rect(cx + 18, ry, 309, 40, BLUE, rx=10)
    txt(cx + 31, ry + 20, "Check your roll no.", 11, "#FFFFFF", 700)
    txt(cx + 314, ry + 20, "→", 15, "#FFFFFF", 500, anchor="end")

    # Real footer (share_infographic.dart): always-true claims only.
    txt(cx + 172.5, ry + 57, "FREE · NO ACCOUNT · CHECKED ON YOUR DEVICE", 8, "#64748B", 500, mono=True, anchor="middle", ls=0.7)

    # targets
    ty = cy + 390
    targets = [("WhatsApp", "whatsapp", GREEN, "#25D366", True),
               ("Telegram", "send", BLUE, "#54A9EB", False),
               ("Copy link", "link", TXT3, "#AEB9C9", False),
               ("Save", "save", TXT3, "#AEB9C9", False)]
    for i, (label, ic, color, fg, hot) in enumerate(targets):
        x = 16 + i * 92
        rect(x + 13, ty + 2, 46, 46, SURF if not hot else color, rx=16,
             opacity=0.11 if hot else 1)
        rect(x + 13, ty + 2, 46, 46, "none", rx=16,
             stroke=color if hot else BORDER, sw=1, opacity=0.32 if hot else 1)
        if ic == "whatsapp":
            wa_icon(x + 26, ty + 15, 20, fg, hole="#121A26")
        else:
            icon(ic, x + 26, ty + 15, 20, fg)
        txt(x + 36, ty + 60, label, 8.5, "#D8E4F4" if hot else "#8494AB", 600, anchor="middle")

    # group row
    gy = ty + 74
    rect(16, gy, 361, 50, SURF, rx=13, stroke=BORDER, sw=1)
    rect(28, gy + 11, 28, 28, GREEN, rx=9, opacity=0.1)
    rect(28, gy + 11, 28, 28, "none", rx=9, stroke=GREEN, sw=1, opacity=0.26)
    wa_icon(34, gy + 17, 15, "#25D366", hole="#111827")
    txt(68, gy + 20, "SSC CGL 2026 Warriors", 11, "#E3E9F1", 600)
    txt(68, gy + 33, "248 members · WhatsApp group", 8.5, "#8B98AC", 400)
    txt(365, gy + 26, "CHANGE", 7.5, "#7C8AA3", 600, mono=True, ls=1, anchor="end")

    # caption preview — sending a card blind into a 248-person group is a trust risk
    ky = gy + 62
    rect(16, ky, 361, 48, SURF, rx=12, stroke=BORDER, sw=1)
    txt(30, ky + 16, "MESSAGE CAPTION", 8, TXT3, 500, mono=True, ls=1.2)
    # caption echoes the real format: "🚨 <EXAM> <HEADLINE> — <subline>."
    # (whatsapp_share_card_screen.dart); shortened here to fit the mock row.
    # The old "cut-off & PDF inside" claimed data the app never fabricates.
    txt(30, ky + 32, "SSC CGL 2026 RESULT IS LIVE — official link & roll check", 9.5, "#C7D0DD", 500)
    txt(365, ky + 24, "EDIT", 8, BLUE_TEXT, 600, mono=True, ls=0.9, anchor="end")

    # green cta
    wy = ky + 56
    rect(16, wy, 361, 52, "url(#btnGreen)", rx=14)
    wa_icon(112, wy + 17, 18, "#05130B", hole="#1FBE63")
    txt(136, wy + 27, "Share to study group", 12.5, "#05130B", 700)

    # attach
    ay = wy + 62
    rect(16, ay, 361, 56, SURF, rx=14, stroke=BORDER, sw=1)
    txt(30, ay + 22, "Attach PDF to message", 11.5, "#E4E9F1", 600)
    txt(30, ay + 36, "Off = a direct link is sent instead", 9, "#8B98AC", 400)
    rect(325, ay + 17, 38, 22, GREEN, rx=11, opacity=0.9)
    circle(348, ay + 28, 8, "#FFFFFF")
    txt(196, ay + 66, "Card re-shares automatically when the result updates", 8, "#8B98AC", 400, mono=True, anchor="middle", ls=0.4)
    home_indicator()

    g = [f'<g id="04-share-{THEME["name"]}" transform="translate({((W + GAP) * 3)} {THEME['row_y']})"><g clip-path="url(#frameClip3{SFX()})">']
    g.append("".join(out)); out.clear(); out.extend(saved)
    g.append("</g></g>")
    return "".join(g)


ROW_GAP = 96


def build_theme(name):
    """Render the four frames for one theme and return (body, defs)."""
    global out, defs
    set_theme(name)
    out = []
    defs = []
    build_defs()
    body = frame1() + frame2() + frame3() + frame4()
    # balance: the pass / share cards keep a 1px edge on a light page
    return body, list(defs)


def emit():
    global out, defs
    THEME["row_y"] = 0
    dark_body, dark_defs = build_theme("dark")
    THEME["row_y"] = H + ROW_GAP
    light_body, light_defs = build_theme("light")
    THEME["row_y"] = 0

    board_h = H * 2 + ROW_GAP

    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{BOARD_W}" height="{board_h}" '
           f'viewBox="0 0 {BOARD_W} {board_h}">']
    svg.append("<defs>")
    svg.extend(dark_defs)
    svg.extend(light_defs)
    svg.append("</defs>")

    # page + row labels
    svg.append(f'<rect width="{BOARD_W}" height="{board_h}" fill="#05070C"/>')
    svg.append(dark_body)
    svg.append(light_body)
    svg.append("</svg>")

    return "".join(svg), board_h


svg, board_h = emit()

path = "/root/ExamVault/design/exports/examvault-sheet.svg"
with open(path, "w") as f:
    f.write(svg)
print(f"wrote {path} ({len(svg)/1024:.0f} KB, board {BOARD_W}x{board_h})")
