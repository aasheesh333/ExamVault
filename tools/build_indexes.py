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
                              ├─ verify non-trivial (min-rolls, writeup, size
                              │   budget; warn on bimodal roll shapes)
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
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import hashed_index  # noqa: E402
from extract_rolls import (  # noqa: E402
    build_index,
    download,
    extract_rolls,
    read_pdf_text,
    warn_if_bimodal,
)
import re  # noqa: E402

BUCKET = "examvault-cdn"

# Writer-side size budget. The app refuses to download more than
# `AppConfig.maxDownloadBytes` (12 MB, app/lib/core/config/app_config.dart), so
# publishing an index above that would ship a checker that can never load —
# 10 MB leaves headroom for gzip-level variance and future overhead.
MAX_INDEX_BYTES = 10 * 1024 * 1024

# An index older than this is due for a revisit: commissions DO replace PDFs
# at the same URL (corrected lists), and a content-addressed republish makes
# that safe. Also the cooldown for retrying a failed extraction.
REVISIT_AFTER = timedelta(days=7)


def _mark_skipped(row: dict, reason: str) -> None:
    """Records a failed extraction so the next run does not repeat it."""
    row["index_attempted_at"] = datetime.now(timezone.utc).isoformat()
    row["index_skipped"] = reason[:120]


