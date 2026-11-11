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
///
/// Completes with whether the sheet actually rendered a **loaded, non-empty**
/// alert list. The caller gates `markSeen` on this: while the feed is loading
/// the sheet shows "Nothing needs your attention.", and opening the bell in
/// that window used to stamp every already-published alert as seen — the badge
/// could never come back for them.
Future<bool> showAlertsSheet(BuildContext context, WidgetRef ref) async {
  var renderedLoadedAlerts = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _AlertsSheet(onLoadedAlertsRendered: () => renderedLoadedAlerts = true),
  );
  return renderedLoadedAlerts;
}

class _AlertsSheet extends ConsumerWidget {
  const _AlertsSheet({this.onLoadedAlertsRendered});

  /// Fired from build when a loaded, non-empty list reaches the screen. The
  /// callback only sets a captured bool — safe and idempotent to call on every
  /// rebuild, and deliberately *not* routed through Navigator.pop: the sheet
  /// can also be dismissed by drag, barrier tap or back gesture, and reading
  /// the alerts must count however the user leaves.
  final VoidCallback? onLoadedAlertsRendered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final feedAsync = ref.watch(liveFeedProvider);
    final feed = feedAsync.value?.feed;

    final alerts =
        (feed?.activeAt(DateTime.now()) ?? const <LiveUpdate>[])
            .where(
              (u) =>
                  u.status == UpdateStatus.resultOut ||
                  u.status == UpdateStatus.admitCardLive ||
                  u.status == UpdateStatus.formClosing,
            )
            .toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    // `isLoading` is part of the check: after an invalidate Riverpod keeps the
    // previous value *inside* the loading state, and rows painted from a feed
    // that is still resolving must not count as read.
    if (alerts.isNotEmpty && feedAsync.hasValue && !feedAsync.isLoading) {
      onLoadedAlertsRendered?.call();
    }

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border),
      ),
      // A rounded decoration does not clip its child, so rows scrolled past the
      // top edge painted over the dimmed page outside the corners.
      clipBehavior: Clip.antiAlias,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        builder: (context, controller) => Column(
          children: [
            // Own grabber: the theme-level drag handle is disabled (over a
            // transparent sheet background it floated on the dimmed scrim,
            // detached from the card).
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
            // Header sits outside the scroll view: inside it, the title and close
            // button rode up over the first row at 320px and at 2.0x.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
                          switch (alerts.length) {
                            0 => 'Nothing needs your attention.',
                            1 => '1 update needs a look',
                            final n => '$n updates need a look',
                          },
                          // Two lines maximum, so a long subtitle can never push
                          // the list out of the sheet.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
            Expanded(
              child: ListView(
                controller: controller,
                // 20px sides: the card was full-bleed — its border touching the
                // screen edges while the sheet's own header sits at x=20. Three
                // different left edges in one sheet.
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  if (alerts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'When a commission publishes a result or releases an '
                        'admit card, it appears here — and the badge clears '
                        'once you have read it.',
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
