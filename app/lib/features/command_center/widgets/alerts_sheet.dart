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
/// alert list. The caller gates `markSeen` on this: opening the bell while the
/// feed was still loading used to stamp every already-published alert as seen —
/// the badge could never come back for them. The sheet now says it is checking
/// in that window instead of claiming an empty inbox, but the contract is
/// unchanged: only a loaded, non-empty, non-loading list counts as read.
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

    // "Still asking", "the ask failed" and "the answer was nothing" are three
    // different facts, and this sheet used to render all of them as the third:
    // a cold start or a dead edge with nothing cached showed "Nothing needs your
    // attention." — the most alarming lie the app can tell on result day.
    final checking = !feedAsync.hasValue && feedAsync.isLoading;

    // The provider only rejects when it fails before a snapshot exists (a
    // storage fault reading the Hive cache); a *network* failure never lands
    // there, because `LiveFeedRepository.refresh` catches it and returns a
    // snapshot with `error` set. Both are the same fact to the reader — the
    // check did not complete — so both resolve to one reason below.
    const providerFailure =
        'The live feed could not be read. Try again in a moment.';
    final repositoryFailure = feedAsync.value?.error;

    // `hasError` is checked even when a value survived: Riverpod keeps the
    // previous snapshot inside an error state, and an empty snapshot plus a
    // rejection is still a failed check, not a quiet inbox.
    final String? failureReason =
        feedAsync.hasError && repositoryFailure == null
        ? providerFailure
        : repositoryFailure;

    // `isLoading` is part of the check: after an invalidate Riverpod keeps the
    // previous value *inside* the loading state, and rows painted from a feed
    // that is still resolving must not count as read.
    if (alerts.isNotEmpty && feedAsync.hasValue && !feedAsync.isLoading) {
      onLoadedAlertsRendered?.call();
    }

    // The subtitle has to describe the body, not the count: "Nothing needs your
    // attention" above a spinner or a failure was the same lie one line up.
    // With cached rows the failure is the card's job — the subtitle counts what
    // the reader can actually see, as the radar's header does.
    final subtitle = checking
        ? 'Checking for updates…'
        : failureReason != null && alerts.isEmpty
        ? 'Could not check for updates.'
        : switch (alerts.length) {
            0 => 'Nothing needs your attention.',
            1 => '1 update needs a look',
            final n => '$n updates need a look',
          };

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
                  // Container boundary: without it the title and subtitle
                  // merged into the Close button's semantics node, announcing
                  // the whole header as one button (same family as the About
                  // header fix).
                  Expanded(
                    // Semantics INSIDE Expanded (ParentData must sit directly
                    // under its Flex): the container boundary keeps title and
                    // subtitle out of the Close button's semantics node.
                    child: Semantics(
                      container: true,
                      header: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Alerts', style: context.type.sectionTitle),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            // Two lines maximum, so a long subtitle can never push
                            // the list out of the sheet.
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.microLabel.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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
                  if (checking)
                    const _CheckingForUpdates()
                  else if (failureReason != null && alerts.isEmpty)
                    _FeedFailureCard(reason: failureReason)
                  else if (alerts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'When a commission publishes a result or releases an '
                        'admit card, it appears here — and the badge clears '
                        'once you have read it.',
                        style: context.type.bodyMuted,
                      ),
                    )
                  else ...[
                    // Cached rows survived a failed refresh, so they stay — but
                    // the sheet says the refresh failed above them instead of
                    // letting them read as a fresh check.
                    if (failureReason != null)
                      _FeedFailureCard(reason: failureReason),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckingForUpdates extends StatelessWidget {
  const _CheckingForUpdates();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            // Deliberately not the subtitle's words again: the header already
            // says "Checking for updates…", so the body carries the *why*.
            child: Text(
              'New results and admit cards appear here as soon as the feed '
              'answers.',
              style: context.type.bodyMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The inbox's honest failure surface, mirroring the radar's `_FeedErrorCard`.
///
/// `LiveFeedSnapshot.error` is the message the repository attached to a failed
/// refresh; without this card an empty feed with an error rendered exactly like
/// a genuinely quiet inbox. A Column, not a Row: at 320px @ 2.0x the reason and
/// the Retry action cannot share a line with the icon.
class _FeedFailureCard extends ConsumerWidget {
  const _FeedFailureCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    return EvCard(
      color: p.warning.withValues(alpha: 0.07),
      borderColor: p.warning.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: p.warning, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Could not check for updates.',
                  style: context.type.label.copyWith(color: p.warningText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: context.type.bodyMuted.copyWith(color: p.warningText),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: EvTextAction(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              color: p.warningText,
              onPressed: () => ref.invalidate(liveFeedProvider),
            ),
          ),
        ],
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
          // spaceBetween so the pill keeps its right edge flush when it does not
          // need its whole flex share (at 1.0x it is narrower than its share).
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // flex 3 vs 2: the exam name is the row's subject and must always be
            // the wider of the two. An even split capped it at half the row,
            // which at 320px @ 2.0x is narrower than the pill.
            Expanded(
              flex: 3,
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
            // Flexible: as a non-flex child at 320px @ 2.0x the "ADMIT CARD
            // LIVE" pill's intrinsic width (~230 of the 248 available px) ate
            // the row and collapsed the exam name to a sliver. As a flex child
            // it gets bounded.
            Flexible(
              flex: 2,
              // scaleDown, right-aligned: the pill lays its label out
              // unbounded, so its ellipsis never engages; scaling keeps the
              // label whole and inside the row. Same fix as
              // `live_radar_tile.dart`.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: EvStatusPill.status(update.status, compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
