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
  });

  if (errors.length) {
    throw new Error(`feed is invalid:\n  - ${errors.join('\n  - ')}`);
  }
  return doc;
}

const raw = readFileSync(input, 'utf8');
const doc = validate(JSON.parse(raw));

// Stamp the publish time so the app can show age honestly.
doc.generated_at = new Date().toISOString();
doc.revision = (doc.revision ?? 0) + 1;

const body = JSON.stringify(doc, null, 2);
console.log(`feed      ${input}`);
console.log(`updates   ${doc.updates.length}`);
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
