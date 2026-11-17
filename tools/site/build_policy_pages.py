#!/usr/bin/env python3
"""Render the policy markdown in docs/ into self-contained HTML pages.

Why this exists: the Play Store listing needs a hosted privacy-policy URL, and the
two documents that must be reachable are maintained as markdown in the repo so
they can be reviewed in a pull request. This turns those markdown files into the
static HTML that gets uploaded, so the hosted copy can never drift from the
reviewed one — regenerate and re-upload instead of editing HTML by hand.

Deliberately dependency-free: no pandoc, no python-markdown, no network. The
markdown subset used by these documents is small, and handling it here keeps the
build reproducible on a machine with nothing installed.

Usage:
    python3 tools/site/build_policy_pages.py [--out DIR]
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS = REPO_ROOT / "docs"

# Palette lifted from the app's own theme tokens (theme_tokens.dart) so the hosted
# pages look like the product rather than a stray template.
PAGE_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>{title} · ExamVault</title>
<meta name="description" content="{description}">
<style>
  :root {{
    --bg: #f7f8fa;
    --surface: #ffffff;
    --text: #111827;
    --muted: #4b5563;
    --border: #e5e7eb;
    --accent: #2563eb;
    --accent-soft: #eff6ff;
    --code-bg: #f3f4f6;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #0b0f19;
      --surface: #111827;
      --text: #f9fafb;
      --muted: #9ca3af;
      --border: #1f2937;
      --accent: #60a5fa;
      --accent-soft: #16233a;
      --code-bg: #0e1522;
    }}
  }}
  * {{ box-sizing: border-box; }}
  html {{ -webkit-text-size-adjust: 100%; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
          "Helvetica Neue", Arial, sans-serif;
    padding: 0 16px 72px;
  }}
  .wrap {{ max-width: 720px; margin: 0 auto; }}
  header {{
    padding: 32px 0 20px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 32px;
  }}
  header a.brand {{
    display: inline-flex;
    align-items: center;
    gap: 10px;
    color: var(--text);
    text-decoration: none;
    font-weight: 700;
    letter-spacing: -0.01em;
  }}
  header .dot {{
    width: 10px; height: 10px; border-radius: 3px;
    background: var(--accent);
    display: inline-block;
  }}
  header nav {{ margin-top: 14px; font-size: 14px; }}
  header nav a {{
    color: var(--muted);
    text-decoration: none;
    margin-right: 18px;
    padding-bottom: 2px;
    border-bottom: 1px solid transparent;
  }}
  header nav a:hover {{ color: var(--accent); border-bottom-color: var(--accent); }}
  h1 {{
    font-size: 30px;
    line-height: 1.25;
    letter-spacing: -0.02em;
    margin: 0 0 8px;
  }}
  h2 {{
    font-size: 20px;
    letter-spacing: -0.01em;
    margin: 40px 0 12px;
    padding-top: 8px;
  }}
  h3 {{ font-size: 17px; margin: 28px 0 10px; }}
  p, li {{ color: var(--text); }}
  p {{ margin: 0 0 16px; }}
  ul, ol {{ margin: 0 0 16px; padding-left: 22px; }}
  li {{ margin: 6px 0; }}
  li > ul, li > ol {{ margin: 6px 0; }}
  a {{ color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 2px; }}
  strong {{ font-weight: 650; }}
  code {{
    background: var(--code-bg);
    border-radius: 4px;
    padding: 1px 5px;
    font-size: 0.9em;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  }}
  hr {{ border: 0; border-top: 1px solid var(--border); margin: 36px 0; }}
  .table-scroll {{ overflow-x: auto; margin: 0 0 20px; }}
  table {{
    border-collapse: collapse;
    width: 100%;
    font-size: 14.5px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    overflow: hidden;
  }}
  th, td {{
    text-align: left;
    padding: 10px 12px;
    border-bottom: 1px solid var(--border);
    vertical-align: top;
  }}
  th {{ background: var(--accent-soft); font-weight: 650; white-space: nowrap; }}
  tr:last-child td {{ border-bottom: 0; }}
  blockquote {{
    margin: 0 0 16px;
    padding: 2px 0 2px 14px;
    border-left: 3px solid var(--accent);
    color: var(--muted);
  }}
  footer {{
    margin-top: 56px;
    padding-top: 20px;
    border-top: 1px solid var(--border);
    font-size: 13.5px;
    color: var(--muted);
  }}
  footer a {{ color: var(--muted); }}
  @media (max-width: 520px) {{
    h1 {{ font-size: 25px; }}
    h2 {{ font-size: 18px; }}
    body {{ font-size: 15.5px; }}
  }}
</style>
</head>
<body>
<div class="wrap">
<header>
  <a class="brand" href="./index.html"><span class="dot"></span>ExamVault</a>
  <nav>
    <a href="./privacy.html">Privacy policy</a>
    <a href="./terms.html">Terms of use</a>
    <a href="https://github.com/aasheesh333/ExamVault">Source</a>
  </nav>
</header>
<main>
{body}
</main>
<footer>
  ExamVault is a free study utility for Indian competitive-exam aspirants.
  It is not affiliated with any examining body.
  Questions: <a href="https://github.com/aasheesh333/ExamVault/issues">open an issue</a>.
</footer>
</div>
</body>
</html>
"""


