import 'dart:io';

import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
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
/// device/scale/theme points, and four mechanical assertions run each time:
///
///  * nothing throws (RenderFlex overflow included),
///  * no text is laid out off-screen or past the right edge,
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
  });

  final List<AdmitCard> cards;
  final bool hangVault;
  final bool failVault;
  final bool emptyFeed;
}
