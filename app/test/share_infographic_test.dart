import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/share_card/whatsapp_share_card_screen.dart';
import 'package:examvault/features/share_card/widgets/share_infographic.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The share card is the only part of the app that leaves the device as an image.
///
/// That makes its claims expensive: a screenshot forwarded into a 200-person
/// study group is read as fact, and cannot be corrected. Two failure modes are
/// pinned here — claiming a cut-off that was never published, and telling a
/// shortlisted candidate they are "SELECTED".
void main() {
  ShareCardData data({
    bool selected = true,
    String roll = '0801786',
    String headline = 'RESULT IS LIVE',
    String? pdfSize,
    String name = '',
  }) => ShareCardData(
    examName: 'Final Result: Combined Section Officers',
    headline: headline,
    subline: 'Official link & instant roll-number check',
    dateLine: '10 NOV 2026',
    rollNumber: roll,
    candidateName: name,
    selected: selected,
    shareUrl: 'https://examvault.example/v1/feed',
    officialUrl: 'https://www.upsc.gov.in/sites/default/files/example.pdf',
    pdfSizeLabel: pdfSize,
  );

  Future<void> pumpCard(WidgetTester tester, ShareCardData card) async {
    await tester.binding.setSurfaceSize(const Size(393, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: ShareInfographic(data: card)),
      ),
    );
    await tester.pump();
  }

  late Directory hiveDir;
  late Box<dynamic> cacheBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_share_card');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    cacheBox = await Hive.openBox<dynamic>(
      'share${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('the card never shows a cut-off it was not given', (
    tester,
  ) async {
    await pumpCard(tester, data());

    // The `cutoffs` field and its block were deleted outright: nothing in the
    // feed ever populated them, so the only state the widget could render was
    // a fabricated one.
    expect(find.textContaining('CUT-OFF'), findsNothing);
    // The one fact we do have must still be there.
    expect(find.textContaining('0801786'), findsOneWidget);
  });

  testWidgets('the PDF size survives a share with no roll', (tester) async {
    // Bug: pdfSizeLabel lived inside _RollBlock, which only renders when a
    // roll number exists — so a radar-only share (or one with the roll hidden)
    // dropped the single feed fact the card had been given.
    await pumpCard(tester, data(roll: '', pdfSize: '18.4 MB'));
    expect(find.textContaining('0801786'), findsNothing);
    expect(
      find.textContaining('18.4 MB'),
      findsOneWidget,
      reason: 'the footer meta line renders whenever the feed gave a size',
    );

    // And it still renders next to a roll.
    await pumpCard(tester, data(pdfSize: '18.4 MB'));
    expect(find.textContaining('0801786'), findsOneWidget);
    expect(find.textContaining('18.4 MB'), findsOneWidget);
  });

  testWidgets('the alert strip meets the 4.5:1 white-text contrast floor', (
    tester,
  ) async {
    // Bug: white on the old #F05252 measured 3.48:1 and the date at 86% alpha
    // on #DC2626 measured 3.89:1 — both under the 4.5:1 AA floor, in an image
    // the recipient can neither re-theme nor enlarge. The strip now runs
    // #DC2626 (white 4.83:1) → #B91C1C (white 5.9:1) with a full-opacity date.
    expect(ShareInfographic.alertRedStart, const Color(0xFFDC2626));
    expect(ShareInfographic.alertRedEnd, const Color(0xFFB91C1C));

    await pumpCard(tester, data());

    final strip = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .firstWhere((g) => g.colors.contains(ShareInfographic.alertRedStart));
    expect(strip.colors, [
      ShareInfographic.alertRedStart,
      ShareInfographic.alertRedEnd,
    ]);

    final date = tester.widget<Text>(find.text('10 NOV 2026'));
    expect(
      date.style?.color,
      Colors.white,
      reason: 'the date must be full-opacity white — 86% alpha was 3.89:1',
    );
  });

  testWidgets('a shortlisted roll is not labelled SELECTED', (tester) async {
    await pumpCard(tester, data());

    expect(
      find.textContaining('SELECTED'),
      findsNothing,
      reason:
          'most indexed lists are shortlists for the next stage, not final '
          'merit lists — "SELECTED" would be a false hope',
    );
    expect(find.textContaining('IN THE LIST'), findsOneWidget);
  });

  testWidgets('an unverified roll is not presented as found', (tester) async {
    await pumpCard(tester, data(selected: false));

    expect(find.text('YOUR ROLL'), findsOneWidget);
    expect(find.textContaining('IN THE LIST'), findsNothing);
  });

  testWidgets('hiding the roll keeps the rest of the card intact', (
    tester,
  ) async {
    final hidden = data().copyWith(rollNumber: '', selected: false);
    await pumpCard(tester, hidden);

    expect(find.textContaining('0801786'), findsNothing);
    // The card still communicates that a result exists and where to look.
    expect(find.text('RESULT IS LIVE', findRichText: true), findsWidgets);
    // With an app URL configured the bar shows that (in the brand row and the
    // CTA bar); otherwise the official one.
    expect(find.textContaining('examvault.example'), findsWidgets);
  });

  testWidgets('the card offers no button it cannot honour', (tester) async {
    await pumpCard(tester, data());

    // The card is exported as a PNG. A bar reading "Check your roll number"
    // looks tappable and is not, so it must show the destination instead.
    expect(
      find.textContaining('Check your roll number'),
      findsNothing,
      reason: 'nothing on an exported image can be tapped',
    );
    expect(
      find.text('examvault.example'),
      findsOneWidget,
      reason: 'the bar shows the host, so a screenshot still says where to go',
    );
  });

  test('the card falls back to the official link when there is no app URL', () {
    final officialOnly = data().copyWith(shareUrl: null);
    expect(officialOnly.link, officialOnly.officialUrl);
  });

  testWidgets('the bar shows the host alone, not a 90-character PDF path', (
    tester,
  ) async {
    await pumpCard(tester, data().copyWith(shareUrl: null));

    expect(find.text('www.upsc.gov.in'), findsOneWidget);
    expect(
      find.textContaining('/sites/default/files'),
      findsNothing,
      reason: 'a long path truncates to noise on the card',
    );
  });

  test('a card with no app URL still offers the official link', () {
    // A disabled "Copy link" was the previous behaviour whenever no public web
    // base was configured — which is the default. The commission's own link is
    // real, openable, and strictly more useful than a dead tile.
    final officialOnly = data().copyWith(shareUrl: null);

    expect(
      officialOnly.link,
      'https://www.upsc.gov.in/sites/default/files/example.pdf',
    );
    expect(officialOnly.linkIsOfficial, isTrue);

    final appLink = data();
    expect(appLink.link, appLink.shareUrl);
    expect(
      appLink.linkIsOfficial,
      isFalse,
      reason: 'an app URL must not be labelled as the official one',
    );
  });

  testWidgets('the headline glyphs are not clipped by a short line box', (
    tester,
  ) async {
    await pumpCard(tester, data());

    // `height: 0.96` makes the line box shorter than the glyphs. `Text` defaults
    // to `TextOverflow.clip`, so the exported PNG showed "LIVE" with a flat,
    // sliced-off bottom. Every headline run must opt out of that clip.
    final headlineRuns = tester
        .widgetList<Text>(find.byType(Text))
        .where(
          (t) =>
              t.style?.fontSize == 38 &&
              (t.data == 'RESULT IS' || t.data == 'LIVE'),
        )
        .toList();

    expect(headlineRuns, isNotEmpty, reason: 'sanity: headline must be found');
    for (final run in headlineRuns) {
      expect(
        run.overflow,
        TextOverflow.visible,
        reason: '"${run.data}" would be cut off without this',
      );
    }
  });

  testWidgets('the alert strip says what the card actually is', (tester) async {
    // Bug: the strip was hardcoded to "RESULT IS LIVE", so an admit-card share
    // contradicted itself in the same image.
    await pumpCard(tester, data(headline: 'ADMIT CARD IS LIVE'));

    expect(find.text('ADMIT CARD IS LIVE'), findsOneWidget);
    expect(
      find.text('RESULT IS LIVE'),
      findsNothing,
      reason: 'an admit card must never be announced as a result',
    );
    expect(find.text('ADMIT CARD IS'), findsOneWidget);
  });

  testWidgets('the alert strip follows every non-result status', (
    tester,
  ) async {
    for (final headline in [
      'ANSWER KEY IS OUT',
      'LAST DATE IS NEAR',
      'UPDATE AWAITED',
    ]) {
      await pumpCard(tester, data(headline: headline));
      expect(
        find.text(headline),
        findsOneWidget,
        reason: '"$headline" must reach the strip',
      );
      expect(find.text('RESULT IS LIVE'), findsNothing);
    }
  });

  testWidgets('editing the caption survives a rebuild', (tester) async {
    // Bug: the caption was rewritten inside build(), and the TextField never
    // reported edits, so any rebuild silently replaced what the user typed.
    await tester.binding.setSurfaceSize(const Size(393, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final card = _savedCard();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          httpCacheBoxProvider.overrideWithValue(cacheBox),
          admitCardsProvider.overrideWith(() => _FakeAdmitCards([card])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const WhatsappShareCardScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('ADMIT CARD IS LIVE'), findsWidgets);

    await tester.tap(find.text('EDIT'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      'Custom caption for my group',
    );
    await tester.pump();

    // A rebuild that is not an exam change: the same radar row is selected.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WhatsappShareCardScreen)),
    );
    container.read(resultExamIdProvider.notifier).select(_radarRow());
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Custom caption for my group'),
      findsOneWidget,
      reason: 'a rebuild must not overwrite a caption the user edited',
    );
  });
  testWidgets('the student\'s own name renders on the card', (tester) async {
    await pumpCard(tester, data(name: 'Asha Verma'));
    expect(find.text('ASHA VERMA'), findsOneWidget);
    expect(find.text('0801786'), findsOneWidget);
    expect(find.text('YOUR ROLL · IN THE LIST'), findsOneWidget);
  });

  testWidgets('a hidden roll still shows the name, as CANDIDATE', (
    tester,
  ) async {
    await pumpCard(tester, data(name: 'Asha Verma', roll: ''));
    expect(find.text('ASHA VERMA'), findsOneWidget);
    expect(find.text('CANDIDATE'), findsOneWidget);
    expect(find.text('0801786'), findsNothing);
  });
}

class _FakeAdmitCards extends AdmitCardsNotifier {
  _FakeAdmitCards(this.cards);

  final List<AdmitCard> cards;

  @override
  Future<List<AdmitCard>> build() async => cards;
}

AdmitCard _savedCard() => AdmitCard(
  id: 'card-1',
  examId: 'upsc_ldce_2025',
  category: ExamCategory.upsc,
  examName: 'Combined Section Officers',
  conductingBody: 'UPSC',
  examCode: 'LDCE',
  rollNumber: '0801786',
  registrationId: 'R1',
  dobOrPortalPassword: '01/01/1990',
  centerCode: 'DL-01',
  centerAddress: 'New Delhi',
  gate: 'Gate 1',
  reportBy: '09:00 AM',
  examDate: DateTime(2026, 12, 1),
  shift: '10:00 AM',
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

LiveUpdate _radarRow() => LiveUpdate(
  examId: 'upsc_ldce_2025',
  category: ExamCategory.upsc,
  examName: 'Combined Section Officers',
  contextLine: 'Official PDF · upsc.gov.in',
  status: UpdateStatus.resultOut,
  publishedAt: DateTime(2026, 11, 10),
  officialPdf: 'https://www.upsc.gov.in/sites/default/files/example.pdf',
);
