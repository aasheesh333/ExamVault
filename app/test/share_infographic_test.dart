import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/features/share_card/widgets/share_infographic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The share card is the only part of the app that leaves the device as an image.
///
/// That makes its claims expensive: a screenshot forwarded into a 200-person
/// study group is read as fact, and cannot be corrected. Two failure modes are
/// pinned here — claiming a cut-off that was never published, and telling a
/// shortlisted candidate they are "SELECTED".
void main() {
  ShareCardData data({
    bool selected = true,
    Map<String, String>? cutoffs,
    String roll = '0801786',
  }) => ShareCardData(
    examName: 'Final Result: Combined Section Officers',
    headline: 'RESULT IS LIVE',
    subline: 'Official link & instant roll-number check',
    dateLine: '10 NOV 2026',
    rollNumber: roll,
    selected: selected,
    shareUrl: 'https://examvault.example/v1/feed',
    officialUrl: 'https://www.upsc.gov.in/sites/default/files/example.pdf',
    cutoffs: cutoffs,
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

  testWidgets('the card never shows a cut-off it was not given', (
    tester,
  ) async {
    await pumpCard(tester, data());

    expect(find.textContaining('CUT-OFF'), findsNothing);
    // The one fact we do have must still be there.
    expect(find.textContaining('0801786'), findsOneWidget);
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
}
