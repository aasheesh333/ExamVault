#!/usr/bin/env python3
"""Builds and publishes roll-number indexes for every result in the feed.

Why this exists: `fetch_official_feeds.mjs` produces the radar, and
`extract_rolls.py` turns one PDF into one index. Nothing connected them — so the
app could show "SSC SI 2025 RESULT OUT" and then have no index to search, which is
exactly the case that used to fall back to a fabricated one.

This script closes the loop:

    live_feed.json  ──▶  for each result_out row with a PDF
                              │
                              ├─ download the official PDF
                              ├─ extract roll numbers
                              ├─ verify sorted + non-trivial
                              └─ publish v1/rolls/<exam_id>_rolls.json.gz

The exam id written here is **the same id** used in the feed row, so the app's
existing `AppConfig.rollIndexPath(examId)` resolves without any mapping table.

    python3 build_indexes.py --feed ../data/live_feed.json [--limit 3] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from extract_rolls import build_index, download, extract_rolls, read_pdf_text  # noqa: E402
import re  # noqa: E402

BUCKET = "examvault-cdn"
# Only statuses that actually publish a roll list.
INDEXABLE = {"result_out"}


def publish(local_path: Path, key: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  dry-run       would publish {key}")
        return
    subprocess.run(
        [
            "npx", "--yes", "wrangler@4", "r2", "object", "put",
            f"{BUCKET}/{key}",
            f"--file={local_path}",
            "--content-type=application/gzip",
            "--remote",
        ],
        check=True,
        capture_output=True,
    )
    print(f"  published     {key}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--feed", required=True)
    ap.add_argument("--limit", type=int, default=5, help="max indexes to build")
    ap.add_argument("--pattern", default=r"\b\d{9,14}\b")
    ap.add_argument(
        "--min-rolls",
        type=int,
        default=100,
        help=(
            "floor for a believable candidate list. A 'writeup' PDF contains a "
            "handful of representative rolls; publishing that as an index would "
            "tell every other candidate they were not selected."
        ),
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    feed = json.loads(Path(args.feed).read_text())
    # Only PDFs under masterData/Results are candidate lists. Notice-board and
    # "writeup" documents describe a result; they do not enumerate it.
    rows = [
        r
        for r in feed.get("updates", [])
        if r.get("status") in INDEXABLE
        and r.get("official_pdf")
        and "/Results/" in r["official_pdf"]
        and re.search(r"(list of candidates|merit list|roll number order)", r.get("exam_name", ""), re.I)
    ]

    print(f"candidates    {len(rows)} result rows with a PDF")

    pattern = re.compile(args.pattern)
    built = 0

    for row in rows[: args.limit]:
        exam_id = row["exam_id"]
        url = row["official_pdf"]
        print(f"\n{exam_id}")
        print(f"  pdf           {url}")

        try:
            pdf = download(url)
            text = read_pdf_text(pdf)
            rolls = extract_rolls(text, pattern)
        except SystemExit as e:
            print(f"  skipped       {e}")
            continue
        except Exception as e:  # noqa: BLE001
            print(f"  skipped       {type(e).__name__}: {e}")
            continue

        print(f"  rolls         {len(rolls):,}")

        # A result PDF that yields almost nothing is almost always a scanned
        # image or a changed layout. Publishing it would tell every candidate
        # they were not selected, so it is skipped instead.
        if len(rolls) < args.min_rolls:
            print("  skipped       too few rolls (scanned image or new layout?)")
            continue

        for i in range(1, len(rolls)):
            if not rolls[i - 1] < rolls[i]:
                print(f"  skipped       not sorted at {i}")
                break
        else:
            body = build_index(rolls, with_ranks=True)
            print(f"  gzip          {len(body) / 1024:.1f} KB")

            with tempfile.NamedTemporaryFile(suffix=".json.gz", delete=False) as fh:
                fh.write(body)
                tmp = Path(fh.name)

            # Flag the row so the app can offer "Check my result" for it.
            row["index_available"] = True
            row["roll_count"] = len(rolls)

            publish(tmp, f"v1/rolls/{exam_id}_rolls.json.gz", args.dry_run)
            os.unlink(tmp)
            built += 1

    print(f"\nbuilt         {built} index(es)")

    if not args.dry_run and built:
        Path(args.feed).write_text(json.dumps(feed, indent=2))
        print(f"updated       {args.feed} (index_available flags)")

    return 0 if built or args.dry_run else 1


if __name__ == "__main__":
    sys.exit(main())
