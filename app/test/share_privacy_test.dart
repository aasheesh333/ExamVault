import 'dart:io';

import 'package:examvault/features/share_card/whatsapp_share_card_screen.dart';
import 'package:examvault/features/share_card/widgets/share_infographic.dart';
import 'package:examvault/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// Two regressions from the audit, pinned.
///
/// 1. The privacy switch hid the roll number from the exported *image* but not
///    from the shared *caption* once the caption had been edited — leaking
///    "Roll 2201098765 · in the published list" to a 200-person study group.
/// 2. The exported PNG inherited the sender's accessibility text scale, so at
///    2.0x the "viral card" doubled in height and blew its size contract.
void main() {
  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_share_privacy');
    Hive.init(hiveDir.path);
    // matrix.dart's contract: load the fonts once from setUpAll, on the real
    // event loop. Inside a testWidgets body the load runs under the fake
    // clock, and the *second* pumpMatrix in a file then awaits a future whose
    // completion was scheduled in the first test's dead zone — a hang.
    await loadMatrixFonts();
  });

  setUp(() async {
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('hiding the roll scrubs an edited caption too', (tester) async {
    await pumpMatrix(
      tester,
      const WhatsappShareCardScreen(),
      matrixPoints[1],
      env: env,
      cards: [matrixCard(roll: '2201098765', candidateName: 'Asha Verma')],
    );

    // Edit the caption, so `_captionTouched` freezes auto-sync.
    await tester.tap(find.text('EDIT'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byType(TextField).last,
      'Alhamdulillah! Check yours on ExamVault',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('DONE'));
    await tester.pump(const Duration(milliseconds: 200));

    // Precondition: the edited caption is what's shown (auto-sync frozen),
    // while the generated default — containing the roll — is what a share
    // would fall back to if the caption were ever empty.
    expect(
      _allText(tester).any((t) => t.contains('Alhamdulillah')),
      isTrue,
      reason: 'the edited caption must be visible before the toggle',
    );

    // Flip the privacy switch off.
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pump(const Duration(milliseconds: 400));
    // One more frame: the caption re-sync runs in a post-frame callback, which
    // marks the preview dirty for the *next* frame. (In production that is a
    // 16ms delay; here, one extra pump.)
    await tester.pump();

    final texts = _allText(tester);
    expect(
      texts.any((t) => t.contains('2201098765')),
      isFalse,
      reason:
          'the roll must not survive anywhere — neither on the card nor '
          'in the caption — once the user hides it. The shared text used to '
          'keep the generated "Roll … · in the published list" line even '
          'though the image scrubbed it.',
    );
    final caption = texts.where((t) => t.startsWith('🚨')).toList();
    expect(
      caption,
      isNotEmpty,
      reason: 'toggling privacy must regenerate the caption from scrubbed data',
    );
    // The name is the student's identity, not a secret: hiding the roll keeps
    // it on the card and in the caption.
    expect(texts.any((t) => t.contains('ASHA VERMA')), isTrue);

    await disposeMatrix(tester);
  });

  testWidgets('turning the roll back on keeps an edited caption verbatim', (
    tester,
  ) async {
    // The OFF direction scrubs the caption — privacy outranks the edit. But
    // the old code reset "touched" in BOTH directions, so toggling back ON
    // destroyed whatever the user had written and re-inserted the generated
    // "Roll …" line they may have deliberately removed. ON has nothing to
    // scrub: the user's text must survive exactly as written.
    await pumpMatrix(
      tester,
      const WhatsappShareCardScreen(),
      matrixPoints[1],
      env: env,
      cards: [matrixCard(roll: '2201098765')],
    );

    // OFF scrubs the caption back to generated (privacy wins, pinned above).
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // While hidden, the user writes their own caption.
    await tester.tap(find.text('EDIT'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byType(TextField).last,
      'Result is out — card attached, no roll from me.',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('DONE'));
    await tester.pump(const Duration(milliseconds: 200));

    // ON again.
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final texts = _allText(tester);
    expect(
      texts.any(
        (t) => t.contains('Result is out — card attached, no roll from me.'),
      ),
      isTrue,
      reason: 're-enabling the roll must not rewrite the user\'s own caption',
    );
    expect(
      texts.any((t) => t.contains('Roll 2201098765')),
      isFalse,
      reason: 'the generated roll line must not be re-added to the caption',
    );
    expect(
      texts.any((t) => t == '2201098765'),
      isTrue,
      reason: 'the card itself shows the roll again once the switch is ON',
    );

    await disposeMatrix(tester);
  });

  testWidgets('an untouched caption regenerates in both toggle directions', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      const WhatsappShareCardScreen(),
      matrixPoints[1],
      env: env,
      cards: [matrixCard(roll: '2201098765')],
    );

    // The generated caption carries the roll line while the switch is on.
    expect(
      _allText(tester).any((t) => t.contains('Roll 2201098765')),
      isTrue,
      reason: 'sanity: the untouched caption is generated from full data',
    );

    // OFF: regenerated from scrubbed data — the roll survives nowhere.
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      _allText(tester).any((t) => t.contains('2201098765')),
      isFalse,
      reason: 'an untouched caption must track the privacy switch',
    );

    // ON: regenerated from roll-bearing data.
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final texts = _allText(tester);
    expect(texts.any((t) => t.contains('Roll 2201098765')), isTrue);
    expect(
      texts.any((t) => t == '2201098765'),
      isTrue,
      reason: 'and the card shows it again too',
    );

    await disposeMatrix(tester);
  });

  testWidgets('the exported card ignores the device text scale', (
    tester,
  ) async {
    const data = ShareCardData(
      examName: 'SSC CGL Tier-1 2026',
      headline: 'RESULT IS LIVE',
      subline: 'Official link & instant roll-number check',
      dateLine: '10 NOV 2026',
      rollNumber: '2201098765',
      selected: true,
      shareUrl: '',
      officialUrl: null,
      pdfSizeLabel: null,
    );

    Future<Size> sizeAt(double scale) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(393, 852),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(child: ShareInfographic(data: data)),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(ShareInfographic));
    }

    final at1 = await sizeAt(1.0);
    final at2 = await sizeAt(2.0);

    expect(
      at2.height,
      closeTo(at1.height, 0.5),
      reason:
          'the PNG geometry must not depend on the sender\'s '
          'accessibility setting — at 2.0x the card used to double in height',
    );
    expect(at2.width, closeTo(at1.width, 0.5));
  });
}

List<String> _allText(WidgetTester tester) => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .toList();
