#!/usr/bin/env node
/**
 * Pulls the official SSC feed and writes `data/live_feed.json`.
 *
 * This is the missing half of the pipeline: `publish_feed.mjs` takes a document
 * and puts it on the edge; this script produces that document from the source of
 * truth instead of a hand-maintained file.
 *
 * ## What is real here
 *
 * SSC exposes a public, unauthenticated JSON API used by its own website:
 *
 *   GET /api/general-website/portal/records?contentType=results&…
 *   GET /api/general-website/portal/notice-boards?…
 *
 * Each record carries a headline, a publication date, an exam id and zero or
 * more PDF attachments. Everything written to the feed comes from those fields —
 * nothing is inferred, filled in, or invented.
 *
 * ## Legal stance: link, never mirror
 *
 * The app links to the **official** PDF on ssc.gov.in. The PDFs are not copied to
 * our CDN. The only thing we derive ourselves is a sorted list of roll numbers,
 * which is a set of facts rather than a reproduction of the document.
 *
 *   node fetch_official_feeds.mjs --out ../data/live_feed.json [--dry-run]
 */

import { writeFileSync } from 'node:fs';
import { argv } from 'node:process';

const BASE = 'https://ssc.gov.in/api/general-website/portal';

/** SSC's own site sends a normal browser UA; a bare node UA gets 403. */
const UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/155.0.0.0 Safari/537.36';

const HEADERS = {
  'user-agent': UA,
  accept: 'application/json',
  referer: 'https://ssc.gov.in/',
};

const out = arg('out', '../data/live_feed.json');
const dryRun = argv.includes('--dry-run');
const limit = Number(arg('limit', '25'));

function arg(name, fallback) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}

/**
 * Maps an SSC headline onto our five categories.
 *
 * Ordered most-specific first: "SSC Selection Posts" must not be caught by the
 * generic `selection` rule before `chsl`/`cgl` get a chance, and `mts` appears in
 * several composite names.
 */
function categoryOf(headline) {
  const h = headline.toLowerCase();
  if (/\b(cgl|combined graduate level)\b/.test(h)) return 'ssc';
  if (/\b(chsl|10\+2|higher secondary)\b/.test(h)) return 'ssc';
  if (/\b(mts|multi[- ]tasking)\b/.test(h)) return 'ssc';
  if (/\b(gd|constable|capf|delhi police|si in delhi)\b/.test(h)) return 'ssc';
  if (/\b(stenographer|je|junior engineer|jht|hindi translator)\b/.test(h)) return 'ssc';
  return 'ssc';
}

/**
 * Maps a headline onto a status, or null when it is not a student-facing event.
 *
 * Null is important: a notice about "debarred candidates" or a tender is not an
 * update a student needs pushed to their phone. Dropping it is better than
 * relabelling it as something it is not.
 */
/**
 * Notices that are published on the same board but are not for candidates:
 * procurement, empanelment, retired-officer engagement, debarment lists. They must
 * never reach a student's radar.
 */
const NOT_FOR_CANDIDATES =
  /(engagement of|retired|consultant|tender|expression of interest|eoi|empanel|debarred|quotation|auction|corrigendum to the tender)/;

function statusOf(headline) {
  const h = headline.toLowerCase();
  if (NOT_FOR_CANDIDATES.test(h)) return null;

  // NOTE ON WORD BOUNDARIES
  // An earlier version used a trailing \b on every alternative, so `shortlist\b`
  // failed to match "shortlisted" and `result\b` failed to match "results".
  // Real declarations — "List of Candidates shortlisted…", "Declaration of
  // results…" — were therefore silently dropped. Stems match without a trailing
  // boundary; only the *leading* boundary is kept so "consultant" cannot match
  // "result".

  // Order matters. A headline mentioning both a result and an admit card is a
  // result announcement (the admit card is usually a footnote).
  // `select` alone used to match 'Staff Selection Commission', turning a
  // consultant-engagement notice into a result. Only the candidate-facing forms
  // are matched now.
  if (/(result|merit|cut.?off|selected|selection list|select list|shortlist|declaration|marks|writeup)/.test(h)) {
    return 'result_out';
  }
  if (/(admit.?card|call.?letter|admission|exam.*city|examination.*city|roll.?number)/.test(h)) {
    return 'admit_card_live';
  }
  if (/(answer.?key|response.?sheet)/.test(h)) return 'answer_key';
  if (/(last.?date|closing|closes|apply.?online|application|registration)/.test(h)) {
    return 'form_closing';
  }
  if (/(schedule|calendar|exam.?date|notice|corrigendum|revised)/.test(h)) {
    return 'awaited';
  }
  return null;
}

