/**
 * UPSC — Union Public Service Commission (upsc.gov.in).
 *
 * No API: `/jsonapi` 404s, so the "What's New" list is parsed directly. Each row
 * is a `views-row` block whose anchor text is the announcement; the date and the
 * attachment live on the detail page, which is fetched for every candidate row.
 *
 * UPSC publishes roll-list PDFs for written results (e.g.
 * `WR-CSM-2026-Engl-RollList-05112026.pdf`), so those rows can be indexed exactly
 * like SSC's.
 */

import { createHash } from 'node:crypto';

import { absUrl, clean, extractDates, getText, slug, statusOf, toIsoDate } from './lib.mjs';

const BASE = 'https://www.upsc.gov.in';
const LIST = `${BASE}/whats-new`;

/**
 * A collision-free exam_id for a "What's New" path.
 *
 * `slug()` truncates to 56 chars, and UPSC paths share long prefixes
 * (`/whats-new/written-result-with-name-combined-defence-services-…`), so
 * distinct notices used to collapse onto the SAME id: the snapshot shipped 8
 * of 12 fetched upsc rows, and because detail pages are fetched by a 4-worker
 * pool the surviving row was nondeterministic run to run. Suffixing a 6-char
 * hash of the FULL path makes the id unique while staying within the cap
 * (49 + 1 + 6 = 56).
 */
function examIdFor(pathname) {
  const hash = createHash('sha1').update(pathname).digest('hex').slice(0, 6);
  return `${slug(`upsc-${pathname}`).slice(0, 49)}_${hash}`;
}

/** Extracts (title, detailUrl) pairs from the "What's New" widget. */
function parseList(html) {
  const out = [];
  const anchor =
    /<a href="(\/whats-new\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  for (const m of html.matchAll(anchor)) {
    const title = clean(m[2]);
    if (title.length < 8) continue;
    out.push({ title, url: absUrl(BASE, m[1]) });
  }
  return out;
}

/** Reads the date and the primary PDF from a detail page. */
function parseDetail(html, url) {
  const text = clean(html);
  // The published date is the first real date on the page; UPSC prints it as
  // "06 Nov 2026". A footer link to an old year is the failure mode the year
  // floor in `toIsoDate` guards against.
  const published = toIsoDate(firstDate(text));

  const pdfs = [...html.matchAll(/href="([^"]+\.pdf)"/gi)]
    .map((m) => absUrl(url, m[1]))
    .filter(Boolean);
  const pdf = pdfs.find((p) => p.includes('/sites/default/files/')) ?? null;

  return { published, pdf, text };
}

function firstDate(text) {
  const m = text.match(
    /\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?,?\s+\d{4}\b/i,
  );
  return m ? m[0] : '';
}

export default {
  id: 'upsc',
  label: 'UPSC',
  category: 'upsc',
  homepage: BASE,
  sourceName: 'upsc.gov.in',

  async run({ limit = 12 } = {}) {
    const html = await getText(LIST);
    const items = parseList(html)
      .filter((it) => statusOf(it.title) !== null)
      .slice(0, limit);

    // Detail pages are fetched in a small pool: UPSC is a modest server and
    // hammering it would be both rude and slow.
    const rows = [];
    const queue = [...items];
    const workers = Array.from({ length: 4 }, async () => {
      for (;;) {
        const item = queue.shift();
        if (!item) return;
        let detail;
        try {
          detail = parseDetail(await getText(item.url), item.url);
        } catch {
          continue; // A single unreachable detail page must not lose the rest.
        }
        const status = statusOf(item.title);
        if (!status || !detail.published) continue;

        const context = detail.pdf
          ? 'Official PDF · upsc.gov.in'
          : 'Published on upsc.gov.in';

        rows.push({
          exam_id: examIdFor(decodeURIComponent(new URL(item.url).pathname)),
          category: 'upsc',
          exam_name: item.title.length > 96 ? `${item.title.slice(0, 93)}…` : item.title,
          context,
          status,
          // The detail page is official text; a date is used only when one of
          // the explicit trigger phrases precedes it.
          ...extractDates({ headline: item.title, context, text: detail.text }),
          published_at: detail.published,
          source: 'upsc.gov.in',
          source_id: 'upsc',
          // An HTML notice has no PDF; the official page is still the right link.
          official_pdf: detail.pdf,
          official_page: detail.pdf ? null : item.url,
        });
      }
    });
    await Promise.all(workers);

    return rows;
  },
};
