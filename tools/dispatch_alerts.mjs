#!/usr/bin/env node
/**
 * ExamVault alert dispatcher.
 *
 * Turns a feed diff into push notifications for the students who asked for that
 * exam. Runs at the end of the refresh workflow, after the new snapshot is
 * committed and published to the edge.
 *
 *   node dispatch_alerts.mjs --old <prev.json> --new <data/live_feed.json>
 *
 * Credentials (either provider, both optional):
 *   FCM_SERVICE_ACCOUNT_JSON   Firebase service-account JSON (raw or base64).
 *                              Preferred: per-topic send through FCM HTTP v1.
 *   EV_ONESIGNAL_REST_KEY      OneSignal REST API key (+ EV_ONESIGNAL_APP_ID).
 *
 * With neither present this exits 0 after saying so: a missing notification is
 * cosmetic, a red pipeline is not — and the next run with credentials catches
 * the same diff only if the snapshot changed, which is why the NOTICE is loud.
 *
 * Android channel: `exam_alerts_v2` — the versioned channel that carries the
 * custom chime (see MainActivity.kt for why the id carries a version).
 */
import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

export const CHANNEL_ID = 'exam_alerts_v2';

/** Statuses a student would want a phone alert for. */
const NOTIFY_STATUSES = new Set([
  'result_out',
  'admit_card_live',
  'form_closing',
]);

const KIND_LABEL = {
  exam_date: ['Exam date announced', 'exam'],
  result_date: ['Result date announced', 'result'],
  deadline: ['Last date to apply', 'deadline'],
};

/** Stable identity of "what this row says", for change detection. */
export function rowKey(row) {
  return [
    row.exam_id,
    row.status,
    row.published_at,
    row.index_version ?? '',
  ].join('|');
}

function dateFields(row) {
  return {
    exam_date: row.exam_date ?? null,
    result_date: row.result_date ?? null,
    deadline: row.deadline ?? null,
  };
}

/**
 * What to tell the student, from the difference between two snapshots.
 *
 * Pure and exported so the rules are testable without a network or a key.
 * Yields one alert per (exam, reason). An exam that merely aged out of the
 * feed produces nothing; a row whose text changed but whose status, time and
 * index version did not produces nothing either.
 */
export function computeAlerts(oldFeed, newFeed) {
  const before = new Map();
  for (const row of oldFeed?.updates ?? []) {
    if (!row || typeof row.exam_id !== 'string') continue;
    before.set(rowKey(row), row);
  }

  const alerts = [];
  const seen = new Set();

  const push = (row, reason, title, body) => {
    const id = `${row.exam_id}|${reason}`;
    if (seen.has(id)) return;
    seen.add(id);
    alerts.push({
      examId: row.exam_id,
      examName: row.exam_name,
      category: row.category,
      reason,
      title,
      body,
      link: row.official_pdf ?? row.official_page ?? null,
      topic: `exam_${topicSafe(row.exam_id)}`,
    });
  };

  for (const row of newFeed?.updates ?? []) {
    if (!row || typeof row.exam_id !== 'string') continue;
    if (!NOTIFY_STATUSES.has(row.status)) continue;

    const prior = before.get(rowKey(row));
    if (!prior) {
      // A row that was not in the previous snapshot at all.
      push(
        row,
        `new:${row.status}`,
        statusTitle(row.status),
        statusBody(row),
      );
      continue;
    }

    // Same notice, newly stated dates: that is the "when is my exam" alert.
    const oldDates = dateFields(prior);
    const newDates = dateFields(row);
    for (const [field, [label]] of Object.entries(KIND_LABEL)) {
      if (newDates[field] && newDates[field] !== oldDates[field]) {
        push(
          row,
          field,
          `${label} · ${row.exam_name}`,
          `${label}: ${formatDate(newDates[field])}. ${row.exam_name}${
            row.context ? ` — ${row.context}` : ''
          }`,
        );
      }
    }
  }

  return alerts;
}

export function topicSafe(raw) {
  return String(raw ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '_');
}

function statusTitle(status) {
  switch (status) {
    case 'result_out':
      return 'Result is out';
    case 'admit_card_live':
      return 'Admit card is live';
    case 'form_closing':
      return 'Last date is near';
    default:
      return 'New update';
  }
}

function statusBody(row) {
  const bits = [row.exam_name];
  if (row.context) bits.push(row.context);
  return `${bits.join(' — ')}. Tap to check.`;
}

function formatDate(iso) {
  const [y, m, d] = String(iso).split('-');
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const idx = Number(m) - 1;
  if (!months[idx]) return iso;
  return `${Number(d)} ${months[idx]} ${y}`;
}

// ---------------------------------------------------------------- providers

/** FCM v1 access token from a service-account JSON. No dependencies: sign with
 *  node:crypto, exchange at Google's token endpoint. */
