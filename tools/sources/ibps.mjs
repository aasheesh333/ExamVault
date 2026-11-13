/**
 * IBPS — Institute of Banking Personnel Selection (ibps.in).
 *
 * ## The certificate problem, and why it is not solved by turning verification off
 *
 * `www.ibps.in` serves only its leaf certificate. The intermediate
 * ("GlobalSign GCC R46 OV TLS CA 2025") is missing from the handshake, so every
 * client that does not already have it cached fails with `unknown CA` — curl and
 * Node both do; Chrome succeeds because it fetched the intermediate earlier.
 *
 * Disabling verification would make the pipeline trust *anyone* who can intercept
 * the connection, and this pipeline decides whether a student is told "RESULT
 * OUT". So instead the intermediate is pinned in `tools/certs/` (it is public
 * certificate data, published by GlobalSign) and passed as an extra CA alongside
 * the normal root store. The chain is then verified in full — a wrong or
 * substituted certificate still fails.
 *
 * If IBPS ever rotates to a different CA the fetch fails closed, the source is
 * reported `unavailable` in the feed health block, and nothing is published from
 * it. That is the correct failure mode; a silently trusted connection is not.
 */

import { readFileSync } from 'node:fs';
import { rootCertificates } from 'node:tls';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { clean, extractDates, statusOf, toIsoDate, UA } from './lib.mjs';

const BASE = 'https://www.ibps.in';
const LIST = `${BASE}/index.php/recruitment/`;

const CERT_FILE = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'certs',
  'globalsign-gcc-r46-ov-tls-ca-2025.pem',
);

/**
 * Minimal GET that can add a pinned intermediate to the trust chain.
 *
 * `www.ibps.in` intermittently aborts the handshake with `EPROTO` (its front end
 * rejects some TLS record batches). That is a transport hiccup, not a certificate
 * problem, so it is retried; a certificate failure (`UNABLE_TO_VERIFY_LEAF_SIGNATURE`,
 * `CERT_HAS_EXPIRED`, …) is thrown immediately, because retrying will not fix it
 * and we must not paper over a real trust failure.
 */
const RETRYABLE = new Set(['EPROTO', 'ECONNRESET', 'ETIMEDOUT']);

async function getWithChain(url, { timeoutMs = 25000, attempts = 3 } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await once(url, timeoutMs);
    } catch (e) {
      lastError = e;
      if (!RETRYABLE.has(e?.code)) throw e;
      await new Promise((r) => setTimeout(r, 400 * attempt));
    }
  }
  throw lastError;
}

/**
 * Loads the pinned intermediate + root store, FAILING CLOSED.
 *
 * The old code caught a missing/corrupt PEM and silently fell back to
 * `rootCertificates` alone — which is precisely the "unknown CA" outage the
 * pin exists to prevent, re-created by our own error handling. Now a missing
 * or non-PEM file throws with the filename in the message; the orchestrator
 * reports IBPS `unavailable` in the feed health block, which is the honest
 * failure mode.
 *
 * The pinned certificate (GlobalSign GCC R46 OV TLS CA 2025) EXPIRES
 * 2029-06-23 — see the rotation note in docs/DATA_PIPELINE.md.
 */
function loadTrustChain() {
  let pem;
  try {
    pem = readFileSync(CERT_FILE, 'utf8');
  } catch (e) {
    throw new Error(
      `pinned IBPS intermediate unreadable: ${CERT_FILE} (${e?.code ?? e?.message}). ` +
        'Refusing to fall back to the root store: ibps.in omits its intermediate, ' +
        'so that fallback reproduces the exact "unknown CA" outage the pin prevents. ' +
        'Restore the PEM — see docs/DATA_PIPELINE.md.',
    );
  }
  if (!/-----BEGIN CERTIFICATE-----/.test(pem)) {
    throw new Error(
      `pinned IBPS intermediate is corrupt (no PEM certificate found): ${CERT_FILE}`,
    );
  }
  return [pem, ...rootCertificates];
}

function once(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const ca = loadTrustChain();

    const req = https.get(
      new URL(url),
      {
        ca,
        headers: {
          'user-agent': UA,
          accept: 'text/html,application/xhtml+xml',
          'accept-language': 'en-IN,en;q=0.9',
        },
      },
      (res) => {
        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`HTTP ${res.statusCode}`));
          return;
        }
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (d) => (body += d));
        res.on('end', () => resolve(body));
      },
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error('timeout')));
    req.on('error', reject);
  });
}

