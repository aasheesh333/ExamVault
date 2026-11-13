/**
 * Fixtures for the optional `exam_date` / `result_date` / `deadline` fields.
 *
 * The rule these pin: a date may only be shown when the commission's own text
 * states it, right after an explicit trigger phrase. No trigger → no date;
 * unrelated numbers ("Part-IV", "12,480 aspirants") → no date; impossible or
 * far-out-of-range dates → no date. A wrong date is worse than a blank one.
 *
 * `now` is injected so the fixtures do not age out of the accepted year window.
 *
 * Run: node --test tools/test/
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { extractDates } from '../sources/lib.mjs';
import { normalizedFeedJson } from '../normalize_feed.mjs';

const NOW = new Date('2026-11-13T00:00:00.000Z');

function dates(input) {
  return extractDates({ ...input, now: NOW });
}

test('SSC exam date is taken from "Examination will be held on"', () => {
  const row = dates({
    headline: 'SSC CGL 2026 Tier-I Examination will be held on 21.11.2026',
    context: 'Notice board · ssc.gov.in',
  });
  assert.equal(row.exam_date, '2026-11-21');
  assert.equal(row.result_date, undefined);
  assert.equal(row.deadline, undefined);
});

test('a numerical exam range takes its first day', () => {
  const row = dates({
    headline: 'RRB CEN 09/2026 CBT Examination will be held on 21.11.2026 to 24.11.2026',
    context: 'Railway Recruitment Board · 9 Nov 2026',
  });
  assert.equal(row.exam_date, '2026-11-21');
});

test('an "and" exam range takes its first day', () => {
  const row = dates({
    headline: 'UPSC CSE (Preliminary) Examination dates: 21 & 22 November 2026',
    context: 'Published on upsc.gov.in',
  });
  assert.equal(row.exam_date, '2026-11-21');
});

test('IBPS deadline comes from the stated closing date', () => {
  const row = dates({
    headline: 'SBI — Recruitment of Probationary Officers',
    context: 'Online registration closes on 25-Nov-2026',
  });
  assert.equal(row.deadline, '2026-11-25');
  assert.equal(row.exam_date, undefined);
});

test('TNPSC result date is taken from "will be declared on"', () => {
  const row = dates({
    headline: 'TNPSC Group IV 2026 — Result of the Written Examination will be declared on 12 December 2026',
    context: 'Final result list · 01/2026',
  });
  assert.equal(row.result_date, '2026-12-12');
});

test('a result preceded by an exam date does not inherit the exam day', () => {
  const row = dates({
    headline:
      'SSC CHSL 2026 — Result of the examination held on 21.11.2026 will be declared on 12.12.2026',
  });
  assert.equal(row.exam_date, '2026-11-21');
  assert.equal(row.result_date, '2026-12-12');
});

test('other real formats parse and are normalised to ISO', () => {
  assert.equal(
    dates({ headline: 'Examination date: 21 November 2026' }).exam_date,
    '2026-11-21',
  );
  assert.equal(
    dates({ headline: 'Date of Examination: November 21, 2026' }).exam_date,
    '2026-11-21',
  );
  assert.equal(
    dates({ context: 'Last date for submission is 05/12/2026' }).deadline,
    '2026-12-05',
  );
  assert.equal(
    dates({ headline: 'Apply before 21-11-2026' }).deadline,
    '2026-11-21',
  );
});

test('a date before the trigger is ignored', () => {
  const row = dates({
    headline: '21.11.2026 — Examination will be held on 24.11.2026',
  });
  assert.equal(row.exam_date, '2026-11-24');
});

test('negative: no trigger phrase yields no dates', () => {
  assert.deepEqual(
    dates({ headline: 'SSC CGL 2026 Tier-I — notice for candidates' }),
    {},
  );
});

test('negative: "Part-IV" is not a date', () => {
  assert.deepEqual(
    dates({ headline: 'Written Result Part-IV', context: 'Official PDF · ssc.gov.in' }),
    {},
  );
});

test('negative: "12,480 aspirants" is not a date', () => {
  // Even with an explicit trigger, the comma-separated count must not parse.
  assert.deepEqual(
    dates({ headline: 'Exam date: 12,480 aspirants' }),
    {},
  );
  assert.deepEqual(
    dates({ headline: 'SSC CGL 2026 notice — 12,480 aspirants' }),
    {},
  );
});

test('negative: impossible calendar dates are dropped', () => {
  assert.deepEqual(
    dates({ headline: 'Examination will be held on 31.02.2027' }),
    {},
  );
  assert.deepEqual(
    dates({ headline: 'Result will be declared on 31 November 2026' }),
    {},
  );
});

test('negative: years outside [now-1, now+3] are dropped', () => {
  assert.deepEqual(
    dates({ headline: 'Examination will be held on 21.11.1999' }),
    {},
  );
  assert.deepEqual(
    dates({ headline: 'Examination will be held on 21.11.2031' }),
    {},
  );
});

test('negative: a date more than ~60 chars after the trigger is ignored', () => {
  const headline =
    'Examination will be held on ' + 'x'.repeat(70) + ' 21.11.2026';
  assert.deepEqual(dates({ headline }), {});
});

test('date fields are part of the normalized content hash', () => {
  const base = {
    updates: [{ exam_id: 'ssc_x', exam_date: '2026-11-21' }],
  };
  const same = {
    updates: [{ exam_id: 'ssc_x', exam_date: '2026-11-21' }],
  };
  const changed = {
    updates: [{ exam_id: 'ssc_x', exam_date: '2026-11-24' }],
  };
  assert.equal(normalizedFeedJson(base), normalizedFeedJson(same));
  assert.notEqual(normalizedFeedJson(base), normalizedFeedJson(changed));
});
