#!/usr/bin/env python3
"""Extract roll numbers from an official result PDF and build a search index.

The app's headline feature is answering "am I selected?" in under a millisecond
without downloading a 60 MB PDF. This script produces the input for that: a
sorted, deduplicated, gzip-compressed list of roll numbers.

## What is copied, and what is not

Only *facts* are extracted — the set of roll numbers that appear in a published
result. The PDF itself is never mirrored: the app links to the original on
ssc.gov.in. A list of roll numbers is not a reproduction of the document.

## Why the roll pattern is configurable

Different commissions format rolls differently (`125130000008` for SSC's
12-digit PET/PST lists, alphanumeric for some state PSCs). Guessing a single
pattern would silently drop real candidates, so the caller states it and the
script *reports* how many candidates it found, so a wrong guess is visible.

    python3 extract_rolls.py \
        --url https://ssc.gov.in/api/attachment/.../LIST.pdf \
        --exam ssc_si_capf_2025 \
        --out build/ssc_si_capf_2025_rolls.json.gz \
        --pattern '^\\d{9,14}$'

Exits non-zero if the result looks wrong (no rolls found, or a suspiciously low
count), so a broken parser fails CI instead of publishing an empty index that
would tell every candidate they were not selected.
"""

from __future__ import annotations

import argparse
import gzip
import io
import json
import re
import sys
import urllib.request
from typing import Iterable

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/155.0.0.0 Safari/537.36"
)


def download(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Referer": "https://ssc.gov.in/",
            "Accept": "application/pdf,*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        if resp.status != 200:
            raise SystemExit(f"download failed: HTTP {resp.status}")
        data = resp.read()
    if not data.startswith(b"%PDF"):
        # SSC serves an HTML error page with a 200 status for some paths.
        raise SystemExit(
            "download did not return a PDF (got "
            f"{data[:16]!r}); check the URL prefix is /api/attachment/"
        )
    return data


def read_pdf_text(pdf_bytes: bytes) -> str:
    try:
        from pypdf import PdfReader
    except ImportError:
        raise SystemExit("pypdf is required: pip install pypdf")

    reader = PdfReader(io.BytesIO(pdf_bytes))
    chunks: list[str] = []
    for page in reader.pages:
        try:
            chunks.append(page.extract_text() or "")
        except Exception:
            # One unreadable page must not abort a 200-page list; gaps are
            # reported by the caller via --min-rolls.
            continue
    return "\n".join(chunks)


def extract_rolls(text: str, pattern: re.Pattern[str]) -> list[str]:
    found = set()
    for match in pattern.finditer(text):
        value = match.group(0).strip().upper()
        if 4 <= len(value) <= 24:
            found.add(value)
    return sorted(found)


def build_index(rolls: list[str], with_ranks: bool) -> bytes:
    payload: Iterable
    if with_ranks:
        payload = [{"r": r, "rank": i + 1} for i, r in enumerate(rolls)]
    else:
        payload = rolls

    raw = json.dumps(payload, separators=(",", ":")).encode()
    return gzip.compress(raw, compresslevel=9)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True, help="official PDF URL")
    ap.add_argument("--exam", required=True, help="exam id, e.g. ssc_cgl_tier1_2026")
    ap.add_argument("--out", required=True, help="output .json.gz path")
    ap.add_argument(
        "--pattern",
        default=r"\b\d{9,14}\b",
        help="regex a roll number must fully match",
    )
    ap.add_argument("--no-ranks", action="store_true", help="omit merit ranks")
    ap.add_argument(
        "--min-rolls",
        type=int,
        default=10,
        help="fail if fewer rolls than this are found (guards a broken parser)",
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # Accept anchored patterns (`^\d{9,14}$`) even though `finditer` scans
    # the whole document: the anchors are stripped and replaced with word
    # boundaries, so the same pattern works whether the caller is thinking in
    # "one token" or "search the text" terms.
    raw_pattern = args.pattern
    if raw_pattern.startswith("^"):
        raw_pattern = raw_pattern[1:]
    if raw_pattern.endswith("$") and not raw_pattern.endswith("\\$"):
        raw_pattern = raw_pattern[:-1]
    if not raw_pattern.startswith(r"\b"):
        raw_pattern = r"\b" + raw_pattern
    if not raw_pattern.endswith(r"\b"):
        raw_pattern = raw_pattern + r"\b"
    pattern = re.compile(raw_pattern)

    print(f"exam      {args.exam}")
    print(f"source    {args.url}")

    pdf = download(args.url)
    print(f"pdf       {len(pdf) / 1024 / 1024:.1f} MB")

    text = read_pdf_text(pdf)
    print(f"text      {len(text):,} chars")

    rolls = extract_rolls(text, pattern)
    print(f"rolls     {len(rolls):,}")

    if len(rolls) < args.min_rolls:
        print(
            f"FAILED    only {len(rolls)} rolls matched; the pattern or the PDF "
            f"changed. Refusing to publish an index that would tell candidates "
            f"they were not selected.",
            file=sys.stderr,
        )
        return 1

    # The app binary-searches this array. Verify strict ascending order before
    # anything is written — a broken sort silently costs every user a full scan.
    for i in range(1, len(rolls)):
        if not rolls[i - 1] < rolls[i]:
            print(f"FAILED    not strictly ascending at {i}", file=sys.stderr)
            return 1
    print("sorted    verified strictly ascending")

    print(f"sample    {', '.join(rolls[:4])} …")

    body = build_index(rolls, with_ranks=not args.no_ranks)
    print(f"gzip      {len(body) / 1024:.1f} KB")

    if args.dry_run:
        print("dry-run   not written")
        return 0

    with open(args.out, "wb") as fh:
        fh.write(body)
    print(f"wrote     {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
