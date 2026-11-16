import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../core/utils/ev_haptics.dart';
import '../../data/services/app_logger.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/live_update.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_surfaces.dart';
import '../../shared/widgets/status_pill.dart';

/// The per-exam detail page — the part aggregator sites get right.
///
/// A radar row answers "is there news?"; this answers the four questions a
/// student actually has next: **when is it, how many posts, what does it cost,
/// and where do I apply?**
///
/// The honesty rule is the same one the calendar runs on: every value here is
/// either the commission's own number/link or the student's own document. A
/// field the notice did not state is simply not drawn — no "TBA", no dash, no
/// guess. That is why the sheet can look short.
Future<void> showExamDetailSheet(
  BuildContext context, {
  LiveUpdate? update,
  AdmitCard? card,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExamDetailSheet(update: update, card: card),
  );
}

class _ExamDetailSheet extends ConsumerWidget {
  const _ExamDetailSheet({this.update, this.card});

  final LiveUpdate? update;
  final AdmitCard? card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final examId = update?.examId ?? card?.examId;
    final examName = update?.examName ?? card?.examName ?? 'Exam';
    final alerts = ref.watch(examAlertsProvider);
    final alerting = examId != null && alerts.contains(examId);

    final dates = <_DateRow>[
      if (update?.deadline != null)
        _DateRow('Last date to apply', update!.deadline!),
      if (update?.examDate != null) _DateRow('Exam date', update!.examDate!),
      if (update?.resultDate != null)
        _DateRow('Result date', update!.resultDate!),
      // The student's own document fills in a date the notice did not state.
      if (update?.examDate == null && card != null)
        _DateRow(
          'Exam date (your card)',
          card!.examDate,
          source: _DateSource.card,
        ),
    ];

