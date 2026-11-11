#!/usr/bin/env node
/**
 * Builds `data/live_feed.json` from the official commissions' own websites.
 *
 * This is the producer behind `publish_feed.mjs`. The app reads one document; this
 * script decides what is true in it.
 *
 * ## Sources (all official, all verified live on 2026-11-10)
 *
 *   ssc       ssc.gov.in          JSON API        results + notice boards
 *   upsc      upsc.gov.in         HTML            "What's New" + detail pages
 *   ibps      ibps.in             HTML            ongoing-recruitment grid
 *   tnpsc     tnpsc.gov.in        HTML            results grid (state PSC)
 *   railways  rrbchennai.gov.in   HTML            CEN notices (RRB)
 *
 * Together they cover the five categories the app ships with: SSC, UPSC,
 * Banking, Railways, State PSC.
 *
 * ## Two hard rules
 *
 * 1. **Never invent a row.** Every field comes from the source document. If a
 *    source is unreachable, this script records the outage in the `sources` block
 *    and continues — a missing category is visible, and a fabricated "RESULT OUT"
 *    is impossible.
 * 2. **Link, never mirror.** The official PDF stays on the commission's server.
 *    Only a one-way hashed index of the roll numbers is ever published (`See
 *    tools/build_indexes.py`), which is a derived artefact, not a copy.
 *
 *   node fetch_official_feeds.mjs --out ../data/live_feed.json [--dry-run]
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { argv } from 'node:process';
import { pathToFileURL } from 'node:url';

import { canonicalJson, stripVolatile } from './normalize_feed.mjs';
import ssc from './sources/ssc.mjs';
import upsc from './sources/upsc.mjs';
import ibps from './sources/ibps.mjs';
import tnpsc from './sources/tnpsc.mjs';
import railways from './sources/railways.mjs';

/** Registry order is also the order the health block is reported in. */
const SOURCES = [ssc, upsc, ibps, tnpsc, railways];

/** Enough rows that every category has content, small enough to stay cacheable. */
const MAX_UPDATES = 80;

/**
 * Per-source cap.
 *
 * One board can emit twenty dated items in a week (RRB Chennai does), which would
 * bury SSC and UPSC in an unfiltered radar. Capping each source keeps the default
 * view a digest of *all* exams rather than a feed of one.
 */
const MAX_PER_SOURCE = Number(arg('per-source', '20'));

const out = arg('out', '../data/live_feed.json');
const dryRun = argv.includes('--dry-run');
const limit = Number(arg('limit', '25'));

function arg(name, fallback) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}

/** Statuses the app understands. Anything else indicates an adapter bug. */
const VALID_STATUS = new Set([
  'result_out',
  'admit_card_live',
  'answer_key',
  'form_closing',
  'awaited',
]);

/**
 * Carries the index bookkeeping forward from the previous feed.
 *
 * `build_indexes.py` runs *after* this script and stamps `index_available`,
 * `index_version`, `roll_count` and `index_built_at` onto rows it publishes,
 * and `index_attempted_at`/`index_skipped` onto rows it fails on. Without
 * carrying ALL of them, the next 30-minute refresh would erase those stamps:
 * the app would stop offering "check my result" even though the object is
 * still on the CDN, and — worse — every failed PDF would lose its weekly
 * cooldown memo and be re-downloaded on every single run forever.
 */
export function carryIndexFields(rows, previous) {
  const byId = new Map();
  for (const row of previous?.updates ?? []) {
    if (row?.exam_id) byId.set(row.exam_id, row);
  }

  for (const row of rows) {
    // A producer-set pause (e.g. SSC's multi-part flag) outranks any old
    // stamp: the pipeline is refusing to index this row, so it must not
    // advertise a stale index built from a partial list.
    if (row.index_skipped) continue;

    const old = byId.get(row.exam_id);
    if (!old) continue;
    // Only trust the old bookkeeping when it was made from the same PDF.
    if ((old.official_pdf ?? null) !== (row.official_pdf ?? null)) continue;

    if (old.index_available) {
      row.index_available = true;
      if (old.index_version) row.index_version = old.index_version;
      if (typeof old.roll_count === 'number') row.roll_count = old.roll_count;
      if (old.index_built_at) row.index_built_at = old.index_built_at;
    }
    if (old.index_attempted_at) {
      row.index_attempted_at = old.index_attempted_at;
      if (old.index_skipped) row.index_skipped = old.index_skipped;
    }
  }
  return rows;
}

