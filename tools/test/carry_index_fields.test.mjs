/**
 * Regression fixtures for index-bookkeeping carry-over between feed
 * generations.
 *
 * The bugs these pin:
 *  - failure memos (index_attempted_at / index_skipped) were erased on every
 *    regeneration, so the weekly cooldown in build_indexes.py never applied
 *    and dead PDFs were re-downloaded every 30 minutes;
 *  - index_built_at (the revisit scheduler's clock) must survive too, or
 *    every indexed row looks stale on every run;
 *  - a producer-set pause (SSC multi-part flag) must WIN over an old stamp —
 *    resurrecting index_available from a partial-list build is exactly the
 *    wrong-"not selected" verdict the pause exists to prevent.
 *
 * Run: node --test tools/test/
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { carryIndexFields } from '../fetch_official_feeds.mjs';

const PDF = 'https://ssc.gov.in/api/attachment/uploads/masterData/Results/LIST.pdf';

function previousRow(extra) {
  return { exam_id: 'ssc_x', official_pdf: PDF, ...extra };
}

test('carries the full index stamp for the same PDF', () => {
  const rows = [{ exam_id: 'ssc_x', official_pdf: PDF }];
  const previous = {
    updates: [
      previousRow({
        index_available: true,
        index_version: 'abc123def456',
        roll_count: 8956,
        index_built_at: '2026-11-10T08:00:00.000Z',
      }),
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].index_available, true);
  assert.equal(rows[0].index_version, 'abc123def456');
  assert.equal(rows[0].roll_count, 8956);
  assert.equal(rows[0].index_built_at, '2026-11-10T08:00:00.000Z');
});

test('carries failure memos so the weekly cooldown survives regeneration', () => {
  const rows = [{ exam_id: 'ssc_x', official_pdf: PDF }];
  const previous = {
    updates: [
      previousRow({
        index_attempted_at: '2026-11-10T08:00:00.000Z',
        index_skipped: 'too few rolls',
      }),
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].index_attempted_at, '2026-11-10T08:00:00.000Z');
  assert.equal(rows[0].index_skipped, 'too few rolls');
  assert.equal(rows[0].index_available, undefined);
});

test('does not carry anything when the PDF changed', () => {
  const rows = [{ exam_id: 'ssc_x', official_pdf: 'https://ssc.gov.in/other.pdf' }];
  const previous = {
    updates: [
      previousRow({
        index_available: true,
        index_version: 'abc123def456',
        index_attempted_at: '2026-11-10T08:00:00.000Z',
        index_skipped: 'too few rolls',
      }),
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].index_available, undefined);
  assert.equal(rows[0].index_version, undefined);
  assert.equal(rows[0].index_attempted_at, undefined);
});

test('a producer multi-part pause outranks an old index stamp', () => {
  const rows = [
    {
      exam_id: 'ssc_x',
      official_pdf: PDF,
      index_skipped: 'multi-part list (2 attachments)',
    },
  ];
  const previous = {
    updates: [previousRow({ index_available: true, index_version: 'abc123def456' })],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].index_available, undefined);
  assert.equal(rows[0].index_version, undefined);
  assert.equal(rows[0].index_skipped, 'multi-part list (2 attachments)');
});

test('missing previous feed is a no-op', () => {
  const rows = [{ exam_id: 'ssc_x', official_pdf: PDF }];
  carryIndexFields(rows, null);
  assert.deepEqual(rows, [{ exam_id: 'ssc_x', official_pdf: PDF }]);
});

test('carries dates only for the identical document (same link + context)', () => {
  const rows = [
    {
      exam_id: 'ibps_x',
      official_pdf: null,
      official_page: 'https://www.ibps.in/notice/1',
      context: 'Registration closes 25 Nov 2026',
    },
  ];
  const previous = {
    updates: [
      {
        exam_id: 'ibps_x',
        official_pdf: null,
        official_page: 'https://www.ibps.in/notice/1',
        context: 'Registration closes 25 Nov 2026',
        deadline: '2026-11-25',
      },
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].deadline, '2026-11-25');
});

test('a changed URL with no fresh date does not resurrect the old date', () => {
  const rows = [
    {
      exam_id: 'ibps_x',
      official_pdf: null,
      official_page: 'https://www.ibps.in/notice/2',
      context: 'Registration closes soon',
    },
  ];
  const previous = {
    updates: [
      {
        exam_id: 'ibps_x',
        official_pdf: null,
        official_page: 'https://www.ibps.in/notice/1',
        context: 'Registration closes 25 Nov 2026',
        deadline: '2026-11-25',
      },
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].deadline, undefined);
});

test('a changed context drops the old date even at the same URL', () => {
  const rows = [
    {
      exam_id: 'ibps_x',
      official_pdf: null,
      official_page: 'https://www.ibps.in/notice/1',
      context: 'Registration closes soon',
    },
  ];
  const previous = {
    updates: [
      {
        exam_id: 'ibps_x',
        official_pdf: null,
        official_page: 'https://www.ibps.in/notice/1',
        context: 'Registration closes 25 Nov 2026',
        deadline: '2026-11-25',
      },
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].deadline, undefined);
});

test('a freshly extracted date always wins over the carried one', () => {
  const rows = [
    {
      exam_id: 'ssc_x',
      official_pdf: PDF,
      context: 'Official PDF · ssc.gov.in',
      result_date: '2026-12-12',
    },
  ];
  const previous = {
    updates: [
      previousRow({
        result_date: '2026-11-21',
        context: 'Official PDF · ssc.gov.in',
      }),
    ],
  };
  carryIndexFields(rows, previous);
  assert.equal(rows[0].result_date, '2026-12-12');
});