/**
 * Parses the "Other Ongoing recruitments" grid.
 *
 * The page is Elementor flex divs, not a table:
 *
 *   <a href="<registration portal>">
 *     <div class="detail-section">
 *       <div class="detail-list">
 *         <div class="detail-first-heading">SBI</div>
 *         <div class="detail-second-heading">Recruitment of …</div>
 *         <div class="detail-heading"><div>04-Nov-2026</div><div>25-Nov-2026</div></div>
 */
function parseRows(html) {
  const out = [];
  const marker = '<div class="detail-section">';

  let index = html.indexOf(marker);
  while (index !== -1) {
    // The registration link wraps the block, so it is the nearest `<a href>` that
    // starts before this marker. Scanning backwards is more reliable than one
    // regex spanning the whole nested structure.
    const preceding = html.lastIndexOf('<a ', index);
    const href = preceding === -1
      ? null
      : html.slice(preceding, index).match(/href="([^"]+)"/)?.[1] ?? null;

    const next = html.indexOf(marker, index + marker.length);
    const block = html.slice(index, next === -1 ? html.length : next);

    const org = clean(
      block.match(/class="detail-first-heading"[^>]*>([\s\S]*?)<\/div>/i)?.[1] ?? '',
    );
    const title = clean(
      block.match(/class="detail-second-heading"[^>]*>([\s\S]*?)<\/div>/i)?.[1] ?? '',
    );
    const dates = [...block.matchAll(/<div>([^<]*)<\/div>/gi)]
      .map((d) => toIsoDate(d[1]))
      .filter(Boolean);

    if (title && dates.length > 0) {
      out.push({
        org,
        title,
        opens: dates[0],
        closes: dates[dates.length - 1],
        url: href,
      });
    }

    index = next;
  }
  return out;
}

export default {
  id: 'ibps',
  label: 'IBPS',
  category: 'banking',
  homepage: BASE,
  sourceName: 'ibps.in',
  // Surfaced in the feed health block: this source needs a pinned intermediate.
  note: 'TLS chain completed with a pinned GlobalSign intermediate',

  async run() {
    const html = await getWithChain(LIST);
    const rows = [];
    const today = Date.now();

    for (const item of parseRows(html)) {
      const org = item.org || 'IBPS';
      const label = `${org} — ${item.title}`;
      if (statusOf(label) === null && !/recruit/i.test(item.title)) continue;

      // `closes` is stamped at 00:00 UTC of the closing day (see lib.toIsoDate),
      // and registration normally stays open until 23:59 IST ON that day. Treat
      // the whole closing day as open, or the form flips to "closed" up to a
      // full day early.
      const closeMs = Date.parse(item.closes);
      const closeEndMs = Number.isFinite(closeMs) ? closeMs + 24 * 3600 * 1000 - 1 : NaN;
      const open = Number.isFinite(closeEndMs) && closeEndMs > today;

      const context = open
        ? `Registration closes ${placeDate(item.closes)}`
        : `Registration closed ${placeDate(item.closes)}`;

      // `closes` is a structured field on IBPS's own grid, so it WINS over
      // anything the text extraction might read out of the generated context.
      const dates = extractDates({ headline: label, context });
      const closesDay = item.closes?.slice(0, 10);
      if (closesDay) dates.deadline = closesDay;

      rows.push({
        exam_id: `ibps_${slugify(`${org}_${item.title}_${item.closes?.slice(0, 10) ?? ''}`)}`,
        category: 'banking',
        exam_name: label.length > 96 ? `${label.slice(0, 93)}…` : label,
        context,
        status: open ? 'form_closing' : 'awaited',
        ...dates,
        // The window's opening date is the only date IBPS publishes here.
        published_at: item.opens,
        // EXPLICIT expiry pinned to the end of the closing day. The default
        // form_closing TTL (7 days from published_at = opens, in both
        // publish_feed.mjs and the app's _defaultExpiry fallback) hid banking
        // rows WEEKS before registration actually closed. Both sides only
        // stamp a default when expires_at is absent, so emitting it here wins.
        ...(open && Number.isFinite(closeMs)
          ? { expires_at: new Date(closeEndMs - 999).toISOString() }
          : {}),
        source: 'ibps.in',
        source_id: 'ibps',
        official_pdf: null,
        official_page: item.url,
      });
    }

    return rows;
  },
};

function slugify(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 56);
}

function placeDate(isoDate) {
  const d = new Date(isoDate);
  if (Number.isNaN(d.getTime())) return 'soon';
  return d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  });
}
