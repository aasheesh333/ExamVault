#!/usr/bin/env node
/**
 * Builds a publication-ready roll index.
 *
 * Output contract (the app depends on all four properties):
 *   1. JSON array, ascending lexicographic order of roll numbers
 *   2. optionally `[{ "r": "2201049821", "rank": 1284 }, ...]`
 *   3. gzip-compressed, stored as an OBJECT (not a transfer encoding)
 *   4. no BOM, UTF-8, LF free
 *
 * Sorting is the load-bearing step: the app binary-searches this array and falls
 * back to a linear scan the moment it detects an unsorted payload. A missing sort
 * here silently costs every user a full scan, so it is verified before writing.
 *
 *   node build_roll_index.mjs --exam ssc_cgl --in rolls.txt --out out.gz [--no-ranks]
 */

import { createWriteStream, readFileSync } from 'node:fs';
import { createGzip } from 'node:zlib';
import { argv } from 'node:process';

function arg(name, fallback = null) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}

const input = arg('in');
const output = arg('out');
const withRanks = !argv.includes('--no-ranks');
const exam = arg('exam', 'unknown');

if (!input || !output) {
  console.error('usage: node build_roll_index.mjs --exam <id> --in <rolls.txt> --out <file.json.gz>');
  process.exit(2);
}

function normalise(line) {
  // Strip BOM, zero-width, NBSP, en/em dashes and all whitespace — exactly what
  // the app does to user input, so the two can never disagree.
  return line
    .replace(/^\uFEFF/, '')
    .replace(/[\u200B\u00A0\u2013\u2014]/g, '')
    .replace(/\s+/g, '')
    .toUpperCase();
}

const raw = readFileSync(input, 'utf8');
const lines = raw.split(/\r?\n/);

const seen = new Set();
for (const line of lines) {
  const roll = normalise(line);
  if (!roll) continue;
  if (roll.length < 4 || roll.length > 24) continue;
  if (!/^[A-Z0-9\-/]+$/.test(roll)) continue;
  seen.add(roll);
}

const rolls = [...seen];

// Deduplicate *before* sorting, and sort with a plain comparator. `Array.sort()`
// without one sorts by UTF-16 code unit — which happens to match JavaScript's
// `<`, but `localeCompare` does NOT, and would break the app's binary search.
rolls.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

// Prove the contract before writing a byte.
for (let i = 1; i < rolls.length; i++) {
  if (!(rolls[i - 1] < rolls[i])) {
    console.error(`FATAL: not strictly ascending at index ${i} (${rolls[i - 1]} then ${rolls[i]})`);
    process.exit(1);
  }
}

const payload = withRanks
  ? rolls.map((r, i) => ({ r, rank: i + 1 }))
  : rolls;

const json = JSON.stringify(payload);

// gzip with maximum compression: this is written once and read 10M times, so the
// extra CPU here is the best trade in the whole pipeline.
const gz = createGzip({ level: 9 });
const out = createWriteStream(output);
gz.pipe(out);
gz.end(json);
await new Promise((res, rej) => {
  out.on('finish', res);
  out.on('error', rej);
});

const bytes = readFileSync(output).length;
const pct = ((bytes / json.length) * 100).toFixed(0);

console.log(`exam        ${exam}`);
console.log(`rolls       ${rolls.length.toLocaleString()}`);
console.log(`json        ${(json.length / 1024).toFixed(0)} KB`);
console.log(`gzip        ${(bytes / 1024).toFixed(1)} KB (${pct}% of raw)`);
console.log(`sorted      verified strictly ascending`);
console.log(`ranks       ${withRanks ? 'included' : 'omitted'}`);
console.log(`wrote       ${output}`);
