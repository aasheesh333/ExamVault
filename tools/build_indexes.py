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
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import hashed_index  # noqa: E402
from extract_rolls import build_index, download, extract_rolls, read_pdf_text  # noqa: E402
import re  # noqa: E402

BUCKET = "examvault-cdn"


def _mark_skipped(row: dict, reason: str) -> None:
    """Records a failed extraction so the next run does not repeat it."""
    row["index_attempted_at"] = datetime.now(timezone.utc).isoformat()
    row["index_skipped"] = reason[:120]


def _parse_iso(value):
    if not value:
        return None
    from datetime import datetime, timezone

    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
# Only statuses that actually publish a roll list.
INDEXABLE = {"result_out"}

# Roll-number shape is per commission, and it is not guessable: SSC uses
# 12-digit rolls (`125160000498`), UPSC uses zero-padded 7-digit rolls
# (`0100823`), TNPSC uses 9-10 digit registration numbers. A single pattern
# silently drops real candidates — which is the worst failure this pipeline can
# have — so each source declares its own and the extractor prints the count it
# found so a wrong guess is visible rather than silent.
ROLL_PATTERNS = {
    "ssc": r"\b\d{9,14}\b",
    "upsc": r"\b\d{7}\b",
    "tnpsc": r"\b\d{9,14}\b",
    "ibps": r"\b\d{9,14}\b",
    "railways": r"\b\d{9,14}\b",
}
DEFAULT_ROLL_PATTERN = r"\b\d{9,14}\b"


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
    ap.add_argument(
        "--pattern",
        default=None,
        help="override the per-source roll pattern (debugging only)",
    )
    ap.add_argument(
        "--min-rolls",
        type=int,
        default=20,
        help=(
            "floor for a believable candidate list. A 'writeup' PDF contains a "
            "handful of representative rolls; publishing that as an index would "
            "tell every other candidate they were not selected. Twenty is enough "
            "to reject those while still indexing genuinely small final lists "
            "(a 30-post LDCE publishes 30 rolls)."
        ),
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    feed = json.loads(Path(args.feed).read_text())

    # Any `result_out` row that links a PDF is a candidate for indexing.
    #
    # An earlier version guessed from the URL ("/Results/", "RollList", …), but
    # every commission names files differently — UPSC ships
    # `FR-CombStenoGrB-I-LDCE-2020-Engl-06112026.pdf`, TNPSC uses
    # `/document/finalresult/`, SSC uses `/masterData/Results/`. Guessing missed
    # real lists and would have shipped a feed where only SSC was searchable.
    #
    # The protection is not the file name. It is `--min-rolls` plus the
    # strictly-ascending check below: a "writeup" PDF naming three illustrative
    # rolls produces three numbers and is rejected, so nobody is ever told they
    # were not selected on the strength of a document that never listed them.
    rows = [
        r
        for r in feed.get("updates", [])
        if r.get("status") in INDEXABLE and r.get("official_pdf")
    ]

    # Rows with no published index go first, so a small --limit still covers the
    # whole feed over a few runs instead of re-checking the same three rows
    # every 30 minutes. Rows that already failed are retried last and not more
    # than once a week: a PDF that yields three rolls today will yield three
    # rolls in half an hour, and burning the budget on it every run would starve
    # the lists that can actually be indexed.
    now = datetime.now(timezone.utc)

    def is_fresh_skip(row) -> bool:
        attempted = _parse_iso(row.get("index_attempted_at"))
        return bool(attempted) and (now - attempted).days < 7

    rows.sort(
        key=lambda r: (
            2 if is_fresh_skip(r) else (1 if r.get("index_available") else 0),
            -( _parse_iso(r.get("published_at")).timestamp()
               if _parse_iso(r.get("published_at")) else 0
            ),
        )
    )

    print(f"candidates    {len(rows)} result rows with a PDF")

    # `--pattern` overrides the per-source registry (used for one-off debugging).
    pattern_override = args.pattern
    built = 0

    for row in rows[: args.limit]:
        exam_id = row["exam_id"]
        url = row["official_pdf"]
        print(f"\n{exam_id}")
        print(f"  pdf           {url}")

        pattern = re.compile(
            pattern_override or ROLL_PATTERNS.get(row.get("source_id") or "", DEFAULT_ROLL_PATTERN)
        )
        try:
            pdf = download(url)
            text = read_pdf_text(pdf)
            rolls = extract_rolls(text, pattern)
        except SystemExit as e:
            print(f"  skipped       {e}")
            _mark_skipped(row, str(e))
            continue
        except Exception as e:  # noqa: BLE001
            print(f"  skipped       {type(e).__name__}: {e}")
            _mark_skipped(row, f"{type(e).__name__}: {e}")
            continue

        print(f"  pattern       {pattern.pattern}")
        print(f"  rolls         {len(rolls):,}")

        # A "writeup" is a prose summary that quotes a few representative roll
        # numbers; it never enumerates the candidates. Indexing one would answer
        # "not selected" for everybody it left out, which is worse than having no
        # index at all.
        if re.search(r"writeup|write[-_ ]?up", url, re.I):
            print("  skipped       writeup document, not a candidate list")
            _mark_skipped(row, "writeup")
            continue

        # A result PDF that yields almost nothing is almost always a scanned
        # image or a changed layout. Publishing it would tell every candidate
        # they were not selected, so it is skipped instead.
        if len(rolls) < args.min_rolls:
            print("  skipped       too few rolls (scanned image or new layout?)")
            _mark_skipped(row, "too few rolls")
            continue

        for i in range(1, len(rolls)):
            if not rolls[i - 1] < rolls[i]:
                print(f"  skipped       not sorted at {i}")
                _mark_skipped(row, "not sorted")
                break
        else:
            # Hashed: the published object contains no roll numbers, only salted
            # digests. This is what makes working from an official PDF defensible.
            body, mode = build_index(
                rolls,
                with_ranks=False,
                salt=hashed_index.exam_salt(exam_id),
            )
            print(f"  mode          {mode}")
            print(f"  gzip          {len(body) / 1024:.1f} KB")

            with tempfile.NamedTemporaryFile(suffix=".json.gz", delete=False) as fh:
                fh.write(body)
                tmp = Path(fh.name)

            # Content-addressed object name.
            #
            # The roll route is cached `immutable`, which is only true if the URL
            # never changes. A stable URL meant the edge served the FIRST published
            # index for 24 h — including after a corrected list replaced it. Naming
            # the object after its own content makes `immutable` correct: new
            # content is a new URL, old URLs stay valid forever, and the app reads
            # the version from the feed row.
            version = hashlib.sha256(body).hexdigest()[:12]
            previous_version = row.get("index_version")

            # Flag the row so the app can offer "Check my result" for it.
            row["index_available"] = True
            row["roll_count"] = len(rolls)
            row["index_version"] = version

            # The salt is derived from the exam id, so an unchanged candidate list
            # hashes to the same bytes and therefore the same object name. Re-put
            # it only when it actually changed.
            if previous_version == version and not args.dry_run:
                print("  unchanged     already published at this version")
            else:
                publish(
                    tmp,
                    f"v1/rolls/{exam_id}_{version}_rolls.json.gz",
                    args.dry_run,
                )
            os.unlink(tmp)
            built += 1

    print(f"\nbuilt         {built} index(es)")

    if not args.dry_run and built:
        Path(args.feed).write_text(json.dumps(feed, indent=2))
        print(f"updated       {args.feed} (index_available flags)")

    return 0 if built or args.dry_run else 1


if __name__ == "__main__":
    sys.exit(main())
