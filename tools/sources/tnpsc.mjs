/**
 * TNPSC — Tamil Nadu Public Service Commission (tnpsc.gov.in).
 *
 * Covers the `state_psc` category. The results page is an ASP.NET grid with
 * `rowspan` cells, so column indexes shift between rows; instead of counting
 * `<td>`s, this adapter keys on the URL path, which carries the semantics:
 *
 *   ../document/finalresult/16_2024_GROUP_VA_PUBLICATION_LIST.pdf
 *
 * Only final-result publication lists are taken — not the written-exam lookup
 * pages (`Checkresult.aspx?...`), which are per-candidate dynamic queries with no
 * document to index and no date to trust.
 */

import { absUrl, clean, getText, slug, toIsoDate } from './lib.mjs';

const BASE = 'https://www.tnpsc.gov.in';
const LIST = `${BASE}/English/Results.aspx`;

const NOTIF = /^\d{2}\/\d{4}$/;

/** Reads the grid, carrying `rowspan` context forward the way a human would. */
function parseRows(html) {
  const rows = [];
  let notif = null;
  let post = null;

  for (const m of html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const cells = [...m[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/gi)].map((c) => c[1]);

    // A new recruitment starts whenever the first cell holds a notification
    // number; the following rows repeat it via rowspan and are continuations.
    const first = clean(cells[0] ?? '');
    if (NOTIF.test(first)) {
      notif = first;
      post = clean(cells[1] ?? '') || post;
    } else if (notif && cells.length > 1) {
      // Continuation row for the same recruitment — keep the post name.
    }
    if (!notif) continue;

    for (const a of m[1].matchAll(/<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)) {
      const href = a[1];
      if (!/\/finalresult\//i.test(href)) continue;

      const label = clean(a[2]);
      const published = toIsoDate(label);
      if (!published || !post) continue;

      rows.push({
        exam_id: slug(`tnpsc-${notif}-${post}`),
        category: 'state_psc',
        exam_name: truncate(`TNPSC ${notif} · ${post}`),
        context: `Final result list · ${notif}`,
        status: 'result_out',
        published_at: published,
        source: 'tnpsc.gov.in',
        source_id: 'tnpsc',
        // Link-only: the PDF stays on tnpsc.gov.in.
        official_pdf: absUrl(LIST, href),
        official_page: null,
      });
    }
  }
  return rows;
}

function truncate(text, max = 96) {
  return text.length > max ? `${text.slice(0, max - 3)}…` : text;
}

export default {
  id: 'tnpsc',
  label: 'TNPSC',
  category: 'state_psc',
  homepage: BASE,
  sourceName: 'tnpsc.gov.in',

  async run({ limit = 20 } = {}) {
    const html = await getText(LIST);
    const rows = parseRows(html);

    // Newest first, and one row per recruitment: the page repeats a recruitment
    // across continuation rows, and the radar does not need the repetition.
    rows.sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at));
    const seen = new Set();
    const unique = [];
    for (const row of rows) {
      if (seen.has(row.exam_id)) continue;
      seen.add(row.exam_id);
      unique.push(row);
      if (unique.length >= limit) break;
    }
    return unique;
  },
};
