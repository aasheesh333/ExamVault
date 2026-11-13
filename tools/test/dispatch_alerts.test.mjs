import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  CHANNEL_ID,
  computeAlerts,
  dispatch,
  topicSafe,
} from '../dispatch_alerts.mjs';

function row(over = {}) {
  return {
    exam_id: 'ssc_cgl_2026',
    exam_name: 'SSC CGL 2026 Tier-1',
    category: 'ssc',
    status: 'result_out',
    published_at: '2026-11-10T09:00:00Z',
    context: 'Official PDF · ssc.gov.in',
    official_pdf: 'https://ssc.gov.in/list.pdf',
    ...over,
  };
}

const feed = (...updates) => ({ updates });

test('a brand-new result row alerts once, on the per-exam topic', () => {
  const alerts = computeAlerts(feed(), feed(row()));
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].topic, 'exam_ssc_cgl_2026');
  assert.equal(alerts[0].reason, 'new:result_out');
  assert.match(alerts[0].title, /Result is out/);
  assert.match(alerts[0].body, /SSC CGL 2026 Tier-1/);
});

test('an unchanged snapshot alerts nobody', () => {
  const prev = feed(row());
  assert.deepEqual(computeAlerts(prev, feed(row())), []);
});

test('a row whose status changed alerts for the new status', () => {
  const prev = feed(row({ status: 'awaited' }));
  const alerts = computeAlerts(prev, feed(row()));
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].reason, 'new:result_out');
});

test('a newly stated exam date alerts, in words, once', () => {
  // Same status and timestamp: only the date is new, which is the case this
  // test is about. (Changing the status too would make it a "new row".)
  const prev = feed(row({ status: 'admit_card_live', exam_date: null }));
  const next = feed(
    row({ status: 'admit_card_live', exam_date: '2026-12-21' }),
  );
  const alerts = computeAlerts(prev, next);
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].reason, 'exam_date');
  assert.match(alerts[0].title, /Exam date announced/);
  assert.match(alerts[0].body, /21 Dec 2026/);
});

test('a changed date re-alerts; an unchanged date does not', () => {
  const withDate = (d) => feed(row({ exam_date: d }));
  assert.equal(computeAlerts(withDate('2026-12-21'), withDate('2026-12-21')).length, 0);
  const moved = computeAlerts(withDate('2026-12-21'), withDate('2026-12-28'));
  assert.equal(moved.length, 1);
  assert.match(moved[0].body, /28 Dec 2026/);
});

test('deadlines and result dates are separate, labelled alerts', () => {
  const prev = feed(row({ status: 'form_closing' }));
  const next = feed(
    row({ status: 'form_closing', deadline: '2026-11-30', result_date: '2027-01-15' }),
  );
  const alerts = computeAlerts(prev, next);
  assert.deepEqual(
    alerts.map((a) => a.reason).sort(),
    ['deadline', 'result_date'],
  );
  const deadline = alerts.find((a) => a.reason === 'deadline');
  assert.match(deadline.title, /Last date to apply/);
});

test('statuses a student does not need a phone alert for are ignored', () => {
  const prev = feed();
  const next = feed(row({ status: 'awaited' }), row({ exam_id: 'x', status: 'answer_key' }));
  assert.deepEqual(computeAlerts(prev, next), []);
});

test('a row that only aged out of the feed alerts nobody', () => {
  assert.deepEqual(computeAlerts(feed(row()), feed()), []);
});

test('topic names are forced into FCM characters', () => {
  assert.equal(topicSafe('SSC CGL 2026/IV'), 'ssc_cgl_2026_iv');
  assert.equal(topicSafe('  '), '');
});

test('the android channel id matches the one the app creates', () => {
  // Pinned: MainActivity.CHANNEL_ID must equal this, or the custom chime is
  // silently replaced by the default sound.
  assert.equal(CHANNEL_ID, 'exam_alerts_v2');
});

test('without credentials it reports what it would send and sends nothing', async () => {
  const lines = [];
  const result = await dispatch({
    oldFeed: feed(),
    newFeed: feed(row()),
    env: {},
    log: (l) => lines.push(l),
  });
  assert.equal(result.sent, 0);
  assert.equal(result.alerts, 1);
  assert.ok(lines.some((l) => l.includes('NO push credentials')));
  assert.ok(lines.some((l) => l.includes('would send → [exam_ssc_cgl_2026]')));
});
