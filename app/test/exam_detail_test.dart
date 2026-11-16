import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/calendar/exam_detail_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-exam detail page must show only what the notice states.
///
/// This is the aggregator-site feature done honestly: dates, vacancy and fee
/// appear when the commission printed them, and the sheet is simply shorter
/// when it did not. A "TBA" placeholder would be a promise the app cannot keep.
///
/// The sheet is also the place where two defects were visible to users: one URL
/// printed twice under two labels ("Official website" and "Apply online"), and
/// another exam's saved card drawn under this exam's headline. Both are covered
/// below, together with the accessibility trait and the 320@2.0x layout floor.
void main() {
  LiveUpdate row({
    String examId = 'ssc_cgl_2026',
    String examName = 'SSC CGL 2026',
    DateTime? examDate,
    DateTime? resultDate,
    DateTime? deadline,
    int? vacancy,
    String? fee,
    String? pdf = 'https://ssc.gov.in/list.pdf',
    String? page,
    UpdateStatus status = UpdateStatus.notification,
  }) => LiveUpdate(
    examId: examId,
    category: ExamCategory.ssc,
    examName: examName,
    contextLine: 'Official notice',
    status: status,
    publishedAt: DateTime(2026, 11, 10),
    examDate: examDate,
    resultDate: resultDate,
    deadline: deadline,
    vacancy: vacancy,
    fee: fee,
    officialPdf: pdf,
    officialPage: page,
  );

  AdmitCard card({
    String examId = 'ssc_cgl_2026',
    String examName = 'SSC CGL 2026',
    String rollNumber = '2201098765',
  }) => AdmitCard(
    id: 'card-$examId',
    examId: examId,
    category: ExamCategory.ssc,
    examName: examName,
    conductingBody: 'Staff Selection Commission',
    examCode: 'CGL · TIER-1',
    rollNumber: rollNumber,
    registrationId: 'SSC-CGL-26-441122',
    dobOrPortalPassword: '11/05/1998',
    centerCode: 'DL-07-2210',
    centerAddress: 'Sector 9, Rohini, New Delhi',
    gate: 'Gate 2',
    reportBy: '08:00 AM',
    examDate: DateTime(2026, 12, 1),
    shift: '10:00 AM – 11:00 AM',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  /// The bell section is hidden in tests anyway (push is not configured), but
  /// the sheet reads the alert set, so it must not fall through to the real
  /// Hive-backed notifier.
  Widget host({LiveUpdate? update, AdmitCard? card}) => ProviderScope(
    overrides: [examAlertsProvider.overrideWith(_EmptyAlerts.new)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showExamDetailSheet(context, update: update, card: card),
            child: const Text('open detail'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, Widget hostWidget) async {
    await tester.pumpWidget(hostWidget);
    await tester.pump();
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
  }

  /// Scrolls the sheet's own list to the bottom so lazily-built rows exist in
  /// the tree — an absent row must mean "not rendered", never "not scrolled
  /// into existence yet".
  Future<void> scrollToEnd(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  group('the notice model', () {
    test('a vacancy and fee survive parsing when present', () {
      final r = row(vacancy: 1234, fee: '₹100');
      expect(r.vacancy, 1234);
      expect(r.fee, '₹100');
    });

    test('absent facts stay null — never zero, never a placeholder', () {
      final r = row();
      expect(r.vacancy, isNull);
      expect(r.fee, isNull);
      expect(r.examDate, isNull);
      expect(r.resultDate, isNull);
      expect(r.deadline, isNull);
    });

    test('the new vacancy status has its own honest label', () {
      // "CLOSING SOON" on a notice published this morning is simply untrue.
      expect(UpdateStatus.notification.label, 'NEW VACANCY');
      expect(UpdateStatus.fromId('notification'), UpdateStatus.notification);
      expect(UpdateStatus.fromId('form_closing'), UpdateStatus.formClosing);
    });
  });

  group('status rendering', () {
    testWidgets('a new vacancy renders with the accent, not danger red', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          // The palette is a ThemeExtension: accentOn() reads context.ev.
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              final accent = UpdateStatus.notification.accentOn(context);
              final danger = UpdateStatus.formClosing.accentOn(context);
              expect(accent, isNot(danger));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('official links', () {
    testWidgets('one row per URL — no "Apply online" for a notice', (
      tester,
    ) async {
      await open(
        tester,
        host(
          update: row(
            page: 'https://ssc.gov.in/apply',
            status: UpdateStatus.notification,
          ),
        ),
      );
      await scrollToEnd(tester);

      expect(find.text('Official website'), findsOneWidget);
      // The model has no apply URL; the old row repeated officialPage under a
      // label that promised an application form the feed never carried.
      expect(find.text('Apply online'), findsNothing);
      // Two URLs (PDF + page) therefore two tiles, not three.
      expect(find.byIcon(Icons.open_in_new_rounded), findsNWidgets(2));
    });

    testWidgets('a form-closing notice does not grow a second apply row', (
      tester,
    ) async {
      await open(
        tester,
        host(
          update: row(
            page: 'https://ssc.gov.in/apply',
            status: UpdateStatus.formClosing,
          ),
        ),
      );
      await scrollToEnd(tester);

      expect(find.text('Official website'), findsOneWidget);
      expect(find.text('Apply online'), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNWidgets(2));
    });
  });

  group('the student\'s own card', () {
    testWidgets('a card for another exam is hidden and named in a note', (
      tester,
    ) async {
      await open(
        tester,
        host(
          update: row(),
          // The checker forwards its resolved card unconditionally and falls
          // back to cards.first when nothing matches the tapped row.
          card: card(
            examId: 'ssc_chsl_tier1_2026',
            examName: 'SSC CHSL Tier-1 2026',
            rollNumber: '3301098765',
          ),
        ),
      );
      await scrollToEnd(tester);

      // No foreign facts under this exam's headline.
      expect(find.text('YOUR CARD'), findsNothing);
      expect(find.text('Roll number'), findsNothing);
      expect(find.textContaining('3301098765'), findsNothing);
      expect(find.textContaining('Rohini'), findsNothing);
      expect(find.textContaining('08:00 AM'), findsNothing);
      // The card's date must not fill this notice's exam date either.
      expect(find.text('Exam date (your card)'), findsNothing);

      // Silently dropping it would look like a lost card, so the note keeps the
      // section header and says which exam the saved card belongs to.
      expect(find.text('YOUR SAVED CARD'), findsOneWidget);
      expect(
        find.textContaining('SSC CHSL Tier-1 2026'),
        findsOneWidget,
        reason: 'the note must name the exam the hidden card belongs to',
      );
      expect(find.textContaining('a different exam'), findsOneWidget);
    });

    testWidgets('an unnamed foreign card never renders a blank exam name', (
      tester,
    ) async {
      await open(
        tester,
        host(
          update: row(),
          // Older cards can carry an empty name; the note must not read
          // "Your saved card is for  — a different exam".
          card: card(examId: 'ssc_chsl_tier1_2026', examName: ''),
        ),
      );
      await scrollToEnd(tester);

      expect(find.text('YOUR SAVED CARD'), findsOneWidget);
      expect(
        find.textContaining('belongs to a different exam'),
        findsOneWidget,
      );
      expect(find.textContaining('is for  '), findsNothing);
    });

    testWidgets('a foreign card does not suppress the empty-notice line', (
      tester,
    ) async {
      await open(
        tester,
        host(
          // Nothing at all beyond the headline: both facts are true and both
          // belong on screen.
          update: row(pdf: null),
          card: card(examId: 'ssc_chsl_tier1_2026', examName: 'SSC CHSL'),
        ),
      );
      await scrollToEnd(tester);

      expect(find.text('YOUR SAVED CARD'), findsOneWidget);
      expect(
        find.textContaining('This notice states no dates, fee or vacancy'),
        findsOneWidget,
      );
    });

    testWidgets('a matching card is shown without the note', (tester) async {
      await open(tester, host(update: row(), card: card()));
      await scrollToEnd(tester);

      expect(find.text('YOUR CARD'), findsOneWidget);
      expect(find.text('Roll number'), findsOneWidget);
      expect(find.text('2201098765'), findsOneWidget);
      expect(find.textContaining('a different exam'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('a link tile is announced as a link, not a bare button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await open(tester, host(update: row(page: 'https://ssc.gov.in')));
        await scrollToEnd(tester);

        final node = tester.getSemantics(find.text('Official website'));
        expect(node.flagsCollection.isLink, isTrue);
        expect(node.flagsCollection.isButton, isFalse);
        // The child Text stays the name; a composed label would double-announce.
        expect(node.label, 'Official website');
        // A link trait without an action would be the same dead control the
        // excludeSemantics buttons were.
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a failed link copy reports inside the sheet, not below it', (
      tester,
    ) async {
      await loadFonts();
      failEveryLaunch(tester);
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await open(tester, host(update: row(page: 'https://ssc.gov.in')));

      // Geometry first, at the sheet's *initial* 72% height: the route
      // bottom-anchors its child. Wrapping the route child in a Scaffold
      // instead made it fill the route, so the surface sat at the top edge
      // with the dimmed page below and the barrier unreachable.
      final atRest = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(
        atRest.bottom,
        closeTo(852, 1),
        reason: 'the sheet must sit on the bottom edge of the screen',
      );
      expect(
        atRest.top,
        greaterThan(100),
        reason: 'the sheet must not be anchored to the top edge',
      );

      await scrollToEnd(tester);
      await tester.tap(find.text('Official website'));
      await tester.pumpAndSettle();

      final toast = find.textContaining('Official link copied');
      expect(toast, findsOneWidget);

      // Not merely hit-testable: through the root messenger the toast painted
      // behind the barrier, and through a top-anchored Scaffold it landed
      // ~190px *below* the sheet, floating over the dimmed page. Both are
      // invisible in practice, so assert containment in the sheet's rect.
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      final toastRect = tester.getRect(toast);
      expect(
        sheet.contains(toastRect.topLeft),
        isTrue,
        reason: 'toast top ${toastRect.top} is outside the sheet $sheet',
      );
      expect(
        sheet.contains(toastRect.bottomRight),
        isTrue,
        reason: 'toast bottom ${toastRect.bottom} is outside the sheet $sheet',
      );
    });
  });

  group('layout floor', () {
    testWidgets('renders at 320x568 @2.0x with no overflow', (tester) async {
      await loadFonts();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Dates relative to now: a fixed 2026-11-20 would turn "IN 4 DAYS" into
      // "PAST" the day after it passed, and this test must not be a time bomb.
      final soon = DateTime.now().add(const Duration(days: 4));
      final later = DateTime.now().add(const Duration(days: 20));
      final muchLater = DateTime.now().add(const Duration(days: 40));

      await open(
        tester,
        host(
          update: row(
            deadline: soon,
            examDate: later,
            resultDate: muchLater,
            vacancy: 17727,
            fee: '₹100',
            page: 'https://ssc.gov.in',
          ),
          card: card(),
        ),
      );

      // Measured probe pre-fix: "A RenderFlex overflowed by 10 pixels on the
      // right" on three date rows, the label collapsed to 0 and the countdown
      // lost its unit. Every pump along the way must stay clean.
      expect(tester.takeException(), isNull);

      // Bring the date rows into view and prove the countdown says what it
      // counts. Asserting `textContaining('IN ')` was not enough: "IN 4…" also
      // contains it. The paragraph must not have needed to ellipsise.
      await tester.scrollUntilVisible(
        find.text('Last date to apply'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);

      final countdowns = tester
          .renderObjectList<RenderParagraph>(find.textContaining('IN '))
          .toList();
      expect(countdowns, isNotEmpty, reason: 'no countdown was rendered');
      for (final paragraph in countdowns) {
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason:
              '"${paragraph.text.toPlainText()}" was ellipsised at 320@2.0x — '
              'the countdown lost its unit',
        );
      }

      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}

/// An alert set that does not reach for Hive — the sheet only needs a value.
class _EmptyAlerts extends ExamAlertsNotifier {
  @override
  Set<String> build() => const <String>{};
}

/// Every link launch fails, as on a de-Googled phone with no browser; the
/// platform channel answers the clipboard and haptic calls benignly.
void failEveryLaunch(WidgetTester tester) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/url_launcher'),
    (call) async => false,
  );
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

/// The bundled typefaces, so a 2.0x layout test measures real advances instead
/// of the square-glyph test font (the same reason sheets_test loads them).
Future<void> loadFonts() async {
  await (FontLoader('Plus Jakarta Sans')
        ..addFont(
          rootBundle.load('assets/google_fonts/PlusJakartaSans-Regular.ttf'),
        )
        ..addFont(
          rootBundle.load('assets/google_fonts/PlusJakartaSans-Medium.ttf'),
        )
        ..addFont(
          rootBundle.load('assets/google_fonts/PlusJakartaSans-SemiBold.ttf'),
        )
        ..addFont(
          rootBundle.load('assets/google_fonts/PlusJakartaSans-Bold.ttf'),
        ))
      .load();
  await (FontLoader('IBM Plex Mono')
        ..addFont(
          rootBundle.load('assets/google_fonts/IBMPlexMono-Regular.ttf'),
        )
        ..addFont(rootBundle.load('assets/google_fonts/IBMPlexMono-Medium.ttf'))
        ..addFont(
          rootBundle.load('assets/google_fonts/IBMPlexMono-SemiBold.ttf'),
        ))
      .load();
}
