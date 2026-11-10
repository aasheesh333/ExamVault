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

import { clean, slug, statusOf } from './lib.mjs';

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

function contextLine(headline, attachment) {
  const h = headline.toLowerCase();
  if (h.includes('admit card') || h.includes('exam city')) {
    return 'Admit card available on ssc.gov.in';
  }
  if (h.includes('result')) {
    return attachment
      ? `Official PDF · ${(attachment.size / 1024 / 1024).toFixed(1)} MB`
      : 'Declared on ssc.gov.in';
  }
  if (h.includes('answer key')) return 'Answer key released';
  if (h.includes('last date') || h.includes('closing')) return 'Apply before the deadline';
  return 'Notice board · ssc.gov.in';
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

    for (const row of [...results, ...notices]) {
      const headline = clean(row.headline);
      if (!headline) continue;

      const status = statusOf(headline);
      if (!status) continue;

      // Deduplicate twice: by record id (the same notice appears under both
      // content types) and by headline+day (SSC publishes one notice per force
      // with identical text, and four identical radar rows is noise).
      const byId = `${row.id}|${status}`;
      const byText = `${slug(headline)}|${String(row.createdAt).slice(0, 10)}`;
      if (seen.has(byId) || seen.has(byText)) continue;
      seen.add(byId);
      seen.add(byText);

      const attachment = (row.attachments ?? [])[0] ?? null;

      rows.push({
        // The feed row id and the index id are the same string, so
        // `AppConfig.rollIndexPath(examId)` resolves with no mapping table.
        exam_id: slug(`${row.examId || 'ssc'}-${row.id}`),
        category: 'ssc',
        exam_name: headline.length > 96 ? `${headline.slice(0, 93)}…` : headline,
        context: contextLine(headline, attachment),
        status,
        published_at: new Date(row.createdAt).toISOString(),
        source: 'ssc.gov.in',
        source_id: 'ssc',
        // Link-only: the official PDF stays on ssc.gov.in.
        official_pdf: attachmentUrl(attachment?.path),
        ...(attachment
          ? { pdf_size: `${(attachment.size / 1024 / 1024).toFixed(1)} MB` }
          : {}),
      });
    }

    return rows;
  },
};
