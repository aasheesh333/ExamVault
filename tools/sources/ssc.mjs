/**
 * SSC — Staff Selection Commission (ssc.gov.in).
 *
 * Uses the public, unauthenticated JSON API that SSC's own website calls:
 *
 *   GET /api/general-website/portal/records?contentType=results&…
 *   GET /api/general-website/portal/records?contentType=notice-boards&…
 *
 * This is the only source with a real structured endpoint. Everything is taken
 * from `headline`, `createdAt` and `attachments`; nothing is inferred.
 */

import { clean, extractDates, extractFacts, slug, statusOf } from './lib.mjs';

const BASE = 'https://ssc.gov.in/api/general-website/portal';
const UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/155.0.0.0 Safari/537.36';

const ATTRS = 'id,headline,examId,contentType,redirectUrl,startDate,endDate,createdAt';

/** Turns an SSC attachment path into a public URL. */
function attachmentUrl(path) {
  if (!path) return null;
  // Windows-style separators, and real file names with spaces ("CHT 2025 FRTA
  // notice 07112026.pdf") which must be encoded or every fetch fails.
  const normalised = path.replace(/\\/g, '/').trim();
  const encoded = normalised
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
  return `https://ssc.gov.in/api/attachment/${encoded}`;
}

function contextLine(headline, attachment, sizeBytes) {
  const h = headline.toLowerCase();
  if (h.includes('admit card') || h.includes('exam city')) {
    return 'Admit card available on ssc.gov.in';
  }
  if (h.includes('result')) {
    if (sizeBytes) return `Official PDF · ${(sizeBytes / 1024 / 1024).toFixed(1)} MB`;
    return attachment ? 'Official PDF · ssc.gov.in' : 'Declared on ssc.gov.in';
  }
  if (h.includes('answer key')) return 'Answer key released';
  if (h.includes('last date') || h.includes('closing')) return 'Apply before the deadline';
  return 'Notice board · ssc.gov.in';
}

/**
 * The byte size of an attachment, or null when it is missing/garbage.
 *
 * SSC records occasionally arrive without `size`; `(undefined / 1048576).toFixed(1)`
 * is "NaN MB", which used to ship in the row context — and the throw from the
 * sibling `createdAt` bug took the ENTIRE source down for the run.
 */
function attachmentSize(attachment) {
  const size = attachment?.size;
  return typeof size === 'number' && Number.isFinite(size) && size > 0 ? size : null;
}

async function fetchRecords(contentType, limit) {
  const params = new URLSearchParams({
    page: '1',
    limit: String(limit),
    contentType,
    key: 'createdAt',
    order: 'DESC',
    language: 'english',
    isAttachment: 'true',
    attributes: ATTRS,
  });

  const res = await fetch(`${BASE}/records?${params}`, {
    headers: {
      'user-agent': UA,
      accept: 'application/json',
      referer: 'https://ssc.gov.in/',
    },
  });
  if (!res.ok) throw new Error(`${contentType}: HTTP ${res.status}`);
  const json = await res.json();
  if (!Array.isArray(json.data)) throw new Error(`${contentType}: unexpected payload`);
  return json.data;
}

export default {
  id: 'ssc',
  label: 'SSC',
  category: 'ssc',
  homepage: 'https://ssc.gov.in/',
  sourceName: 'ssc.gov.in',

  async run({ limit = 25 } = {}) {
    const [results, notices] = await Promise.all([
      fetchRecords('results', limit),
      fetchRecords('notice-boards', limit),
    ]);

    const rows = [];
    const seen = new Set();

    for (const record of [...results, ...notices]) {
      // One malformed record must not take down the whole source. A missing
      // `createdAt` used to throw (Invalid Date → toISOString) inside this
      // loop, which surfaced as "ssc unavailable" for the ENTIRE run — every
      // SSC row lost because of one bad record. Same shape as upsc.mjs: skip
      // the item, keep the source.
      try {
        const headline = clean(record.headline);
        if (!headline) continue;

        const status = statusOf(headline);
        if (!status) continue;

        const createdAt = new Date(record.createdAt);
        if (Number.isNaN(createdAt.getTime())) {
          throw new Error(`unparseable createdAt: ${JSON.stringify(record.createdAt)}`);
        }

        // Deduplicate twice: by record id (the same notice appears under both
        // content types) and by headline+day (SSC publishes one notice per force
        // with identical text, and four identical radar rows is noise).
        const byId = `${record.id}|${status}`;
        const byText = `${slug(headline)}|${createdAt.toISOString().slice(0, 10)}`;
        if (seen.has(byId) || seen.has(byText)) continue;
        seen.add(byId);
        seen.add(byText);

        const attachments = record.attachments ?? [];
        const attachment = attachments[0] ?? null;
        const sizeBytes = attachmentSize(attachment);

        // MULTI-PART LISTS: SSC splits big candidate lists across several
        // attachments. Indexing attachments[0] alone would publish a PARTIAL
        // index — and a partial index answers "NOT SELECTED" to every
        // candidate in parts 2+, the worst wrong verdict this product has.
        // So: keep the link (part 1 is a real official document), pause
        // indexing via `index_skipped`, and say so in the row context.
        // build_indexes.py honours the flag and never indexes the row.
        const multiPart = attachments.length > 1;
        const context = multiPart
          ? 'Multi-part list — indexing paused'
          : contextLine(headline, attachment, sizeBytes);

        rows.push({
          // The feed row id and the index id are the same string, so
          // `AppConfig.rollIndexPath(examId)` resolves with no mapping table.
          exam_id: slug(`${record.examId || 'ssc'}-${record.id}`),
          category: 'ssc',
          exam_name: headline.length > 96 ? `${headline.slice(0, 93)}…` : headline,
          context,
          status,
          // Only what the headline itself states; SSC's API carries no exam /
          // result / closing date fields, so anything else would be invented.
          ...extractDates({ headline, context }),
          // Vacancy / fee only when the notice itself states them.
          ...extractFacts({ headline, context }),
          published_at: createdAt.toISOString(),
          source: 'ssc.gov.in',
          source_id: 'ssc',
          // Link-only: the official PDF stays on ssc.gov.in.
          official_pdf: attachmentUrl(attachment?.path),
          ...(!multiPart && sizeBytes
            ? { pdf_size: `${(sizeBytes / 1024 / 1024).toFixed(1)} MB` }
            : {}),
          ...(multiPart
            ? { index_skipped: `multi-part list (${attachments.length} attachments)` }
            : {}),
        });
      } catch (e) {
        console.error(`  ssc: dropped malformed record ${record?.id ?? '?'}: ${e.message}`);
      }
    }

    return rows;
  },
};