/** Drops rows that cannot be shown or opened, and rows the app would reject. */
export function validate(row) {
  if (!row?.exam_id || !row?.exam_name) return 'missing id or name';
  if (!VALID_STATUS.has(row.status)) return `bad status ${row.status}`;
  if (!row.published_at || Number.isNaN(Date.parse(row.published_at))) {
    return 'missing date';
  }
  if (!row.official_pdf && !row.official_page) return 'no source link';
  if (row.official_pdf && !/^https?:\/\//i.test(row.official_pdf)) {
    return 'relative pdf url';
  }
  if (row.official_page && !/^https?:\/\//i.test(row.official_page)) {
    return 'relative page url';
  }
  return null;
}

/**
 * Deterministic feed ordering: newest first, ties broken by exam_id ascending.
 *
 * The tie-breaker matters. Date-only notices now share a midnight-UTC stamp,
 * and UPSC rows arrive from a worker pool in completion order — without a
 * total order, the same world state serialises to a different array order on
 * every run, and the "did the CONTENT change?" decisions (the revision bump
 * here, the snapshot commit in refresh-data.yml) would fire on pure ordering
 * jitter. A stable sort is not enough; the INPUT order must not leak through.
 */
function byRecencyThenId(a, b) {
  const delta = Date.parse(b.published_at) - Date.parse(a.published_at);
  if (delta !== 0) return delta;
  return a.exam_id < b.exam_id ? -1 : a.exam_id > b.exam_id ? 1 : 0;
}

