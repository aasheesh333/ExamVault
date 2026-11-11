/**
 * Shared helpers for the official-source adapters.
 *
 * ## The rule this file exists to enforce
 *
 * Every field written to the feed must come from a field on the source page.
 * There is no "guess the date", no "probably a result", no placeholder. When an
 * adapter cannot establish a fact it drops the row, and when it cannot reach the
 * source at all the orchestrator records that as an outage — an honest gap beats
 * a plausible invention, because a wrong "RESULT OUT" makes a student skip an
 * exam and there is no apology that fixes that.
 */

/** A normal desktop UA. Several of these sites 403 a bare `node` UA. */
export const UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/155.0.0.0 Safari/537.36';

const MONTHS = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};

export function clean(text) {
  return (text ?? '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&#8211;|&ndash;/gi, '\u2013')
    .replace(/&quot;/gi, '"')
    .replace(/&#039;|&#39;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\r\n|\r|\n/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

export function slug(text) {
  return String(text)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '')
    .slice(0, 56);
}

/** Resolves `href` against `base`, tolerating protocol-relative and absolute. */
export function absUrl(base, href) {
  if (!href) return null;
  try {
    return new URL(href.trim(), base).toString();
  } catch {
    return null;
  }
}

/**
 * Parses the date formats these sites actually use, and returns an ISO string.
 *
 * Supported (all real, all seen in the wild):
 *   `09-11-2026`, `09/11/2026`, `9 Nov 2026`, `09 November 2026`, `2026-11-09`
 *
 * Ambiguity policy: a slash/dash date with the first component <= 12 is read as
 * D/M/Y, because every one of these sources is Indian. `YYYY-MM-DD` is recognised
 * first so it is never misread.
 */
export function toIsoDate(input) {
  const text = clean(input);
  if (!text) return null;

  let m = text.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (m) return iso(Number(m[1]), Number(m[2]) - 1, Number(m[3]));

  m = text.match(/\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b/);
  if (m) return iso(Number(m[3]), Number(m[2]) - 1, Number(m[1]));

  // `04-Nov-2026` and `4 Nov 2026` both appear on IBPS and UPSC pages, so the
  // separators between the three parts are interchangeable.
  m = text.match(
    /\b(\d{1,2})\s*(?:st|nd|rd|th)?[\s\-/.]+([A-Za-z]{3,9})\.?,?[\s\-/.]+(\d{2,4})\b/,
  );
  if (m) {
    const month = MONTHS[m[2].slice(0, 3).toLowerCase()];
    // A two-digit year is real: IBPS prints "25-Nov-26".
    const year = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
    if (month !== undefined) return iso(year, month, Number(m[1]));
  }

  return null;
}

function iso(year, month, day) {
  if (!(year >= 2015 && year <= 2100)) return null;
  if (!(month >= 0 && month <= 11)) return null;
  if (!(day >= 1 && day <= 31)) return null;
  // Midnight UTC, NOT noon. A date-only notice ("09 Nov 2026") stamped at
  // 12:00Z is in the FUTURE for every refresh that runs between 00:00Z and
  // 12:00Z, and publish_feed.mjs (correctly) rejects any future
  // `published_at` — one same-day UPSC/TNPSC/RRB notice used to take the whole
  // document down with it for half the day. Midnight is always in the past by
  // the time the notice is fetched; app-side age labels ("2h old") are
  // unaffected in kind, only up to 12 h coarser on day one.
  return new Date(Date.UTC(year, month, day)).toISOString();
}

/**
 * Verification-stage notices: IV / DV / shortlist-for-verification.
 *
 * These LOOK like results — SSC's own wording is "Identity Verification (IV)
 * for the candidates shortlisted in …" — but the PDF lists candidates SUMMONED
 * to be verified, not candidates SELECTED. `RESULT_WORDS` matches
 * "shortlist", so without this earlier check the row became `result_out`, the
 * indexer queued it, and the checker would answer "NOT SELECTED" to everyone
 * the IV notice never mentioned. Classification order is the fix: a
 * verification notice is a call to appear → `admit_card_live`.
 *
 * Deliberately anchored on "verification" phrases rather than a bare /\biv\b/
 * or /\bdv\b/, so "Written Result Part IV" stays a result.
 */
const VERIFICATION_WORDS =
  /(identity verification|document verification|certificate verification|physical verification|verification \(|shortlisted[^.]{0,80}(verification|\bdv\b|\biv\b)|(?:\bdv\b|\biv\b)[^.]{0,80}shortlist)/;

/**
 * Milestone words that mean "a result exists", ordered so the most specific
 * decision wins. Shared by every adapter because the vocabulary is the same on
 * all of these boards.
 */
const RESULT_WORDS =
  /(result|merit|cut.?off|selected|selection list|select list|shortlist|declaration|marks|final list|writeup|waitlist|wait list)/;
const ADMIT_WORDS =
  /(admit.?card|call.?letter|hall.?ticket|e-?call|exam.?city|examination.?city|intimation|document verification|medical examination)/;
const KEY_WORDS = /(answer.?key|response.?sheet|objection tracker)/;
const FORM_WORDS =
  /(apply|application|registration|last.?date|closing|closes|online form|recruitment|notification|advertisement|advt)/;
const AWAIT_WORDS = /(schedule|calendar|notice|corrigendum|revised|exam date|indicative)/;

/**
 * Notices on these boards that are not for candidates at all. They must never
 * reach a student's radar: procurement, empanelment, debarment lists, tenders.
 */
export const NOT_FOR_CANDIDATES =
  /(engagement of|retired|consultant|tender|expression of interest|\beoi\b|empanel|debarred|quotation|auction|corrigendum to the tender|hostel|guest house|sports quota)/;

/**
 * Maps a headline onto our feed status, or `null` when it is not an event a
 * student needs to know about.
 */
export function statusOf(input) {
  const text = clean(input).toLowerCase();
  if (!text) return null;
  if (NOT_FOR_CANDIDATES.test(text)) return null;

  // BEFORE result words: "shortlisted for Document Verification" contains
  // "shortlist" and would otherwise ship as result_out (see VERIFICATION_WORDS).
  if (VERIFICATION_WORDS.test(text)) return 'admit_card_live';
  // A headline that mentions both a result and an admit card is a result
  // announcement: the admit card is a footnote to the outcome.
  if (RESULT_WORDS.test(text)) return 'result_out';
  if (KEY_WORDS.test(text)) return 'answer_key';
  if (ADMIT_WORDS.test(text)) return 'admit_card_live';
  if (FORM_WORDS.test(text)) return 'form_closing';
  if (AWAIT_WORDS.test(text)) return 'awaited';
  return null;
}

/**
 * Fetches a page as text with a hard timeout.
 *
 * `relaxedTls` exists because some of these sites serve an incomplete chain. It
 * is only ever passed for a source whose certificate has been inspected by hand,
 * and it is reported in the feed health block so the choice is visible.
 */
export async function getText(url, { timeoutMs = 25000, headers = {} } = {}) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: ac.signal,
      redirect: 'follow',
      headers: {
        'user-agent': UA,
        accept: 'text/html,application/xhtml+xml',
        'accept-language': 'en-IN,en;q=0.9',
        ...headers,
      },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

/** Reads a `?t=<epoch ms>` cache-buster, which several sites use as a timestamp. */
export function epochInQuery(url) {
  const m = String(url).match(/[?&]t=(\d{10,13})\b/);
  if (!m) return null;
  const n = Number(m[1]);
  const ms = n > 1e12 ? n : n * 1000;
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) return null;
  if (d.getUTCFullYear() < 2015 || d.getUTCFullYear() > 2100) return null;
  return d.toISOString();
}

/** Human size label from a byte count, e.g. `1.4 MB`. */
export function sizeLabel(bytes) {
  if (!bytes) return null;
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}
