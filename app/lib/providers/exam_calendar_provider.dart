import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/admit_card.dart';
import '../../domain/entities/exam_category.dart';
import '../../domain/entities/live_update.dart';
import 'app_providers.dart';

/// What a calendar entry is about.
enum CalendarKind {
  exam('EXAM DATE', 'Exam day'),
  result('RESULT DATE', 'Result'),
  deadline('LAST DATE', 'Application deadline');

  const CalendarKind(this.label, this.sentence);

  final String label;
  final String sentence;
}

/// Where a date came from. Both are facts; the difference is whose fact.
enum CalendarSource {
  /// The date printed on the student's own admit card — always trustworthy and
  /// specific to them.
  admitCard('Your admit card'),

  /// A date the commission stated in a notice, read by the pipeline.
  notice('Official notice');

  const CalendarSource(this.label);

  final String label;
}

/// One dated thing in the student's future.
class CalendarEntry {
  const CalendarEntry({
    required this.examId,
    required this.examName,
    required this.category,
    required this.date,
    required this.kind,
    required this.source,
    this.update,
    this.card,
  });

  final String examId;
  final String examName;
  final ExamCategory category;
  final DateTime date;
  final CalendarKind kind;
  final CalendarSource source;

  /// The feed row this came from, when there is one — carries the official
  /// link and the bell topic.
  final LiveUpdate? update;

  /// The saved card this came from, when there is one.
  final AdmitCard? card;

  /// Whole days from [now]'s local midnight. 0 is today, 1 tomorrow.
  int daysFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return day.difference(today).inDays;
  }

  String countdown(DateTime now) {
    final d = daysFrom(now);
    if (d == 0) return 'TODAY';
    if (d == 1) return 'TOMORROW';
    if (d == -1) return 'YESTERDAY';
    if (d < 0) return '${-d} DAYS AGO';
    return 'IN $d DAYS';
  }

  String get dateLabel {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year}';
  }
}

/// Every dated thing the app can prove, nearest first.
///
/// Two sources only:
///  * the student's own saved admit cards (a date they typed off their card),
///  * dates a commission stated in a notice, extracted by the pipeline.
///
/// Nothing is inferred. An exam with no published date simply has no entry —
/// that is why the calendar can be short, and why it is never wrong.
final examCalendarProvider = Provider<List<CalendarEntry>>((ref) {
  final feed = ref.watch(liveFeedProvider).value?.feed;
  final cards = ref.watch(admitCardsProvider).value ?? const <AdmitCard>[];
  final now = DateTime.now();

  final entries = <CalendarEntry>[];
  final seenKeys = <String>{};

  void add({
    required String examId,
    required String examName,
    required ExamCategory category,
    required DateTime? date,
    required CalendarKind kind,
    required CalendarSource source,
    LiveUpdate? update,
    AdmitCard? card,
  }) {
    if (date == null) return;
    // Hide things that are over: yesterday's exam date is not "upcoming".
    if (date.isBefore(DateTime(now.year, now.month, now.day))) return;
    // The same (exam, day, kind) can arrive from both a card and a notice;
    // the admit card wins because it is the student's own document.
    final key = '$examId|${date.toIso8601String()}|${kind.name}';
    if (!seenKeys.add(key)) return;
    entries.add(
      CalendarEntry(
        examId: examId,
        examName: examName,
        category: category,
        date: date,
        kind: kind,
        source: source,
        update: update,
        card: card,
      ),
    );
  }

  // The student's own documents first, so their fact owns the dedupe key.
  for (final card in cards) {
    add(
      examId: card.examId,
      examName: card.examName,
      category: card.category,
      date: card.examDate,
      kind: CalendarKind.exam,
      source: CalendarSource.admitCard,
      card: card,
    );
  }

  for (final update in feed?.updates ?? const <LiveUpdate>[]) {
    add(
      examId: update.examId,
      examName: update.examName,
      category: update.category,
      date: update.examDate,
      kind: CalendarKind.exam,
      source: CalendarSource.notice,
      update: update,
    );
    add(
      examId: update.examId,
      examName: update.examName,
      category: update.category,
      date: update.resultDate,
      kind: CalendarKind.result,
      source: CalendarSource.notice,
      update: update,
    );
    add(
      examId: update.examId,
      examName: update.examName,
      category: update.category,
      date: update.deadline,
      kind: CalendarKind.deadline,
      source: CalendarSource.notice,
      update: update,
    );
  }

  entries.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    // On one day, a student's own exam outranks a form deadline.
    return a.kind.index.compareTo(b.kind.index);
  });
  return List.unmodifiable(entries);
});