def inline(text: str) -> str:
    """Escape, then apply inline markdown. Order matters: code first so its
    contents are not then treated as emphasis or links."""
    placeholders: list[str] = []

    def stash(fragment: str) -> str:
        placeholders.append(fragment)
        return f"\x00{len(placeholders) - 1}\x00"

    # `code`
    text = re.sub(
        r"`([^`]+)`",
        lambda m: stash(f"<code>{html.escape(m.group(1))}</code>"),
        text,
    )
    # [label](url)
    text = re.sub(
        r"\[([^\]]+)\]\((https?://[^\s)]+)\)",
        lambda m: stash(
            f'<a href="{html.escape(m.group(2))}">{html.escape(m.group(1))}</a>'
        ),
        text,
    )
    # <https://autolink>
    text = re.sub(
        r"<(https?://[^\s>]+)>",
        lambda m: stash(
            f'<a href="{html.escape(m.group(1))}">{html.escape(m.group(1))}</a>'
        ),
        text,
    )

    text = html.escape(text)

    # **bold**, then *italic*
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)

    for i, fragment in enumerate(placeholders):
        text = text.replace(f"\x00{i}\x00", fragment)
    return text


def render_table(rows: list[str]) -> str:
    """First row is the header, second is the --- separator."""
    def cells(line: str) -> list[str]:
        line = line.strip().strip("|")
        return [c.strip() for c in line.split("|")]

    header = cells(rows[0])
    body = [cells(r) for r in rows[2:]]
    out = ["<div class=\"table-scroll\"><table>", "<thead><tr>"]
    out += [f"<th>{inline(c)}</th>" for c in header]
    out.append("</tr></thead><tbody>")
    for row in body:
        # Pad/trim so a malformed row cannot shift every later cell.
        row = (row + [""] * len(header))[: len(header)]
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def render(md: str) -> str:
    lines = md.splitlines()
    out: list[str] = []
    i = 0
    para: list[str] = []

    def flush_para() -> None:
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para.clear()

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            flush_para()
            i += 1
            continue

        # Table
        if stripped.startswith("|") and i + 1 < len(lines) and re.match(
            r"^\|[\s:|-]+\|$", lines[i + 1].strip()
        ):
            flush_para()
            block = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                block.append(lines[i])
                i += 1
            out.append(render_table(block))
            continue

        # Horizontal rule
        if re.fullmatch(r"(-{3,}|\*{3,}|_{3,})", stripped):
            flush_para()
            out.append("<hr>")
            i += 1
            continue

        # Headings
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            flush_para()
            level = len(m.group(1))
            out.append(f"<h{level}>{inline(m.group(2))}</h{level}>")
            i += 1
            continue

        # Blockquote
        if stripped.startswith(">"):
            flush_para()
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append(f"<blockquote><p>{inline(' '.join(quote))}</p></blockquote>")
            continue

        # Lists — collect the whole block, tracking indent for nesting
        if re.match(r"^([-*+]|\d+\.)\s+", stripped):
            flush_para()
            ordered = bool(re.match(r"^\d+\.\s+", stripped))
            items: list[tuple[int, str]] = []
            while i < len(lines):
                cur = lines[i]
                cs = cur.strip()
                if not cs:
                    # A blank line ends the list only if the next line is not a
                    # continuation; these documents use blank lines between lists.
                    if i + 1 < len(lines) and re.match(
                        r"^([-*+]|\d+\.)\s+", lines[i + 1].strip()
                    ):
                        i += 1
                        continue
                    break
                lm = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", cur)
                if lm:
                    indent = len(lm.group(1))
                    items.append((indent, lm.group(3)))
                    i += 1
                    continue
                # Continuation of the previous item
                if items and cur.startswith(" "):
                    indent, text = items[-1]
                    items[-1] = (indent, text + " " + cs)
                    i += 1
                    continue
                break

            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>")
            base: int | None = None
            open_sub = False
            for indent, text in items:
                if base is None:
                    base = indent
                if indent > base and not open_sub:
                    out.append(f"<{tag}>")
                    open_sub = True
                elif indent <= base and open_sub:
                    out.append(f"</{tag}>")
                    open_sub = False
                out.append(f"<li>{inline(text)}</li>")
            if open_sub:
                out.append(f"</{tag}>")
            out.append(f"</{tag}>")
            continue

        para.append(stripped)
        i += 1

    flush_para()
    return "\n".join(out)