def _mark_built(row: dict, version: str, roll_count: int) -> None:
    """Stamps a successful build and clears any stale failure memo."""
    now = datetime.now(timezone.utc).isoformat()
    row["index_available"] = True
    row["index_version"] = version
    row["roll_count"] = roll_count
    # Persisted so the scheduler knows when this row was last VERIFIED, not
    # just that it once succeeded — without it, indexed rows were never
    # revisited and a corrected PDF at the same URL served a stale index
    # forever.
    row["index_built_at"] = now
    row.pop("index_attempted_at", None)
    row.pop("index_skipped", None)


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
    # bimodal-length warning from `extract_rolls`: a "writeup" PDF naming three
    # illustrative rolls produces three numbers and is rejected, so nobody is
    # ever told they were not selected on the strength of a document that never
    # listed them.
    candidates = [
        r
        for r in feed.get("updates", [])
        if r.get("status") in INDEXABLE and r.get("official_pdf")
    ]

    # ## Scheduling
    #
    # The old scheme sorted unindexed rows first and sliced `--limit` off the
    # top. With a permanent backlog of unindexable rows (scanned PDFs,
    # writeups) that class never drained, so INDEXED rows were never revisited:
    # a commission that corrected a PDF at the same URL kept serving the stale
    # index forever — silent wrong "not selected" verdicts for every corrected
    # candidate.
    #
    # Now:
    #   * multi-part rows paused by the producer are excluded entirely;
    #   * rows that failed within the last 7 days are excluded (weekly retry);
    #   * the remaining budget is shared ROUND-ROBIN between
    #       - new:     no index yet, and
    #       - revisit: index_available but index_built_at older than 7 days
    #                  (or missing the field, i.e. built before it existed),
    #     oldest verification first. Unindexed rows take the first slot of
    #     each pair, so both classes always progress under any backlog.
    now = datetime.now(timezone.utc)

    def is_paused(row) -> bool:
        # Producer-set pause (SSC multi-part lists). Not a failure, so it must
        # not be retried or overwritten by a memo — SSC has to publish a
        # single complete list first.
        return str(row.get("index_skipped") or "").startswith("multi-part")

    def is_fresh_skip(row) -> bool:
        if row.get("index_available"):
            return False
        attempted = _parse_iso(row.get("index_attempted_at"))
        return bool(attempted) and (now - attempted) < REVISIT_AFTER

    def needs_revisit(row) -> bool:
        if not row.get("index_available"):
            return False
        built = _parse_iso(row.get("index_built_at"))
        return built is None or (now - built) >= REVISIT_AFTER

    def recency(row) -> float:
        published = _parse_iso(row.get("published_at"))
        return published.timestamp() if published else 0.0

    def built_at(row) -> float:
        built = _parse_iso(row.get("index_built_at"))
        return built.timestamp() if built else 0.0

    paused = [r for r in candidates if is_paused(r)]
    fresh_skips = [r for r in candidates if is_fresh_skip(r)]
    new_rows = sorted(
        (
            r
            for r in candidates
            if not r.get("index_available") and not is_paused(r) and not is_fresh_skip(r)
        ),
        key=recency,
        reverse=True,
    )
    stale_rows = sorted(
        (r for r in candidates if needs_revisit(r) and not is_paused(r)),
        key=built_at,
    )

    scheduled: list[tuple[str, dict]] = []
    i = j = 0
    while len(scheduled) < args.limit and (i < len(new_rows) or j < len(stale_rows)):
        if i < len(new_rows):
            scheduled.append(("new", new_rows[i]))
            i += 1
        if len(scheduled) >= args.limit:
            break
        if j < len(stale_rows):
            scheduled.append(("revisit", stale_rows[j]))
            j += 1

    print(
        f"candidates    {len(candidates)} result rows with a PDF  "
        f"(new={len(new_rows)}, due-for-revisit={len(stale_rows)}, "
        f"paused-multi-part={len(paused)}, cooling-down={len(fresh_skips)})"
    )
    for cls, row in scheduled:
        print(f"  scheduled     [{cls:7}] {row['exam_id']}")

    # `--pattern` overrides the per-source registry (used for one-off debugging).
    pattern_override = args.pattern
    built = 0
    # Any mutation of a row (a stamp, a memo) must reach data/live_feed.json,
    # EVEN when nothing was built: the old `if built:` guard threw every
    # failure memo away on built-zero runs, so the weekly cooldown never took
    # effect and the same dead PDFs were re-downloaded every 30 minutes.
    changed = False

    for cls, row in scheduled:
        exam_id = row["exam_id"]
        url = row["official_pdf"]
        print(f"\n{exam_id}  [{cls}]")
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
            changed = True
            continue
        except Exception as e:  # noqa: BLE001
            print(f"  skipped       {type(e).__name__}: {e}")
            _mark_skipped(row, f"{type(e).__name__}: {e}")
            changed = True
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
            changed = True
            continue

        # A result PDF that yields almost nothing is almost always a scanned
        # image or a changed layout. Publishing it would tell every candidate
        # they were not selected, so it is skipped instead.
        if len(rolls) < args.min_rolls:
            print("  skipped       too few rolls (scanned image or new layout?)")
            _mark_skipped(row, "too few rolls")
            changed = True
            continue

        # Signal, not a gate: two populated digit-length modes usually mean an
        # interleaved column (serials/dates/marks) was captured as rolls.
        warn_if_bimodal(rolls)

        # Ascending order is structural (`extract_rolls` returns `sorted(set)`),
        # so the old "strictly ascending" gate here was dead code and is gone.
        #
        # Hashed: the published object contains no roll numbers, only salted
        # digests. This is what makes working from an official PDF defensible.
        body, mode = build_index(
            rolls,
            with_ranks=False,
            salt=hashed_index.exam_salt(exam_id),
        )
        print(f"  mode          {mode}")
        print(f"  gzip          {len(body) / 1024:.1f} KB")

        # Device budget. The app hard-caps index downloads at 12 MB; publishing
        # anything above ~10 MB gzip would create an index no device can load,
        # i.e. a permanent "cannot check" for that exam. Skip loudly instead —
        # a list that big needs chunking, which is a deliberate feature, not a
        # silent publish.
        if len(body) > MAX_INDEX_BYTES:
            print(
                f"WARNING   SKIPPING {exam_id}: index is {len(body) / 1024 / 1024:.1f} MB "
                f"gzip, above the {MAX_INDEX_BYTES // (1024 * 1024)} MB device budget "
                "(app cap is 12 MB). This list is NOT searchable until it is chunked.",
                file=sys.stderr,
            )
            _mark_skipped(row, "index exceeds device budget")
            changed = True
            continue

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

        # Flag the row so the app can offer "Check my result" for it, and stamp
        # WHEN it was verified so the revisit scheduler above works.
        _mark_built(row, version, len(rolls))
        changed = True

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

    # Write whenever ANY row changed — including runs that built nothing but
    # stamped failure memos. Without this the memos never reached
    # data/live_feed.json, the weekly cooldown never applied, and the same
    # dead PDFs were retried every single run.
    if not args.dry_run and changed:
        Path(args.feed).write_text(json.dumps(feed, indent=2))
        print(f"updated       {args.feed} (index flags/memos)")

    # "Built nothing" is not a failure.
    #
    # This returned 1 whenever no index was published, so the scheduled refresh
    # failed every time the only new PDFs were writeups (which are deliberately
    # rejected) — a green pipeline turned red for doing exactly the right thing.
    # A real error still surfaces as an exception, which propagates as a non-zero
    # exit anyway.
    return 0


if __name__ == "__main__":
    sys.exit(main())
