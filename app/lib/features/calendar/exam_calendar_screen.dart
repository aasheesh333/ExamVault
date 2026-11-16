import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/ev_haptics.dart';
import '../../providers/app_providers.dart';
import '../../providers/exam_calendar_provider.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';
import '../shell/root_shell.dart';
import 'exam_detail_sheet.dart';

/// The three date windows the calendar groups under.
///
/// The list is up to ~20 rows of nearest-first dates; without headings it is a
/// flat scroll with no way to tell "tomorrow" from "next month" except by
/// reading every countdown.
///
/// The labels name **rolling day counts**, not calendar periods. `NEXT 7 DAYS`
/// is literally `daysFrom(now) <= 7`: a heading that said "This week" would be
/// wrong for a Sunday date six days out, and would contradict the nearest-first
/// order the rows are already in.
enum CalendarBucket {
  next7Days('Next 7 days'),
  next30Days('Next 30 days'),
  later('Later');

  const CalendarBucket(this.label);

  final String label;
}

/// Which window [entry] falls in, from the same whole-day distance the row's
/// countdown already uses.
///
/// Day windows, not calendar weeks or months: the provider sorts nearest-first,
/// and a calendar week would file a date six days out on a Sunday under "Later"
/// while a date seven days out on a Monday sat under "This week" — a heading
/// that contradicts the order the rows are in. The same reasoning rules out
/// calendar months for the 30-day window.
CalendarBucket calendarBucketFor(CalendarEntry entry, DateTime now) {
  final days = entry.daysFrom(now);
  if (days <= 7) return CalendarBucket.next7Days;
  if (days <= 30) return CalendarBucket.next30Days;
  return CalendarBucket.later;
}

/// One non-empty bucket of the calendar.
class CalendarGroup {
  const CalendarGroup(this.bucket, this.entries);

  final CalendarBucket bucket;

  /// The provider's entries for this bucket, in the provider's order.
  final List<CalendarEntry> entries;
}

/// [entries] grouped into [CalendarBucket] order.
///
/// **Precondition:** [entries] is in non-decreasing date order — which is what
/// `examCalendarProvider` returns. The walk below appends per bucket, so it
/// preserves order *within* each bucket and only produces a correctly ordered
/// whole when the input is already bucket-sorted. It never re-sorts: grouping a
/// nearest-first list must not be a second ordering pass that could disagree
/// with the provider's.
///
/// Empty buckets are dropped rather than drawn as a heading over nothing.
List<CalendarGroup> groupCalendarEntries(
  List<CalendarEntry> entries,
  DateTime now,
) {
  final byBucket = <CalendarBucket, List<CalendarEntry>>{};
  for (final entry in entries) {
    byBucket.putIfAbsent(calendarBucketFor(entry, now), () => []).add(entry);
  }
  final groups = <CalendarGroup>[];
  for (final bucket in CalendarBucket.values) {
    final rows = byBucket[bucket];
    if (rows == null || rows.isEmpty) continue;
    groups.add(CalendarGroup(bucket, List.unmodifiable(rows)));
  }
  return groups;
}

/// One row of the grouped calendar list: a bucket heading, or a dated entry.
class _CalendarItem {
  const _CalendarItem.heading(this.bucket) : entry = null;
  const _CalendarItem.entry(this.entry) : bucket = null;

  final CalendarBucket? bucket;
  final CalendarEntry? entry;
}

/// Screen — Exam Calendar.
///
/// Answers one question: *what is coming up, for which exam, and how soon.*
///
/// The hard constraint is honesty. A calendar that guesses would be worse than
/// none — a student would take leave from work for a date nobody announced. So
/// this screen shows only dates the app can point at: the exam date printed on
/// the student's own admit card, and dates a commission stated in a notice.
/// Exams with no published date are simply absent, and the empty state says so
/// in those words.
class ExamCalendarScreen extends ConsumerStatefulWidget {
  const ExamCalendarScreen({super.key});

  @override
  ConsumerState<ExamCalendarScreen> createState() => _ExamCalendarScreenState();
}