PAGES = [
    (
        "PRIVACY.md",
        "privacy.html",
        "Privacy policy",
        "What ExamVault stores on your device, what leaves it, and what never does.",
    ),
    (
        "TERMS.md",
        "terms.html",
        "Terms of use",
        "The terms that cover your use of the ExamVault Android app.",
    ),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO_ROOT / "site"))
    args = ap.parse_args()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for md_name, html_name, title, description in PAGES:
        src = DOCS / md_name
        if not src.exists():
            print(f"missing {src}", file=sys.stderr)
            return 1
        body = render(src.read_text(encoding="utf-8"))
        page = PAGE_TEMPLATE.format(title=title, description=description, body=body)
        (out_dir / html_name).write_text(page, encoding="utf-8")
        print(f"wrote {out_dir / html_name} ({len(page)} bytes)")

    # A tiny landing page so the domain root is not a 404 — a Play reviewer
    # visiting the bare domain should not see an error page.
    index = PAGE_TEMPLATE.format(
        title="ExamVault policies",
        description="Privacy policy and terms of use for the ExamVault Android app.",
        body=(
            "<h1>ExamVault policies</h1>"
            "<p>ExamVault is a free study utility for Indian competitive-exam "
            "aspirants. It needs no account and keeps your admit cards, roll "
            "numbers and portal details encrypted on your own device.</p>"
            "<ul>"
            '<li><a href="./privacy.html">Privacy policy</a> — what is stored, '
            "what leaves your device, and what never does.</li>"
            '<li><a href="./terms.html">Terms of use</a> — the terms that cover '
            "your use of the app.</li>"
            "</ul>"
            "<p>The app itself is open source at "
            '<a href="https://github.com/aasheesh333/ExamVault">'
            "github.com/aasheesh333/ExamVault</a>.</p>"
        ),
    )
    (out_dir / "index.html").write_text(index, encoding="utf-8")
    print(f"wrote {out_dir / 'index.html'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
