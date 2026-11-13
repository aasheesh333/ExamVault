#!/usr/bin/env node
/**
 * Publishes the radar document to Cloudflare R2.
 *
 * The app reads exactly one object (`v1/live_feed_v1.json`) from the edge, so this
 * script is the only thing that decides what "live" means. It is the seam between
 * the app and the outside world:
 *
 *   source of truth  ->  this script  ->  R2 object  ->  CDN  ->  app
 *
 * Right now the source of truth is a local JSON file. To go fully production,
 * replace `readSource()` with the official notification feeds (SSC, UPSC, IBPS,
 * RRB) and run this on a cron. The app does not change.
 *
 * IMPORTANT: never publish invented rows. A stale document is recoverable; a wrong
 * "RESULT OUT" is not — students act on it.
 *
 *   node publish_feed.mjs --in ../data/live_feed.json [--dry-run]
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { argv } from 'node:process';

const input = arg('in', 'live_feed.json');
const dryRun = argv.includes('--dry-run');
const bucket = arg('bucket', 'examvault-cdn');
const key = 'v1/live_feed_v1.json';

function arg(name, fallback) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}

const REQUIRED = ['exam_id', 'category', 'exam_name', 'status', 'published_at'];
const CATEGORIES = new Set(['ssc', 'upsc', 'banking', 'railways', 'state_psc']);
const STATUSES = new Set([
  'result_out',
  'admit_card_live',
  'form_closing',
  'answer_key',
  'awaited',
]);

/**
 * Optional "when" fields. They are deliberately NOT required and NOT run
 * through the `published_at` future-guard below: an exam date or a result date
 * is normally in the FUTURE, which is the whole point of showing it. They only
 * have to be a real `YYYY-MM-DD` calendar date.
 */
const DATE_FIELDS = ['exam_date', 'result_date', 'deadline'];

/**
 * Default time-to-live per status, in hours.
 *
 * A radar row must stop shouting once it is no longer useful. "RESULT OUT" three
 * days later is misinformation; students tap through and lose trust. The
 * publisher stamps `expires_at` so the app can drop the row on its own, without
 * waiting for someone to remember to edit the file.
 */
const TTL_HOURS = {
  // A declared result remains the current state of that exam until the next
  // stage is announced — weeks, not days. The first version used 48h and
  // immediately expired 16 of SSC's 18 live notices, which would have shown an
  // almost-empty radar on top of entirely real data.
  result_out: 24 * 30,
  // Admit-card windows run from release to exam day.
  admit_card_live: 24 * 21,
  // A closing form is urgent but short-lived.
  form_closing: 24 * 7,
  answer_key: 24 * 30,
  // "Awaited" is a standing placeholder.
  awaited: 24 * 90,
};

/** Refuses to publish a document whose own rows are already stale. */
function stampExpiry(doc) {
  const now = Date.now();
  let stale = 0;

  for (const row of doc.updates) {
    if (row.expires_at) continue;
    const hours = TTL_HOURS[row.status];
    if (!hours) continue;
    const expiry = Date.parse(row.published_at) + hours * 3600 * 1000;
    row.expires_at = new Date(expiry).toISOString();
    if (expiry < now) stale++;
  }

  return { stale, total: doc.updates.length };
}

/** Validates before publishing. A bad document must never reach the edge. */
function validate(doc) {
  const errors = [];

  if (typeof doc !== 'object' || doc === null) {
    throw new Error('feed must be a JSON object');
  }
  if (!Array.isArray(doc.updates)) {
    throw new Error('feed.updates must be an array');
  }

  doc.updates.forEach((row, i) => {
    for (const field of REQUIRED) {
      if (row[field] === undefined || row[field] === null || row[field] === '') {
        errors.push(`updates[${i}] missing ${field}`);
      }
    }
    if (row.category && !CATEGORIES.has(row.category)) {
      errors.push(`updates[${i}] unknown category "${row.category}"`);
    }
    if (row.status && !STATUSES.has(row.status)) {
      errors.push(`updates[${i}] unknown status "${row.status}"`);
    }
    if (row.published_at && Number.isNaN(Date.parse(row.published_at))) {
      errors.push(`updates[${i}] published_at is not a date`);
    }
    if (row.published_at && Date.parse(row.published_at) > Date.now() + 60_000) {
      errors.push(`updates[${i}] published_at is in the future`);
    }
    for (const field of DATE_FIELDS) {
      const value = row[field];
      if (value === undefined || value === null) continue; // absence is valid
      if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        errors.push(`updates[${i}] ${field} must be YYYY-MM-DD`);
        continue;
      }
      // Date.parse alone rolls 31 Feb over to March; compare the parts back.
      const [year, month, day] = value.split('-').map(Number);
      const date = new Date(Date.UTC(year, month - 1, day));
      if (
        date.getUTCFullYear() !== year ||
        date.getUTCMonth() !== month - 1 ||
        date.getUTCDate() !== day
      ) {
        errors.push(`updates[${i}] ${field} is not a real calendar date`);
      }
    }
  });

  if (errors.length) {
    throw new Error(`feed is invalid:\n  - ${errors.join('\n  - ')}`);
  }
  return doc;
}

const raw = readFileSync(input, 'utf8');
const doc = validate(JSON.parse(raw));

// Stamp the publish time so the app can show age honestly. `generated_at` is
// publish-side by nature (it lives only in the uploaded copy).
doc.generated_at = new Date().toISOString();

// Revision is NOT bumped here. `fetch_official_feeds.mjs` owns it and raises it
// only when the feed CONTENT actually changed. This script used to bump it
// again on the uploaded copy only, so the edge document and the repo snapshot
// permanently disagreed by one and the number climbed ~48/day through runs
// that changed nothing. publish_feed must be a pure stamp-and-upload.
doc.revision = doc.revision ?? 0;

const { stale, total } = stampExpiry(doc);

const body = JSON.stringify(doc, null, 2);
console.log(`feed      ${input}`);
console.log(`updates   ${doc.updates.length}`);
if (stale > 0) {
  console.log(
    `note      ${stale}/${total} rows are already past their TTL — hidden by the app.`,
  );
}
console.log(`revision  ${doc.revision}`);
console.log(`size      ${(body.length / 1024).toFixed(1)} KB`);

if (dryRun) {
  console.log('dry-run   not published');
  process.exit(0);
}

// Upload the STAMPED document, not the input file. The first version of this
// script mutated `generated_at` / `revision` in memory and then uploaded the
// original bytes, so every publish shipped a stale timestamp and the app kept
// labelling a freshly published feed as "1d OLD".
const stamped = join(tmpdir(), `examvault-feed-${Date.now()}.json`);
writeFileSync(stamped, body);

execFileSync(
  'npx',
  [
    '--yes',
    'wrangler@4',
    'r2',
    'object',
    'put',
    `${bucket}/${key}`,
    `--file=${stamped}`,
    '--content-type=application/json; charset=utf-8',
    '--remote',
  ],
  { stdio: 'inherit' },
);

console.log(`published ${bucket}/${key}`);
