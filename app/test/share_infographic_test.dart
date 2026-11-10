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
    // The card still communicates that a result exists and how to check it.
    expect(find.text('RESULT IS LIVE', findRichText: true), findsWidgets);
    expect(find.textContaining('Check your roll number'), findsOneWidget);
  });

  testWidgets('the headline accent word is not clipped', (tester) async {
    await pumpCard(tester, data());

    // The accent ("LIVE") used to be laid out inside a clipping `Stack` with a
    // tight line height, which sliced its descenders off the exported PNG.
    final stacks = tester.widgetList<Stack>(find.byType(Stack));
    expect(
      stacks.any((s) => s.clipBehavior == Clip.none),
      isTrue,
      reason: 'the accent word must be allowed to paint outside its line box',
    );
  });
}
