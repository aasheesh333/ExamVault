import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/live_feed_dto.dart';
import '../../../domain/entities/live_update.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/widgets/ev_surfaces.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../shell/root_shell.dart';

/// What the notification bell opens.
///
/// The bell had a red badge and a tooltip that said "Notifications" but its whole
/// behaviour was a SnackBar restating the count, and nothing ever cleared the
/// badge — so the app trained users to ignore the one signal that has to work on
/// result day. This is the inbox it was always implying: the actionable rows,
/// newest first, with the badge clearing once it has been read.
Future<void> showAlertsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AlertsSheet(),
  );
}

class _AlertsSheet extends ConsumerWidget {
  const _AlertsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final feed = ref.watch(liveFeedProvider).value?.feed;

    final alerts = (feed?.activeAt(DateTime.now()) ?? const <LiveUpdate>[])
        .where(
          (u) =>
              u.status == UpdateStatus.resultOut ||
              u.status == UpdateStatus.admitCardLive ||
              u.status == UpdateStatus.formClosing,
        )
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alerts', style: context.type.sectionTitle),
                        const SizedBox(height: 2),
                        Text(
                          alerts.isEmpty
                              ? 'Nothing needs your attention.'
                              : '${alerts.length} updates need a look',
                          style: context.type.microLabel.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close alerts',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.border),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'When a commission publishes a result or releases an admit '
                  'card, it appears here — and the badge clears once you have '
                  'read it.',
                  style: context.type.bodyMuted,
                ),
              )
            else
              EvCard(
                padding: EdgeInsets.zero,
                onTap: null,
                child: Column(
                  children: [
                    for (var i = 0; i < alerts.length; i++)
                      _AlertRow(
                        update: alerts[i],
                        first: i == 0,
                        last: i == alerts.length - 1,
                        onTap: () {
                          ref
                              .read(resultExamIdProvider.notifier)
                              .select(alerts[i]);
                          Navigator.of(context).maybePop();
                          ref
                              .read(tabIndexProvider.notifier)
                              .select(EvTab.radar);
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.update,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final LiveUpdate update;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: first ? BorderSide.none : BorderSide(color: p.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    update.examName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.tileTitle,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${update.category.label} · ${update.ageLabel()}',
                    style: context.type.bodyMuted.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            EvStatusPill.status(update.status, compact: true),
          ],
        ),
      ),
    );
  }
}