async function main() {
  const health = [];
  const rows = [];

  for (const source of SOURCES) {
    const started = Date.now();
    try {
      const produced = await source.run({ limit });
      const elapsed = Date.now() - started;

      let kept = 0;
      for (const row of produced) {
        const problem = validate(row);
        if (problem) {
          console.log(`  drop (${source.id}): ${problem} — ${row?.exam_name?.slice(0, 50)}`);
          continue;
        }
        rows.push(row);
        kept += 1;
      }

      health.push({
        id: source.id,
        label: source.label,
        category: source.category,
        homepage: source.homepage,
        status: kept > 0 ? 'ok' : 'empty',
        rows: kept,
        checked_at: new Date().toISOString(),
        elapsed_ms: elapsed,
        ...(source.note ? { note: source.note } : {}),
      });
      console.log(
        `${source.id.padEnd(9)} ${String(kept).padStart(3)} fetched  ${elapsed} ms` +
          (source.note ? `  (${source.note})` : ''),
      );
    } catch (e) {
      // An outage is a fact about the world, not a reason to invent rows.
      health.push({
        id: source.id,
        label: source.label,
        category: source.category,
        homepage: source.homepage,
        status: 'unavailable',
        rows: 0,
        checked_at: new Date().toISOString(),
        elapsed_ms: Date.now() - started,
        reason: String(e?.message ?? e).slice(0, 160),
      });
      console.log(`${source.id.padEnd(9)}   -  unavailable: ${String(e?.message ?? e).slice(0, 90)}`);
    }
  }

  // Deduplicate by exam id, keeping the first (adapters emit newest first).
  const byId = new Map();
  for (const row of rows) if (!byId.has(row.exam_id)) byId.set(row.exam_id, row);

  let previous = null;
  try {
    previous = JSON.parse(readFileSync(out, 'utf8'));
  } catch {
    previous = null;
  }

  // Cap per source before the global sort, so a quiet week on one board cannot
  // push another board's news out entirely.
  const counts = new Map();
  const capped = [...byId.values()]
    .sort(byRecencyThenId)
    .filter((row) => {
      const key = row.source_id ?? row.category;
      const n = counts.get(key) ?? 0;
      if (n >= MAX_PER_SOURCE) return false;
      counts.set(key, n + 1);
      return true;
    });

  const carried = carryIndexFields(capped, previous);

  /**
   * Keep searchable results even after the notice scrolls off the board.
   *
   * The radar shows what is *new*; the result checker answers what is *true*. A
   * shortlist published six weeks ago still needs to answer "am I in it", so a
   * row with a live index is retained past the recency window. Without this, a
   * student who saved an admit card would find the checker empty a month later,
   * even though the hashed index is still on the CDN.
   */
  const RETAIN_MS = 150 * 24 * 60 * 60 * 1000;
  const present = new Set(carried.map((r) => r.exam_id));
  // Also dedupe retention by official URL: when a row's exam_id SCHEME changes
  // (upsc hash suffixes, railways date-free ids), the old-id row is no longer
  // "present" by id and would be retained ALONGSIDE its new-id twin — the same
  // notice twice on the radar, one of them pointing at an index path that no
  // longer matches its (re-salted) exam id.
  const presentUrls = new Set(
    carried.map((r) => r.official_pdf ?? r.official_page).filter(Boolean),
  );
  for (const row of previous?.updates ?? []) {
    if (!row?.index_available || present.has(row.exam_id)) continue;
    const url = row.official_pdf ?? row.official_page;
    if (url && presentUrls.has(url)) continue;
    if (Date.now() - Date.parse(row.published_at) > RETAIN_MS) continue;
    if (!row.official_pdf) continue;
    carried.push(row);
    present.add(row.exam_id);
    if (url) presentUrls.add(url);
  }

  const updates = carried
    .sort(byRecencyThenId)
    .slice(0, MAX_UPDATES);

  /**
   * The health block's `rows` is displayed by the app as "N items", so it must
   * be the number of rows the source ACTUALLY has in the published document —
   * after global dedupe, the per-source cap and the MAX_UPDATES slice. It used
   * to be the pre-dedupe keep count (railways reported 25 while contributing
   * 20; upsc reported 12 while contributing 8), i.e. the About sheet lied.
   * Retained rows count for the source that produced them.
   */
  const contributed = new Map();
  for (const u of updates) {
    const key = u.source_id ?? u.category;
    contributed.set(key, (contributed.get(key) ?? 0) + 1);
  }
  for (const entry of health) {
    if (entry.status === 'unavailable') continue; // outage: rows stay 0 + reason
    entry.rows = contributed.get(entry.id) ?? 0;
    if (entry.rows === 0) entry.status = 'empty';
  }

  const docContent = {
    source: 'official commission websites',
    fetched_at: new Date().toISOString(),
    // Machine-readable coverage: which bodies answered, and which did not. The
    // `rows` counts above are post-dedupe/post-cap, so the app's About sheet
    // reports what the document actually contains.
    sources: health,
    updates,
  };

  /**
   * `revision` counts distinct feed STATES, not refresh runs.
   *
   * It used to rise on every fetch AND again in publish_feed.mjs (on the
   * uploaded copy only), so the edge and the repo snapshot permanently
   * disagreed and the number meant nothing. Now: publish never bumps, and
   * fetch bumps only when the normalized content (volatile timestamps
   * stripped, keys sorted — see normalize_feed.mjs) actually differs from the
   * previous document.
   */
  const contentNow = canonicalJson(stripVolatile({ ...docContent, revision: 0 }));
  const contentBefore = previous ? canonicalJson(stripVolatile({ ...previous, revision: 0 })) : null;
  const changedContent = contentBefore === null || contentNow !== contentBefore;
  const revision = changedContent ? (previous?.revision ?? 1) + 1 : previous.revision;

  const doc = {
    revision,
    ...docContent,
  };

  const byCategory = {};
  for (const u of updates) byCategory[u.category] = (byCategory[u.category] ?? 0) + 1;
  console.log(`\nkept           ${updates.length}`);
  console.log('categories     ' + JSON.stringify(byCategory));
  console.log(
    `revision       ${revision} (${changedContent ? 'content changed' : 'content unchanged'})`,
  );
  for (const u of updates.slice(0, 8)) {
    console.log(
      `  ${u.published_at.slice(0, 10)}  ${u.category.padEnd(9)} ${u.status.padEnd(16)} ${u.exam_name.slice(0, 52)}`,
    );
  }

  if (dryRun) {
    console.log('dry-run        not written');
    return 0;
  }

  // A refresh that loses every source must not replace a good document with an
  // empty one — every client would lose the radar until the next run.
  if (updates.length === 0 && (previous?.updates?.length ?? 0) > 0) {
    console.error('refusing to publish an empty feed over a populated one');
    return 2;
  }

  writeFileSync(out, JSON.stringify(doc, null, 2));
  console.log(`wrote          ${out}`);
  return 0;
}

// Runs only when invoked as a script (`node fetch_official_feeds.mjs …`), so
// unit tests can import `carryIndexFields`/`validate` without triggering a
// network fetch of all five commissions.
const invokedAsCli = argv[1] && import.meta.url === pathToFileURL(argv[1]).href;

if (invokedAsCli) {
  main()
    .then((code) => process.exit(code ?? 0))
    .catch((e) => {
      console.error('FAILED:', e.message);
      process.exit(1);
    });
}