async function fcmAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const b64 = (o) =>
    Buffer.from(JSON.stringify(o)).toString('base64url');
  const unsigned = `${b64(header)}.${b64(claim)}`;
  const signature = createSign('RSA-SHA256')
    .update(unsigned)
    .sign(serviceAccount.private_key);
  const assertion = `${unsigned}.${signature.toString('base64url')}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  }
  return (await res.json()).access_token;
}

async function sendFcm({ serviceAccount, alert }) {
  const token = await fcmAccessToken(serviceAccount);
  const projectId = serviceAccount.project_id;
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          topic: alert.topic,
          notification: { title: alert.title, body: alert.body },
          android: {
            priority: 'high',
            notification: {
              // The versioned channel that carries the custom chime. A payload
              // without this lands on the manifest default — same id — but
              // stating it keeps the intent explicit and survives a manifest
              // regression.
              channel_id: CHANNEL_ID,
              icon: 'ic_launcher',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
          },
          data: {
            exam_id: alert.examId,
            reason: alert.reason,
            link: alert.link ?? '',
          },
        },
      }),
    },
  );
  if (!res.ok) {
    throw new Error(`fcm send failed: ${res.status} ${await res.text()}`);
  }
}

async function sendOneSignal({ appId, restKey, alert }) {
  const res = await fetch('https://api.onesignal.com/notifications', {
    method: 'POST',
    headers: {
      authorization: `Key ${restKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      app_id: appId,
      // Same tag the app writes when a bell is switched on.
      filters: [{ field: 'tag', key: alert.topic, value: 'true' }],
      headings: { en: alert.title },
      contents: { en: alert.body },
      android_channel_id: CHANNEL_ID,
      data: { exam_id: alert.examId, reason: alert.reason, link: alert.link ?? '' },
    }),
  });
  if (!res.ok) {
    throw new Error(
      `onesignal send failed: ${res.status} ${await res.text()}`,
    );
  }
}

function readServiceAccount(env) {
  const raw = env.FCM_SERVICE_ACCOUNT_JSON;
  if (!raw || !raw.trim()) return null;
  const text = raw.trim().startsWith('{')
    ? raw
    : Buffer.from(raw, 'base64').toString('utf8');
  const parsed = JSON.parse(text);
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error(
      'FCM_SERVICE_ACCOUNT_JSON is missing client_email/private_key/project_id',
    );
  }
  return parsed;
}

export async function dispatch({
  oldFeed,
  newFeed,
  env = process.env,
  log = console.log,
}) {
  const alerts = computeAlerts(oldFeed, newFeed);
  if (alerts.length === 0) {
    log('dispatch: nothing to notify');
    return { sent: 0, failed: 0, alerts: 0 };
  }

  let provider = 'none';
  let serviceAccount = null;
  const appId = (env.EV_ONESIGNAL_APP_ID ?? '').trim();
  const restKey = (env.EV_ONESIGNAL_REST_KEY ?? '').trim();

  try {
    serviceAccount = readServiceAccount(env);
  } catch (err) {
    log(`dispatch: ${err.message}`);
  }
  if (serviceAccount) provider = 'fcm';
  else if (appId && restKey) provider = 'onesignal';

  if (provider === 'none') {
    log(
      `dispatch: ${alerts.length} alert(s) ready but NO push credentials are ` +
        'configured (set FCM_SERVICE_ACCOUNT_JSON, or EV_ONESIGNAL_REST_KEY + ' +
        'EV_ONESIGNAL_APP_ID). Nothing was sent.',
    );
    for (const a of alerts.slice(0, 10)) {
      log(`  would send → [${a.topic}] ${a.title}: ${a.body}`);
    }
    return { sent: 0, failed: 0, alerts: alerts.length, provider };
  }

  let sent = 0;
  let failed = 0;
  for (const alert of alerts) {
    try {
      if (provider === 'fcm') {
        await sendFcm({ serviceAccount, alert });
      } else {
        await sendOneSignal({ appId, restKey, alert });
      }
      sent++;
      log(`sent via ${provider} → ${alert.topic}: ${alert.title}`);
    } catch (err) {
      failed++;
      log(`FAILED ${alert.topic}: ${err.message}`);
    }
  }
  return { sent, failed, alerts: alerts.length, provider };
}

// ----------------------------------------------------------------- CLI glue

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const isMain =
  process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop());

if (isMain) {
  const oldPath = arg('old');
  const newPath = arg('new', '../data/live_feed.json');
  if (!oldPath) {
    console.error('usage: dispatch_alerts.mjs --old <prev.json> [--new <feed>]');
    process.exit(2);
  }
  const oldFeed = JSON.parse(readFileSync(oldPath, 'utf8'));
  const newFeed = JSON.parse(readFileSync(newPath, 'utf8'));
  dispatch({ oldFeed, newFeed })
    .then((r) => {
      console.log(
        `dispatch done: provider=${r.provider} alerts=${r.alerts} sent=${r.sent} failed=${r.failed}`,
      );
      // A failed send must not fail the data pipeline: the snapshot is already
      // published, and the next run will see the same diff only if it changes
      // again. Loud, not red.
      process.exit(0);
    })
    .catch((err) => {
      console.error(`dispatch crashed: ${err.stack ?? err}`);
      process.exit(0);
    });
}
