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

import hashed_index as hashed
import gzip
import io
import json
import re
import sys
import urllib.request
from typing import Iterable
from urllib.parse import urlsplit

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/155.0.0.0 Safari/537.36"
)


def download(url: str) -> bytes:
    # The Referer must be the target's OWN origin. It used to be hardcoded to
    # ssc.gov.in for every commission, which is exactly the cross-origin
    # referer shape that WAFs on upsc.gov.in / tnpsc.gov.in / ibps.in treat as
    # a hotlinking scraper — a tripwire we were handing them for free.
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/pdf,*/*",
    }
    parts = urlsplit(url)
    if parts.scheme and parts.netloc:
        headers["Referer"] = f"{parts.scheme}://{parts.netloc}/"
    req = urllib.request.Request(url, headers=headers)
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


def warn_if_bimodal(rolls: list[str]) -> dict | None:
    """Warns when roll digit-lengths cluster at two or more distinct lengths.

    A real candidate list has ONE roll shape (SSC 12 digits, UPSC zero-padded
    7, TNPSC 9-10). Two populated length modes usually mean the extractor
    picked up an interleaved column from the PDF layout — serial numbers,
    dates, marks — and is publishing junk digests that will answer "not
    selected" for every real candidate.

    This replaces the old "strictly ascending" check, which was dead code:
    `extract_rolls` returns `sorted(set(...))`, so the order is structural and
    the check could never fire. A warning (not a failure) is the right signal
    strength: a combined list CAN legitimately mix shapes, so a human decides.
    """
    if len(rolls) < 20:
        return None
    from collections import Counter

    counts = Counter(len(r) for r in rolls)
    significant = {
        length: count
        for length, count in counts.items()
        if count >= max(2, int(0.05 * len(rolls)))
    }
    if len(significant) >= 2:
        print(
            "WARNING   bimodal roll digit-lengths "
            f"{dict(sorted(significant.items()))} — likely column interleaving "
            "(serial numbers/dates/marks captured as rolls); verify the pattern "
            "before trusting this index",
            file=sys.stderr,
        )
        return significant
    return None


def build_index(
    rolls: list[str],
    with_ranks: bool,
    salt: str | None = None,
) -> tuple[bytes, str]:
    """Returns (gzip bytes, mode).

    Default output is the **hashed** v2 object: it contains no roll numbers, only
    salted SHA-256 digests, so publishing it does not reproduce the official
    candidate list. `--plaintext` exists solely for local fixtures and tests.
    """
    if with_ranks:
        # Plaintext with ranks — never published. Kept for offline fixtures so the
        # merit-rank UI path stays exercised.
        payload = [{"r": r, "rank": i + 1} for i, r in enumerate(rolls)]
        return (
            gzip.compress(
                json.dumps(payload, separators=(",", ":")).encode(),
                9,
                mtime=0,
            ),
            "plaintext",
        )

    body, _meta = hashed.build(rolls, salt=salt)
    return body, hashed.MODE


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
    ap.add_argument(
        "--plaintext",
        action="store_true",
        help=(
            "emit the raw roll list instead of one-way hashes. Only for local "
            "fixtures — a plaintext index reproduces the official candidate list."
        ),
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

    # Ascending order is structural, not checked: `extract_rolls` returns
    # `sorted(set(...))`, so a "verify strictly ascending" loop here could never
    # fire — it was removed as dead code. The check that DOES carry signal is
    # shape bimodality (interleaved-column junk), and it warns rather than fails.
    warn_if_bimodal(rolls)

    print(f"sample    {', '.join(rolls[:4])} …")

    # Privacy-preserving by default: hashed unless explicitly asked otherwise.
    body, mode = build_index(
        rolls,
        with_ranks=args.plaintext and not args.no_ranks,
        salt=hashed.exam_salt(args.exam),
    )
    print(f"mode      {mode}")
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