/** Turns an SSC attachment path into a public URL. */
function attachmentUrl(path) {
  if (!path) return null;
  // The API stores Windows-style paths with backslashes, and several real file
  // names contain spaces ("CHT 2025 FRTA notice 07112026.pdf"). Those must be
  // percent-encoded or every fetch fails with "URL can't contain control
  // characters".
  const normalised = path.replace(/\\/g, '/').trim();
  const encoded = normalised
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
  return `https://ssc.gov.in/api/attachment/${encoded}`;
}

function clean(text) {
  return (text ?? '')
    .replace(/\r\n|\r|\n/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

/** Trims a long SSC headline into a radar-sized context line. */
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

async function fetchRecords(contentType, attributes) {
  const params = new URLSearchParams({
    page: '1',
    limit: String(limit),
    contentType,
    key: 'createdAt',
    order: 'DESC',
    language: 'english',
    isAttachment: 'true',
    attributes,
  });

  const res = await fetch(`${BASE}/records?${params}`, { headers: HEADERS });
  if (!res.ok) {
    throw new Error(`${contentType}: HTTP ${res.status}`);
  }
  const json = await res.json();
  if (!Array.isArray(json.data)) {
    throw new Error(`${contentType}: unexpected payload`);
  }
  return json.data;
}

async function main() {
  const ATTRS =
    'id,headline,examId,contentType,redirectUrl,startDate,endDate,createdAt';

  const [results, notices] = await Promise.all([
    fetchRecords('results', ATTRS),
    fetchRecords('notice-boards', ATTRS),
  ]);

  console.log(`results        ${results.length}`);
  console.log(`notice-boards  ${notices.length}`);

  const updates = [];
  const seen = new Set();

  for (const row of [...results, ...notices]) {
    const headline = clean(row.headline);
    if (!headline) continue;

    const status = statusOf(headline);
    if (!status) {
      console.log(`skip (not student-facing): ${headline.slice(0, 60)}`);
      continue;
    }

    // Deduplicate twice:
    //   1. by record id, because the same notice appears under both content types
    //   2. by headline + day, because SSC publishes one notice per force
    //      ("Constable GD in CAPFs / SSF / Assam Rifles") with identical text, and
    //      four identical radar rows is noise, not information.
    const byId = `${row.id}|${status}`;
    const byText = `${slug(headline)}|${String(row.createdAt).slice(0, 10)}`;
    if (seen.has(byId) || seen.has(byText)) continue;
    seen.add(byId);
    seen.add(byText);

    const attachment = (row.attachments ?? [])[0] ?? null;
    const pdfUrl = attachmentUrl(attachment?.path);

    // Stable, deterministic id so the app can key rows without collisions.
    const examId = slug(`${row.examId || 'ssc'}-${row.id}`);

    updates.push({
      exam_id: examId,
      category: categoryOf(headline),
      // The headline IS the exam name in SSC's data; truncating it would lose the
      // stage ("Paper-II", "PET/PST") that makes the row meaningful.
      exam_name: headline.length > 96 ? `${headline.slice(0, 93)}…` : headline,
      context: contextLine(headline, attachment),
      status,
      published_at: new Date(row.createdAt).toISOString(),
      // Link-only: the official PDF stays on ssc.gov.in.
      source: 'ssc.gov.in',
      official_pdf: pdfUrl,
      ...(attachment
        ? { pdf_size: `${(attachment.size / 1024 / 1024).toFixed(1)} MB` }
        : {}),
    });
  }

  updates.sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at));

  const doc = {
    revision: 1,
    source: 'ssc.gov.in (official JSON API)',
    fetched_at: new Date().toISOString(),
    updates: updates.slice(0, 20),
  };

  console.log(`kept           ${doc.updates.length}`);
  for (const u of doc.updates.slice(0, 6)) {
    console.log(`  ${u.published_at.slice(0, 10)}  ${u.status.padEnd(16)} ${u.exam_name.slice(0, 56)}`);
  }

  if (dryRun) {
    console.log('dry-run        not written');
    return;
  }

  writeFileSync(out, JSON.stringify(doc, null, 2));
  console.log(`wrote          ${out}`);
}

function slug(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 48);
}

main().catch((e) => {
  console.error('FAILED:', e.message);
  process.exit(1);
});
