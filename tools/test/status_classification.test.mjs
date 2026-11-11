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

import { statusOf } from '../sources/lib.mjs';

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
  assert.equal(statusOf('Notification for Online Application (Special Notice)'), 'form_closing');
  assert.equal(statusOf('Corrigendum regarding exam date'), 'awaited');
  assert.equal(statusOf('Engagement of retired consultants'), null);
  assert.equal(statusOf('Tender for hostel maintenance'), null);
  assert.equal(statusOf(''), null);
});
