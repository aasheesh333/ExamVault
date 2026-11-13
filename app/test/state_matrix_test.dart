import 'dart:io';

import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/features/calendar/exam_calendar_screen.dart';
import 'package:examvault/features/command_center/command_center_screen.dart';
import 'package:examvault/features/result_checker/instant_result_checker_screen.dart';
import 'package:examvault/features/share_card/whatsapp_share_card_screen.dart';
import 'package:examvault/features/vault/admit_card_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// The state matrix.
///
/// Every screen is rendered across every state we know about, at eight
/// device/scale/theme points, and five mechanical assertions run each time:
///
///  * nothing throws (RenderFlex overflow included),
///  * the cell renders *something* — a minimum of visible text and tappable
///    widgets; a blank or stuck frame used to satisfy every other check
///    vacuously,
///  * no text is laid out off-screen — past either edge, or below/above the
///    fold when no scroll view can reveal it,
///  * no text is cut mid-word with `TextOverflow.clip`,
///  * every interactive element is >= 44px and actually receives a tap at its
///    centre (i.e. nothing is buried under the tab bar or the action dock).
///
/// This replaces "an agent looks at screenshots". A screenshot review found bugs
/// in a different place every round; a matrix cannot miss a combination.
void main() {
  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_matrix');
    Hive.init(hiveDir.path);
    // Real bundled fonts, loaded on the real event loop before any test's fake
    // clock exists (pumpMatrix also calls loadMatrixFonts, but the first load
    // belongs here — see the guard comment in matrix.dart).
    await loadMatrixFonts();
  });

  // One box pair for the whole suite. Opening per-test and closing in tearDown
  // hung the suite: Hive's close() waits on pending compaction, which never runs
  // inside the widget-test clock. Clearing the boxes between cases is enough.
  setUp(() async {
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    // No `env.close()`: Hive waits on pending compaction there and the widget-test
    // clock never advances it, so the suite hangs after a green run. The boxes live
    // in a temp dir that the OS reclaims.
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  final screens = <String, Widget Function()>{
    'Home': CommandCenterScreen.new,
    'Dates': ExamCalendarScreen.new,
    'Vault': AdmitCardDetailScreen.new,
    'Radar': InstantResultCheckerScreen.new,
    'Share': WhatsappShareCardScreen.new,
  };

  // Content states each screen must survive.
  final states = <String, _State>{
    'empty': const _State(),
    'oneCard': _State(cards: [matrixCard()]),
    'threeCards': _State(
      cards: [
        matrixCard(id: 'a', daysFromNow: 2),
        matrixCard(
          id: 'b',
          roll: '2201000002',
          daysFromNow: 6,
          examName: 'UPSC Civil Services (Preliminary) Examination 2027',
          category: ExamCategory.upsc,
        ),
        matrixCard(id: 'c', roll: '2201000003', daysFromNow: 40),
      ],
    ),
    'longContent': _State(
      cards: [
        matrixCard(
          id: 'long',
          examName:
              'Combined Higher Secondary Level Examination Tier 2 '
              'Regional Office Recruitment 2026',
          conductingBody: 'Staff Selection Commission, North Eastern Region',
          centerAddress:
              'Govt. Boys Senior Secondary School, Sector 9, Rohini, '
              'New Delhi 110085',
          roll: '12345678901234567890',
        ),
      ],
    ),
    'loadingVault': const _State(hangVault: true),
    'failedVault': const _State(failVault: true),
    'emptyFeed': const _State(emptyFeed: true),
    // The pass must stamp VERIFIED without growing a layout: the badge shares
    // rows with the roll number and the countdown at every scale.
    'verifiedCard': _State(cards: [matrixCard(verified: true)]),
    // Exam already taken: the countdown flips to a past tense and the pass
    // must not show a "report by" imperative for a finished exam.
    'pastExam': _State(cards: [matrixCard(id: 'past', daysFromNow: -2)]),
    // Exam *today*: the loudest countdown state, with the least margin for a
    // layout surprise.
    'todayExam': _State(cards: [matrixCard(id: 'today', daysFromNow: 0)]),
    // A card saved with almost nothing filled in, plus a non-empty checklist
    // (the checklist UI had never been exercised — matrixCard hardcoded it
    // empty). Empty optional fields must not render as "—" placeholders that
    // claim data, and the 24-char roll must still fit its box.
    'sparseFields': _State(
      cards: [
        matrixCard(
          id: 'sparse',
          shift: '',
          centerCode: '',
          examCode: '',
          registrationId: '',
          roll: '220109876543210987654321',
          checklist: const {
            ChecklistItem.admitCardPdf,
            ChecklistItem.passportPhotos,
          },
        ),
      ],
    ),
    // Every wire variant at once — awaited/answer_key pills, a page-only row,
    // pdf_size, a 4820ms mirror latency, an expired row, a 95-char Devanagari
    // name — and 60 rows, so long-list behaviour is measured, not assumed.
    'fullFeed': const _State(fullFeed: true, feedRows: 60),
  };

  for (final screen in screens.entries) {
    for (final state in states.entries) {
      for (final point in matrixPoints) {
        testWidgets(
          '${screen.key} / ${state.key} / $point',
          (tester) async {
            await pumpMatrix(
              tester,
              screen.value(),
              point,
              env: env,
              cards: state.value.cards,
              hangVault: state.value.hangVault,
              failVault: state.value.failVault,
              emptyFeed: state.value.emptyFeed,
              fullFeed: state.value.fullFeed,
              feedRows: state.value.feedRows,
            );
            expectScreenSane(tester, point);
            await disposeMatrix(tester);
          },
          // The hang case deliberately leaves a pending timer.
          timeout: const Timeout(Duration(seconds: 30)),
        );
      }
    }
  }
}

/// A content state.
class _State {
  const _State({
    this.cards = const <AdmitCard>[],
    this.hangVault = false,
    this.failVault = false,
    this.emptyFeed = false,
    this.fullFeed = false,
    this.feedRows = 4,
  });

  final List<AdmitCard> cards;
  final bool hangVault;
  final bool failVault;
  final bool emptyFeed;

  /// Feed carries every wire variant (statuses, page-only row, metadata,
  /// an expired row, Devanagari) — see [matrixFeedJson].
  final bool fullFeed;

  /// Rows to emit; beyond the hand-written samples the generator fills in.
  final int feedRows;
}