    final links = <_LinkRow>[
      if (update?.officialPdf != null)
        _LinkRow(
          'Official notification (PDF)',
          update!.officialPdf!,
          Icons.picture_as_pdf_outlined,
        ),
      if (update?.officialPage != null)
        _LinkRow(
          'Official website',
          update!.officialPage!,
          Icons.account_balance_outlined,
        ),
      // "Apply online" is the same page as the notice for these boards; the
      // label is what a student is looking for, so say it when it is a form.
      if (update?.officialPage != null &&
          (update!.status == UpdateStatus.notification ||
              update!.status == UpdateStatus.formClosing))
        _LinkRow('Apply online', update!.officialPage!, Icons.edit_document),
    ];

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Semantics(
                      container: true,
                      header: true,
                      child: Text(
                        examName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.sectionTitle,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: SizedBox(
                        width: EvSize.minTapTarget,
                        height: EvSize.minTapTarget,
                        child: Center(
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  if (update != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: EvStatusPill.status(update!.status),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ---- Important dates ---------------------------------
                  if (dates.isNotEmpty) ...[
                    const EvSectionHeader(
                      label: 'Important dates',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    EvCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EvSpace.x4,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < dates.length; i++) ...[
                            if (i > 0) EvHairline(inset: 0),
                            _DateRowView(row: dates[i]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // The whole point: the student knows where each number
                      // came from.
                      // Provenance must be exact: saying "and the official
                      // notice" when every date came from the student's own
                      // card is a small lie of the kind this app avoids.
                      switch ((
                        dates.any((d) => d.source == _DateSource.notice),
                        dates.any((d) => d.source == _DateSource.card),
                      )) {
                        (true, true) =>
                          'From the official notice and your admit card.',
                        (true, false) => 'As stated in the official notice.',
                        (false, true) => 'From your own admit card.',
                        (false, false) => '',
                      },
                      style: context.type.microLabel.copyWith(fontSize: 10.5),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---- Vacancy / fee -----------------------------------
                  if (update?.vacancy != null || update?.fee != null) ...[
                    const EvSectionHeader(
                      label: 'Vacancy & fee',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    EvCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EvSpace.x4,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          if (update?.vacancy != null)
                            _FactRow(
                              label: 'Total posts',
                              value: _thousands(update!.vacancy!),
                            ),
                          if (update?.vacancy != null && update?.fee != null)
                            EvHairline(inset: 0),
                          if (update?.fee != null)
                            _FactRow(
                              label: 'Application fee',
                              value: update!.fee!,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'As stated in the official notice.',
                      style: context.type.microLabel.copyWith(fontSize: 10.5),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---- Links -------------------------------------------
                  if (links.isNotEmpty) ...[
                    const EvSectionHeader(
                      label: 'Official links',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    for (final link in links) ...[
                      _LinkTile(link: link),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                  ],

                  // ---- The student's own card ---------------------------
                  if (card != null) ...[
                    const EvSectionHeader(
                      label: 'Your card',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    EvCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EvSpace.x4,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FactRow(
                            label: 'Roll number',
                            value: card!.rollNumber.isEmpty
                                ? '—'
                                : card!.rollNumber,
                            mono: true,
                          ),
                          if (card!.centerAddress.isNotEmpty) ...[
                            EvHairline(inset: 0),
                            _FactRow(
                              label: 'Centre',
                              value: card!.centerAddress,
                            ),
                          ],
                          if (card!.reportBy.isNotEmpty) ...[
                            EvHairline(inset: 0),
                            _FactRow(label: 'Report by', value: card!.reportBy),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (dates.isEmpty &&
                      links.isEmpty &&
                      update?.vacancy == null &&
                      update?.fee == null &&
                      card == null)
                    Text(
                      'This notice states no dates, fee or vacancy. Open the '
                      'official notice to read it in full.',
                      style: context.type.bodyMuted,
                    ),

                  // ---- Bell --------------------------------------------
                  if (examId != null &&
                      ref.watch(pushServiceProvider).canDeliver) ...[
                    const SizedBox(height: 4),
                    _BellRow(
                      examId: examId,
                      examName: examName,
                      alerting: alerting,
                      onToggle: () async {
                        EvHaptics.select();
                        final next = await ref
                            .read(examAlertsProvider.notifier)
                            .toggle(examId);
                        await ref
                            .read(pushServiceProvider)
                            .syncExamAlerts(next);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DateSource { notice, card }

class _DateRow {
  _DateRow(this.label, this.date, {this.source = _DateSource.notice});

  final String label;
  final DateTime date;
  final _DateSource source;
}

class _DateRowView extends StatelessWidget {
  const _DateRowView({required this.row});

  final _DateRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final d = row.date;
    final text =
        '${d.day.toString().padLeft(2, '0')} '
        '${months[d.month - 1]} ${d.year}';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
    final countdown = days == 0
        ? 'TODAY'
        : days == 1
        ? 'TOMORROW'
        : days < 0
        ? 'PAST'
        : 'IN $days DAYS';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.bodyMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            maxLines: 1,
            style: context.type.monoMeta.copyWith(
              color: p.textPrimary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              countdown,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.statusPill.copyWith(
                fontSize: 10,
                color: days <= 3 && days >= 0 ? p.dangerText : p.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.bodyMuted,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? context.type.monoMeta.copyWith(color: p.textPrimary)
                  : context.type.label.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow {
  _LinkRow(this.label, this.url, this.icon);

  final String label;
  final String url;
  final IconData icon;
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link});

  final _LinkRow link;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(EvRadius.inner),
        onTap: () async {
          final uri = Uri.tryParse(link.url);
          if (uri == null) return;
          var ok = false;
          try {
            ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e) {
            AppLogger.w('detail', 'launchUrl failed for ${link.url}: $e');
          }
          if (!ok && context.mounted) {
            await ClipboardService.copy(
              context,
              value: link.url,
              label: 'Official link',
            );
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EvRadius.inner),
              border: Border.all(color: p.borderStrong),
            ),
            child: Row(
              children: [
                Icon(link.icon, size: 16, color: p.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    link.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.label.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 13,
                  color: p.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BellRow extends StatelessWidget {
  const _BellRow({
    required this.examId,
    required this.examName,
    required this.alerting,
    required this.onToggle,
  });

  final String examId;
  final String examName;
  final bool alerting;
  final Future<void> Function() onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return EvCard(
      padding: const EdgeInsets.fromLTRB(EvSpace.x4, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alert me about this exam',
                  style: context.type.tileTitle.copyWith(),
                ),
                const SizedBox(height: 2),
                Text(
                  alerting
                      ? 'On — results, admit cards and dates.'
                      : 'Off — no notifications for this exam.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyMuted.copyWith(),
                ),
              ],
            ),
          ),
          Semantics(
            container: true,
            button: true,
            toggled: alerting,
            label: alerting
                ? 'Notifications on for $examName. Turn off.'
                : 'Notify me about $examName.',
            // `excludeSemantics` drops the InkResponse's action, so the wrapper
            // must carry it; otherwise this row was a button with no actions.
            excludeSemantics: true,
            onTap: onToggle,
            child: InkResponse(
              onTap: onToggle,
              radius: 24,
              child: SizedBox(
                width: EvSize.minTapTarget,
                height: EvSize.minTapTarget,
                child: Center(
                  child: Icon(
                    alerting
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 20,
                    color: alerting ? p.accentText : p.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _thousands(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
