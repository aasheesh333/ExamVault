/**
 * Regression fixtures for date-only notices.
 *
 * The bug these pin: `toIsoDate` used to stamp date-only notices at NOON UTC.
 * `publish_feed.mjs` (correctly) rejects any `published_at` in the future, so
 * every refresh between 00:00Z and 12:00Z that saw a same-day notice
 * (05:30–17:30 IST — exactly SSC/UPSC posting hours) died WHOLESALE with
 * "published_at is in the future". Date-only notices must stamp at 00:00 UTC,
 * which is never in the future once the day has started anywhere.
 *
 * Run: node --test tools/test/
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { toIsoDate } from '../sources/lib.mjs';

test('date-only notices stamp at 00:00 UTC, never noon', () => {
  assert.equal(toIsoDate('09-11-2026'), '2026-11-09T00:00:00.000Z');
  assert.equal(toIsoDate('09/11/2026'), '2026-11-09T00:00:00.000Z');
  assert.equal(toIsoDate('9 Nov 2026'), '2026-11-09T00:00:00.000Z');
  assert.equal(toIsoDate('09 November 2026'), '2026-11-09T00:00:00.000Z');
  assert.equal(toIsoDate('2026-11-09'), '2026-11-09T00:00:00.000Z');
  assert.equal(toIsoDate('04-Nov-2026'), '2026-11-04T00:00:00.000Z');
  assert.equal(toIsoDate('25-Nov-26'), '2026-11-25T00:00:00.000Z');
});

test('a same-day notice is never in the future at any hour of the UTC day', () => {
  const todayUtc = new Date().toISOString().slice(0, 10);
  const [y, m, d] = todayUtc.split('-').map(Number);
  const stamp = toIsoDate(`${String(d).padStart(2, '0')}-${String(m).padStart(2, '0')}-${y}`);
  assert.equal(stamp, `${todayUtc}T00:00:00.000Z`);
  assert.ok(Date.parse(stamp) <= Date.now(), 'same-day stamp must not be in the future');
});

test('ambiguous slash dates stay D/M/Y (every source is Indian)', () => {
  // 05/11/2026 is 5 November, not 11 May.
  assert.equal(toIsoDate('05/11/2026'), '2026-11-05T00:00:00.000Z');
});

test('out-of-range years are rejected, not wrapped', () => {
  assert.equal(toIsoDate('9 Nov 1999'), null);
  assert.equal(toIsoDate('garbage'), null);
  assert.equal(toIsoDate(''), null);
});
