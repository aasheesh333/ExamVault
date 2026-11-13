/**
 * Regression fixtures for headline → status classification.
 *
 * The bug these pin: `RESULT_WORDS` matches "shortlist", so SSC's
 * Identity-Verification / Document-Verification notices ("…for the candidates
 * SHORTLISTED in…") were classified `result_out`. One was live in
 * data/live_feed.json (CHT 2025 FRTA IV notice) and queued for indexing — an
 * IV notice lists candidates SUMMONED, not SELECTED, so indexing it would
 * answer "NOT SELECTED" to everyone the notice never mentioned. Verification
 * notices must classify `admit_card_live`, and the check must run BEFORE the
 * result words.
 *
 * Run: node --test tools/test/
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { extractFacts, statusOf } from '../sources/lib.mjs';

// Real headlines (the first is verbatim from data/live_feed.json, 2026-11).
const VERIFICATION_FIXTURES = [
  'Identity Verification (IV) for the candidates shortlisted in FRTA of Combined Hindi Translator Examination, 2025',
  'Document Verification (DV) of the candidates shortlisted for various posts, SSC-CPO-2024',
  'Shortlisted candidates for Document Verification for the post of Stenographer',
  'DV schedule for shortlisted candidates of Constable (GD) Examination 2026',
  'Certificate Verification for the candidates shortlisted in Group IV Examination',
  'Physical Verification (PV) of shortlisted candidates — Phase-II',
];

test('IV/DV/shortlist-for-verification notices are admit_card_live, never result_out', () => {
  for (const headline of VERIFICATION_FIXTURES) {
    assert.equal(
      statusOf(headline),
      'admit_card_live',
      `misclassified verification notice: ${headline}`,
    );
  }
});

test('genuine result headlines are still result_out', () => {
  const results = [
    'Result of Combined Graduate Level Examination, 2025 (Tier-I)',
    'Written Result (with name): Civil Services (Main) Examination, 2026',
    'Final Result: Combined Section Officers Grade B LDCE-2024',
    'Cut-off marks for the candidates shortlisted for appointment',
    'Selection List of the candidates declared successful',
    'Marks of Recommended Candidates: Combined Geo-Scientist (Main) Examination',
    // The verification detector must NOT swallow ordinary results that merely
    // contain Roman numerals or a stage name.
    'Written Result Part IV — Engineering Services Examination 2026',
    'Result: Mains Examination Paper-I and Paper-II',
  ];
  for (const headline of results) {
    assert.equal(statusOf(headline), 'result_out', `misclassified result: ${headline}`);
  }
});

test('other milestone vocabulary is unaffected', () => {
  assert.equal(statusOf('Answer Key of the Tier-I Examination'), 'answer_key');
  assert.equal(statusOf('Admit Card for the Constable Examination 2026'), 'admit_card_live');
  assert.equal(
    statusOf('Medical Examination of the candidates declared successful'),
    'admit_card_live',
  );
  // Was asserted as 'form_closing'. It is not: a notice that opens an online
  // application has no deadline in its own wording, and labelling it CLOSING
  // SOON the day it is published is exactly the untruth the split fixes.
  assert.equal(
    statusOf('Notification for Online Application (Special Notice)'),
    'notification',
  );
  assert.equal(statusOf('Corrigendum regarding exam date'), 'awaited');
  assert.equal(statusOf('Engagement of retired consultants'), null);
  assert.equal(statusOf('Tender for hostel maintenance'), null);
  assert.equal(statusOf(''), null);
});

// ---------------------------------------------------------------------------
// New vacancy vs closing soon
//
// Every "Recruitment 2026" row used to wear a red CLOSING SOON pill on the day
// it was published. A fresh announcement is `notification`; only the notice's
// own deadline wording makes it `form_closing`.
// ---------------------------------------------------------------------------

test('a fresh recruitment announcement is a notification, not "closing soon"', () => {
  const fresh = [
    'SSC CGL 2026 Notification Out — Apply Online for 1234 Posts',
    'RRB NTPC 2026 Recruitment: Advertisement Released',
    'UPSC NDA 2026 Notification and Online Application',
  ];
  for (const headline of fresh) {
    assert.equal(
      statusOf(headline),
      'notification',
      `should be a new-vacancy notification: ${headline}`,
    );
  }
});

test('deadline wording makes it closing soon', () => {
  const closing = [
    'SSC CHSL 2026 — Last Date to Apply Online 30 November 2026',
    'IBPS PO Registration closes on 15 Nov 2026',
    'RRB Group D Apply Before 20 November 2026',
    'TNPSC CCSE-IV online application closing date extended',
  ];
  for (const headline of closing) {
    assert.equal(
      statusOf(headline),
      'form_closing',
      `should be closing soon: ${headline}`,
    );
  }
});

test('results and admit cards still outrank the application words', () => {
  assert.equal(statusOf('SSC CGL 2026 Final Result'), 'result_out');
  assert.equal(statusOf('SSC CGL 2026 Admit Card Download'), 'admit_card_live');
});

// ---------------------------------------------------------------------------
// Structured facts
// ---------------------------------------------------------------------------

test('vacancy is read only from an explicit post/vacancy form', () => {
  assert.equal(extractFacts({ headline: 'SSC CGL 2026 — Total Post : 1,234' }).vacancy, 1234);
  assert.equal(extractFacts({ headline: 'RRB NTPC 2026 for 500 posts' }).vacancy, 500);
  assert.equal(extractFacts({ headline: 'IBPS PO 2026 — 4130 vacancies' }).vacancy, 4130);
});

test('a year or a roll range is not a vacancy count', () => {
  assert.equal(extractFacts({ headline: 'SSC CGL 2026 Notification' }).vacancy, undefined);
  assert.equal(
    extractFacts({ headline: 'Roll 1234567890 selected' }).vacancy,
    undefined,
  );
  assert.equal(extractFacts({ headline: 'Part-IV examination' }).vacancy, undefined);
});

test('fee is read from a currency-marked amount only', () => {
  assert.equal(extractFacts({ headline: 'Application Fee: Rs. 100/-' }).fee, '₹100');
  assert.equal(extractFacts({ context: 'Examination Fee ₹ 250' }).fee, '₹250');
  assert.equal(extractFacts({ headline: 'Fee waiver for reserved category' }).fee, undefined);
});

test('facts are absent, not zero, when the notice says nothing', () => {
  const f = extractFacts({ headline: 'SSC CGL 2026 Result' });
  assert.equal(f.vacancy, undefined);
  assert.equal(f.fee, undefined);
});