class _ExamCalendarScreenState extends ConsumerState<ExamCalendarScreen> {
  /// One guard for the whole list: every row opens the same detail sheet, and
  /// only one can be on screen at a time. The modal barrier appears a frame
  /// after `showExamDetailSheet` is called, so without a synchronous flag a fast
  /// double tap on a row stacked a second sheet on the first.
  final _detailGuard = SheetOpenGuard();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final entries = ref.watch(examCalendarProvider);
    final now = DateTime.now();
    final alerts = ref.watch(examAlertsProvider);
    // Grouped, not re-sorted: the headings only break the provider's
    // nearest-first list into readable windows. Flattened into one lazy list so
    // the screen stays a single scrollable, with an 8px rhythm between rows.
    final items = [
      for (final group in groupCalendarEntries(entries, now)) ...[
        _CalendarItem.heading(group.bucket),
        for (final entry in group.entries) _CalendarItem.entry(entry),
      ],
    ];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _CalendarNavBar(),
            Expanded(
              child: entries.isEmpty
                  ? const _NoDates()
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        EvSpace.gutter,
                        EvSpace.x2,
                        EvSpace.gutter,
                        // Clear the floating tab bar: the bar's height
                        // follows the text scale, so this must be measured,
                        // not guessed.
                        EvChrome.bottomInset(context),
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final bucket = item.bucket;
                        // Spacing carries the grouping: rows keep the 8px
                        // rhythm, but a heading takes 16px above it and only
                        // the usual 8px below. With one uniform gap the
                        // heading sat equidistant from the previous group's
                        // last card and its own first row, and read as
                        // belonging to neither.
                        final gapAbove = i == 0
                            ? 0.0
                            : bucket != null
                            ? EvSpace.x4
                            : EvSpace.x2;
                        if (bucket != null) {
                          return Padding(
                            padding: EdgeInsets.only(top: gapAbove),
                            child: EvSectionHeader(
                              label: bucket.label,
                              // The list already sits inside the page gutter;
                              // the header's own gutter would indent the
                              // heading 16px past the cards it introduces.
                              padding: EdgeInsets.zero,
                            ),
                          );
                        }
                        final entry = item.entry!;
                        return Padding(
                          padding: EdgeInsets.only(top: gapAbove),
                          child: _EntryCard(
                            entry: entry,
                            now: now,
                            onOpen: () => _detailGuard.run<void>(
                              () => showExamDetailSheet(
                                context,
                                update: entry.update,
                                card: entry.card,
                              ),
                            ),
                            alerting: alerts.contains(entry.examId),
                            onAlertToggle:
                                entry.update == null ||
                                    !ref.watch(pushServiceProvider).canDeliver
                                ? null
                                : () =>
                                      _toggleAlert(context, ref, entry, alerts),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAlert(
    BuildContext context,
    WidgetRef ref,
    CalendarEntry entry,
    Set<String> current,
  ) async {
    EvHaptics.select();
    final next = await ref
        .read(examAlertsProvider.notifier)
        .toggle(entry.examId);
    final on = next.contains(entry.examId);
    if (on && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'We will alert you about ${entry.examName} — results, admit '
              'cards and dates.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.type.label.copyWith(color: Colors.white),
            ),
          ),
        );
    }
    await ref.read(pushServiceProvider).syncExamAlerts(next);
  }
}

class _CalendarNavBar extends ConsumerWidget {
  const _CalendarNavBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(examAlertsProvider);

    // A plain Row — no Stack overlay. The pill on the right is as wide as its
    // label ("ALERTS OFF" at 2.0x is ~150px on a 320px screen), so a title
    // laid over the whole bar painted underneath it and read
    // "Exam Calen…RTS OFF". Expanded gives the title exactly the space left
    // between the back button and the pill, and FittedBox keeps it whole.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
      child: Row(
        children: [
          const SizedBox(width: EvSpace.x2),
          EvIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            ghost: true,
            iconSize: 17,
            tooltip: 'Back to Home',
            onPressed: () =>
                ref.read(tabIndexProvider.notifier).select(EvTab.home),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Exam Calendar',
                    maxLines: 1,
                    style: context.type.navTitle,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: EvSpace.x4),
            child: _AlertCount(count: alerts.length),
          ),
        ],
      ),
    );
  }
}

