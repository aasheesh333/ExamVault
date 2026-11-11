#!/usr/bin/env node
/**
 * Normalizes a feed document for CONTENT comparison.
 *
 * Every refresh rewrites `fetched_at`, `sources[].checked_at` and
 * `sources[].elapsed_ms` even when not a single row changed — a raw
 * `git diff -- data/live_feed.json` was therefore dirty on all 48 daily runs,
 * and the repo history was ~48 noise commits/day. Stripping the volatile
 * fields (and sorting object keys, so field order can never fake a change)
 * leaves a document that differs if and only if the FEED differs.
 *
 * Used in two places, which must agree by construction — hence this module:
 *
 *   1. `fetch_official_feeds.mjs` — bumps `revision` only when the normalized
 *      content actually changed, so the number counts distinct feed states
 *      instead of refresh runs.
 *   2. `.github/workflows/refresh-data.yml` — commits the snapshot only when
 *      the normalized content differs from HEAD.
 *
 *   node normalize_feed.mjs <feed.json>   # prints normalized JSON
 */

import { readFileSync } from 'node:fs';
import { argv, exit } from 'node:process';
import { pathToFileURL } from 'node:url';

/** Fields that differ on every run even when the feed content is identical. */
export function stripVolatile(doc) {
  const copy = structuredClone(doc ?? {});
  delete copy.fetched_at;
  delete copy.generated_at;
  if (Array.isArray(copy.sources)) {
    for (const source of copy.sources) {
      if (source && typeof source === 'object') {
        delete source.checked_at;
        delete source.elapsed_ms;
      }
    }
  }
  return copy;
}

/** Deterministic JSON: sorted keys at every level, so only VALUES can differ. */
export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const entries = Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`);
    return `{${entries.join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

/** The canonical comparison form: volatile-stripped, deterministically keyed. */
export function normalizedFeedJson(doc) {
  return JSON.stringify(JSON.parse(canonicalJson(stripVolatile(doc))), null, 1);
}

const invokedAsCli = argv[1] && import.meta.url === pathToFileURL(argv[1]).href;

if (invokedAsCli) {
  const file = argv[2];
  if (!file) {
    console.error('usage: node normalize_feed.mjs <feed.json>');
    exit(2);
  }
  try {
    const doc = JSON.parse(readFileSync(file, 'utf8'));
    process.stdout.write(`${normalizedFeedJson(doc)}\n`);
  } catch (e) {
    console.error(`normalize_feed: ${file}: ${e.message}`);
    exit(1);
  }
}
