import 'dart:typed_data';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/calendar/exam_calendar_screen.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/providers/exam_calendar_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The calendar must never invent a date.
///
/// These tests pin the two properties that make it trustworthy: only dates the
/// app can point at appear (a saved card, or a date a commission stated), and
/// everything already past is hidden — a calendar that keeps showing yesterday
/// is a calendar nobody believes.
void main() {
  late Box<dynamic> settingsBox;

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    settingsBox = await Hive.openBox<dynamic>('cal$stamp', bytes: Uint8List(0));
  });

  LiveUpdate row({
    String id = 'exam_a',
    String name = 'SSC CGL 2026',
    DateTime? examDate,
    DateTime? resultDate,
    DateTime? deadline,
  }) => LiveUpdate(
    examId: id,
    category: ExamCategory.ssc,
    examName: name,
    contextLine: 'Official notice',
    status: UpdateStatus.awaited,
    publishedAt: DateTime(2026, 11, 1),
    examDate: examDate,
    resultDate: resultDate,
    deadline: deadline,
  );

  AdmitCard card({
    String id = 'card_a',
    String examId = 'exam_a',
    String name = 'SSC CGL 2026',
    required DateTime examDate,
  }) => AdmitCard(
    id: id,
    examId: examId,
    category: ExamCategory.ssc,
    examName: name,
    conductingBody: 'Staff Selection Commission',
    examCode: 'CGL',
    rollNumber: '2201098765',
    registrationId: '',
    dobOrPortalPassword: '',
    centerCode: '',
    centerAddress: '',
    gate: '',
    reportBy: '',
    examDate: examDate,
    shift: '',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  ProviderContainer container({
    List<LiveUpdate> updates = const [],
    List<AdmitCard> cards = const [],
  }) {
    final c = ProviderContainer(
      overrides: [
        settingsBoxProvider.overrideWithValue(settingsBox),
        liveFeedProvider.overrideWith(() => _FakeFeed(updates)),
        admitCardsProvider.overrideWith(() => _FakeCards(cards)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Resolves the two async sources the calendar derives from. Without this the
  /// first read sees AsyncLoading (no value) and the calendar looks empty.
  Future<void> settle(ProviderContainer c) async {
    await c.read(liveFeedProvider.future);
    await c.read(admitCardsProvider.future);
  }

  group('examCalendarProvider', () {
    test('is empty when nothing is dated', () async {
      final c = container(updates: [row()]);
      await settle(c);
      expect(c.read(examCalendarProvider), isEmpty);
    });

    test('shows a date the commission stated', () async {
      final c = container(
        updates: [
          row(
            examDate: DateTime(2026, 12, 20),
            deadline: DateTime(2026, 11, 30),
          ),
        ],
      );
      await settle(c);
      final entries = c.read(examCalendarProvider);
      expect(entries.map((e) => e.kind), [
        CalendarKind.deadline,
        CalendarKind.exam,
      ]);
    });

    test('a saved card contributes its own exam date', () async {
      final c = container(cards: [card(examDate: DateTime(2026, 12, 1))]);
      await settle(c);
      final entries = c.read(examCalendarProvider);
      expect(entries, hasLength(1));
      expect(entries.single.source, CalendarSource.admitCard);
      expect(entries.single.kind, CalendarKind.exam);
    });

    test(
      'the admit card wins over a notice date for the same exam and day',
      () async {
        final day = DateTime(2026, 12, 1);
        final c = container(
          cards: [card(examDate: day)],
          updates: [row(examDate: day)],
        );
        await settle(c);
        final entries = c.read(examCalendarProvider);
        expect(entries, hasLength(1));
        expect(entries.single.source, CalendarSource.admitCard);
      },
    );

    test('past dates are hidden — including yesterday', () async {
      final now = DateTime.now();
      final c = container(
        updates: [
          row(examDate: now.subtract(const Duration(days: 1))),
          row(id: 'exam_b', examDate: now.add(const Duration(days: 3))),
        ],
      );
      await settle(c);
      final entries = c.read(examCalendarProvider);
      expect(entries, hasLength(1));
      expect(entries.single.examId, 'exam_b');
    });

    test('sorted nearest first, and today counts as zero', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final c = container(
        updates: [
          row(id: 'far', examDate: today.add(const Duration(days: 40))),
          row(id: 'today', examDate: today),
          row(id: 'soon', examDate: today.add(const Duration(days: 2))),
        ],
      );
      await settle(c);
      final entries = c.read(examCalendarProvider);
      expect(entries.map((e) => e.examId), ['today', 'soon', 'far']);
      expect(entries.first.countdown(now), 'TODAY');
      expect(entries[1].countdown(now), 'IN 2 DAYS');
    });
  });

  group('calendar grouping', () {
    CalendarEntry entry(String id, int daysFromNow) => CalendarEntry(
      examId: id,
      examName: 'Exam $id',
      category: ExamCategory.ssc,
      date: DateTime.now().add(Duration(days: daysFromNow)),
      kind: CalendarKind.exam,
      source: CalendarSource.notice,
    );

    test(
      'buckets are day windows, so a heading cannot contradict the order',
      () {
        final now = DateTime.now();
        expect(calendarBucketFor(entry('a', 0), now), CalendarBucket.thisWeek);
        expect(calendarBucketFor(entry('a', 7), now), CalendarBucket.thisWeek);
        expect(calendarBucketFor(entry('a', 8), now), CalendarBucket.thisMonth);
        expect(
          calendarBucketFor(entry('a', 30), now),
          CalendarBucket.thisMonth,
        );
        expect(calendarBucketFor(entry('a', 31), now), CalendarBucket.later);
      },
    );

    test('groups preserve the provider order and drop empty buckets', () {
      final now = DateTime.now();
      final entries = [
        entry('a', 0),
        entry('b', 2),
        entry('c', 8),
        entry('d', 30),
        entry('e', 31),
        entry('f', 45),
      ];
      final groups = groupCalendarEntries(entries, now);

      expect(groups.map((g) => g.bucket), [
        CalendarBucket.thisWeek,
        CalendarBucket.thisMonth,
        CalendarBucket.later,
      ]);
      expect(groups.expand((g) => g.entries).map((e) => e.examId), [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ]);

      // No entry in the next 8-30 days: the "This month" heading must not be
      // drawn over nothing.
      final sparse = groupCalendarEntries([entry('a', 1), entry('b', 40)], now);
      expect(sparse.map((g) => g.bucket), [
        CalendarBucket.thisWeek,
        CalendarBucket.later,
      ]);
    });
  });

  group('Dates tab grouping', () {
    Future<void> mountDates(WidgetTester tester, ProviderContainer c) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ExamCalendarScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The cards' own exam dates, in the order the provider sorts them.
    List<String> providerOrder(ProviderContainer c) =>
        c.read(examCalendarProvider).map((e) => e.examName).toList();

    testWidgets('headings are ordered and an empty group is not drawn', (
      tester,
    ) async {
      final c = container(
        cards: [
          card(
            id: 'card_a',
            examId: 'exam_a',
            name: 'This week',
            examDate: DateTime.now().add(const Duration(days: 2)),
          ),
          card(
            id: 'card_b',
            examId: 'exam_b',
            name: 'This month',
            examDate: DateTime.now().add(const Duration(days: 10)),
          ),
          card(
            id: 'card_c',
            examId: 'exam_c',
            name: 'Later',
            examDate: DateTime.now().add(const Duration(days: 40)),
          ),
        ],
      );
      await settle(c);
      await mountDates(tester, c);

      final week = tester.getRect(find.text('THIS WEEK'));
      final month = tester.getRect(find.text('THIS MONTH'));
      final later = tester.getRect(find.text('LATER'));
      expect(week.top, lessThan(month.top));
      expect(month.top, lessThan(later.top));

      // A second screen with nothing in the 8-30 day window: no heading.
      final sparse = container(
        cards: [
          card(
            id: 'card_a',
            examId: 'exam_a',
            name: 'This week',
            examDate: DateTime.now().add(const Duration(days: 2)),
          ),
          card(
            id: 'card_c',
            examId: 'exam_c',
            name: 'Later',
            examDate: DateTime.now().add(const Duration(days: 40)),
          ),
        ],
      );
      await settle(sparse);
      await mountDates(tester, sparse);

      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('LATER'), findsOneWidget);
      expect(find.text('THIS MONTH'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rows are in the provider order, unchanged', (
      tester,
    ) async {
      final c = container(
        cards: [
          // Inserted out of order on purpose: the provider sorts nearest-first,
          // and the grouping must not move anything again.
          card(
            id: 'card_c',
            examId: 'exam_c',
            name: 'Third',
            examDate: DateTime.now().add(const Duration(days: 40)),
          ),
          card(
            id: 'card_a',
            examId: 'exam_a',
            name: 'First',
            examDate: DateTime.now().add(const Duration(days: 2)),
          ),
          card(
            id: 'card_b',
            examId: 'exam_b',
            name: 'Second',
            examDate: DateTime.now().add(const Duration(days: 10)),
          ),
        ],
      );
      await settle(c);
      final order = providerOrder(c);
      expect(order, ['First', 'Second', 'Third']);

      await mountDates(tester, c);

      final rendered = [
        for (final name in order) (name, tester.getRect(find.text(name)).top),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      expect(rendered.map((e) => e.$1), order);
      expect(tester.takeException(), isNull);
    });

    testWidgets('each heading is exposed as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final c = container(
          cards: [
            card(
              id: 'card_a',
              examId: 'exam_a',
              name: 'This week',
              examDate: DateTime.now().add(const Duration(days: 2)),
            ),
            card(
              id: 'card_b',
              examId: 'exam_b',
              name: 'This month',
              examDate: DateTime.now().add(const Duration(days: 10)),
            ),
            card(
              id: 'card_c',
              examId: 'exam_c',
              name: 'Later',
              examDate: DateTime.now().add(const Duration(days: 40)),
            ),
          ],
        );
        await settle(c);
        await mountDates(tester, c);

        for (final label in ['THIS WEEK', 'THIS MONTH', 'LATER']) {
          final node = tester.getSemantics(find.text(label));
          final data = node.getSemanticsData();
          expect(
            data.flagsCollection.isHeader,
            isTrue,
            reason: '"$label" must be a heading a screen reader can jump to',
          );
          expect(data.label, label);
        }
      } finally {
        handle.dispose();
      }
    });
  });

  group('exam alert bells', () {
    test('toggling persists and un-toggling removes', () async {
      final c = container();
      await settle(c);
      final notifier = c.read(examAlertsProvider.notifier);

      final on = await notifier.toggle('exam_a');
      expect(on, {'exam_a'});
      expect(settingsBox.get('exam_alerts'), ['exam_a']);

      final off = await notifier.toggle('exam_a');
      expect(off, isEmpty);
      expect(settingsBox.get('exam_alerts'), isEmpty);
    });

    test('survives a restart (rebuilt from the settings box)', () async {
      final c = container();
      await settle(c);
      await c.read(examAlertsProvider.notifier).toggle('exam_b');

      // A new container over the same box is what a cold start sees.
      final restarted = container();
      await settle(restarted);
      expect(restarted.read(examAlertsProvider), {'exam_b'});
    });
  });
}

class _FakeFeed extends LiveFeedNotifier {
  _FakeFeed(this.updates);

  final List<LiveUpdate> updates;

  @override
  Future<LiveFeedSnapshot> build() async => LiveFeedSnapshot(
    feed: LiveFeed(generatedAt: DateTime.now(), updates: updates, revision: 1),
    source: FeedSource.network,
    fetchedAt: DateTime.now(),
  );
}

class _FakeCards extends AdmitCardsNotifier {
  _FakeCards(this.cards);

  final List<AdmitCard> cards;

  @override
  Future<List<AdmitCard>> build() async => cards;
}
