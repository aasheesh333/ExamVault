/**
 * Railways — RRB (rrbchennai.gov.in).
 *
 * ## Why this RRB and not the national portal
 *
 * Verified on 2026-11-10:
 *
 *   rrbapply.gov.in          NXDOMAIN
 *   rrbcdg.gov.in            TLS cert/altname failure, connections refused
 *   rrbahmedabad.gov.in      connect timeout
 *   rrbsecunderabad.gov.in   connect timeout
 *   indianrailways.gov.in    reachable, but the word "recruitment" appears
 *                            nowhere on the site — RRB notices are not there
 *   rrbchennai.gov.in        reachable, server-rendered, dated CEN notices
 *
 * Individual RRBs host the same CEN vocabulary nationwide (a CEN like 09/2026 is
 * a common exam, not a Chennai-only one), so this one board is a faithful window
 * onto railway recruitment. The row's `context` names the board so nothing
 * implies a nationwide count.
 *
 * Only the server-rendered homepage is used. The `/getdata` routes are
 * client-side SPA paths that return the same document for every query, so a
 * crawler cannot read them; the homepage list is the honest subset.
 */

import { absUrl, clean, getText, slug, toIsoDate } from './lib.mjs';

const BASE = 'https://rrbchennai.gov.in';

/** Maps the board's links onto our statuses. */
const STATUS_BY_LABEL = [
  [/exam results|selection list/i, 'result_out'],
  [/e-?call letter|city intimation|document verification|medical examination/i, 'admit_card_live'],
  [/objection tracker/i, 'answer_key'],
  [/application \(special notice\)/i, 'form_closing'],
  [/notification/i, 'awaited'],
];

function statusFor(label) {
  for (const [pattern, status] of STATUS_BY_LABEL) if (pattern.test(label)) return status;
  // "Mock Test Link" and menu chrome are not events; dropping them is correct.
  return null;
}

/**
 * Parses the CEN list.
 *
 * The anchor text is the factual part and it is fully structured:
 *
 *   (09/2026) Notification (09-11-2026)
 *   (06/2026) Application (Special Notice) (05-11-2026)
 */
function parseRows(html) {
  const rows = [];
  const anchor = /<a[^>]*href="([^"]*getdata[^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;

  for (const m of html.matchAll(anchor)) {
    const label = clean(m[2]);
    const status = statusFor(label);
    if (!status) continue;

    const cen = label.match(/\((\d{2}\/\d{4})\)/)?.[1] ?? null;
    const published = toIsoDate(label);
    if (!published) continue;

    const kind = label
      .replace(/^\(\d{2}\/\d{4}\)\s*/, '')
      .replace(/\(\d{1,2}[-/.]\d{1,2}[-/.]\d{4}\)\s*$/, '')
      .trim();

    rows.push({
      exam_id: slug(`rrb-cen-${cen ?? 'unknown'}-${kind}-${published.slice(0, 10)}`),
      category: 'railways',
      exam_name: truncate(
        `${cen ? `RRB CEN ${cen}` : 'RRB'} · ${kind || 'Notice'}`,
      ),
      context: `Railway Recruitment Board · ${shortDate(published)}`,
      status,
      published_at: published,
      source: 'rrbchennai.gov.in',
      source_id: 'railways',
      official_pdf: null,
      official_page: absUrl(BASE, m[1]),
    });
  }
  return rows;
}

function truncate(text, max = 96) {
  return text.length > max ? `${text.slice(0, max - 3)}…` : text;
}

function shortDate(iso) {
  return new Date(iso).toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  });
}

export default {
  id: 'railways',
  label: 'Railways (RRB)',
  category: 'railways',
  homepage: BASE,
  sourceName: 'rrbchennai.gov.in',

  async run({ limit = 20 } = {}) {
    const html = await getText(BASE);
    const rows = parseRows(html);

    // The homepage repeats menu entries; keep the newest per (CEN, kind, day).
    const seen = new Set();
    const unique = [];
    for (const row of rows.sort(
      (a, b) => Date.parse(b.published_at) - Date.parse(a.published_at),
    )) {
      if (seen.has(row.exam_id)) continue;
      seen.add(row.exam_id);
      unique.push(row);
      if (unique.length >= limit) break;
    }
    return unique;
  },
};