class _AlertCount extends StatelessWidget {
  const _AlertCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final active = count > 0;

    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: (active ? p.accent : p.textTertiary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(EvRadius.pill),
        border: Border.all(
          color: (active ? p.accent : p.textTertiary).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            size: 12,
            color: active ? p.accentText : p.textTertiary,
          ),
          const SizedBox(width: 5),
          Text(
            // "1 exam" not "1 alerts".
            active ? '$count ${count == 1 ? 'exam' : 'exams'}' : 'ALERTS OFF',
            maxLines: 1,
            style: context.type.statusPill.copyWith(
              letterSpacing: 0.9,
              color: active ? p.accentText : p.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.now,
    required this.onOpen,
    required this.alerting,
    required this.onAlertToggle,
  });

  final CalendarEntry entry;
  final DateTime now;

  /// Opens the per-exam detail page (important dates, vacancy, fee, links) —
  /// the part a student needs after seeing the date.
  final VoidCallback onOpen;
  final bool alerting;
  final VoidCallback? onAlertToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final days = entry.daysFrom(now);
    final urgent = days <= 3;

    return EvCard(
      onTap: onOpen,
      // The card is a button, so it needs a name: without one TalkBack
      // announced a nameless button the size of the card (caught by the a11y
      // matrix, which checks exactly this).
      semanticLabel:
          '${entry.examName}. ${entry.kind.sentence} ${entry.dateLabel}. '
          'Open notice details.',
      padding: const EdgeInsets.fromLTRB(EvSpace.x4, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.examName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.tileTitle,
                ),
              ),
              if (onAlertToggle != null) ...[
                const SizedBox(width: 4),
                Semantics(
                  container: true,
                  button: true,
                  toggled: alerting,
                  label: alerting
                      ? 'Notifications on for ${entry.examName}. Turn off.'
                      : 'Notify me about ${entry.examName}.',
                  // The wrapper carries the action because `excludeSemantics`
                  // removes the InkResponse's; without it this bell was a button
                  // with no actions at all.
                  excludeSemantics: true,
                  onTap: onAlertToggle,
                  child: InkResponse(
                    onTap: onAlertToggle,
                    radius: 22,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          alerting
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          size: 17,
                          color: alerting ? p.accentText : p.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Wrap, not Row: three fixed-ish children (kind pill, date, countdown
          // chip) cannot coexist on a 320px card at 2.0x text, and a Row
          // pushed the countdown chip outside the card's rounded edge. Wrapping
          // moves the chip to its own line instead of clipping it.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _KindPill(kind: entry.kind),
              Text(
                entry.dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.monoMeta.copyWith(
                  color: p.textPrimary,
                  fontSize: 12,
                ),
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: (urgent ? p.danger : p.accent).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(EvRadius.badge),
                  border: Border.all(
                    color: (urgent ? p.danger : p.accent).withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.countdown(now),
                      maxLines: 1,
                      style: context.type.statusPill.copyWith(
                        fontSize: 11,
                        color: urgent ? p.dangerText : p.accentText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                entry.source == CalendarSource.admitCard
                    ? Icons.badge_outlined
                    : Icons.verified_outlined,
                size: 11,
                color: p.textTertiary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  // The provenance is the point: "your admit card" is a fact
                  // about you; "official notice" is a fact about the exam.
                  entry.source.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // No `copyWith`: microLabel is already 10.5px, so an override
                  // here only invited the two values to drift apart.
                  style: context.type.microLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.kind});

  final CalendarKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final color = switch (kind) {
      CalendarKind.exam => p.accent,
      CalendarKind.result => p.success,
      CalendarKind.deadline => p.warning,
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(EvRadius.badge),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kind.label,
            maxLines: 1,
            // No fontSize override: the statusPill token is the 11px floor, and
            // this row used to hardcode 10 — one of the two live-UI sites that
            // undercut the floor.
            style: context.type.statusPill.copyWith(
              color: switch (kind) {
                CalendarKind.exam => p.accentText,
                CalendarKind.result => p.successText,
                CalendarKind.deadline => p.warningText,
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest empty state.
///
/// It does not apologise and does not hint at dates it does not have: the
/// arithmetic of Indian exam calendars is that most notices do not state a
/// future date, and inventing one would be the single most harmful thing this
/// screen could do.
class _NoDates extends StatelessWidget {
  const _NoDates();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return EvCenteredScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_note_rounded, size: 40, color: p.textTertiary),
          const SizedBox(height: 16),
          Text('No dates announced yet', style: context.type.sectionTitle),
          const SizedBox(height: 6),
          Text(
            'Commissions state exam and result dates in their notices. When a '
            'notice does, the date appears here — we never guess one. A date '
            'from your own admit card always appears immediately.',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
          const SizedBox(height: 20),
          EvTextAction(
            label: 'Browse live results',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
