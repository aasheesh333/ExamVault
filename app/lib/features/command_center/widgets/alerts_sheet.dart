import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../data/models/live_feed_dto.dart';
import '../../../data/repositories/live_feed_repository.dart';
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
    //
    // `AsyncLoading` alone is not enough to detect "still asking". Production
    // never enters it: `LiveFeedNotifier.build` answers from
    // `readCached() ?? emptySnapshot()` *synchronously* and refreshes with
    // `unawaited(...)`, so on a fresh install the provider is
    // `AsyncData(empty, source: none, error: null)` for the whole first fetch —
    // the network timeout on result day. `neverAnswered` is that sentinel, shared
    // with the radar so both surfaces read the same state the same way.
    final snapshot = feedAsync.value;
    final checking =
        (!feedAsync.hasValue && feedAsync.isLoading) ||
        // A rejected build is a failed check, not a pending one — without this
        // guard a retained sentinel would show a spinner forever instead of the
        // failure card.
        (!feedAsync.hasError && neverAnswered(snapshot));

    // The provider only rejects when it fails before a snapshot exists (a
    // storage fault reading the Hive cache); a *network* failure never lands
    // there, because `LiveFeedRepository.refresh` catches it and returns a
    // snapshot with `error` set. Both are the same fact to the reader — the
    // check did not complete — so both resolve to one reason below. Neither
    // sentence names a cause: a provider rejection is storage, not the network.
    const providerFailure = 'The live feed could not be read.';
    final repositoryFailure = snapshot?.error;

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
      // Vertical only: the ListView already insets its children by 20px, and an
      // extra horizontal inset here put the spinner at x=40 while the header
      // and the failure card sit at x=20.
      padding: const EdgeInsets.symmetric(vertical: EvSpace.x1),
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
          const SizedBox(width: EvSpace.x3),
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

  /// Imperative verbs that describe a *gesture* this sheet cannot offer.
  static const _gestureVerbs = ['Pull', 'Swipe', 'Drag'];

  /// The repository's diagnostic, with any gesture instruction dropped.
  ///
  /// `LiveFeedRepository.refresh` ends its generic failure with "Pull to
  /// retry." — true of the radar, which has a `RefreshIndicator`, and false
  /// here: a modal sheet has nothing to pull, so that sentence described a
  /// gesture that did nothing.
  ///
  /// The split is on the *gesture verb*, not on that exact string, so a
  /// repository copy change ("Pull down to refresh.", "Swipe down to retry.")
  /// still cannot start telling a modal reader to pull. The diagnostic
  /// sentence(s) before it are kept verbatim: they are the only text that knows
  /// why the check failed, and the honesty rules forbid paraphrasing them.
  static String diagnosticOf(String reason) {
    final text = reason.trim();
    final boundary = text.lastIndexOf('. ');
    if (boundary < 0) {
      // A single sentence: keep it, unless it *is* a gesture instruction — in
      // which case there is no diagnostic to show and the card keeps only its
      // own heading and the affordance it can honour.
      return _isGestureInstruction(text) ? '' : text;
    }
    if (!_isGestureInstruction(text.substring(boundary + 2))) return text;
    // Recurse on the head so stacked instructions ("… Pull to retry. Swipe down
    // to refresh.") are all dropped.
    return diagnosticOf(text.substring(0, boundary + 1));
  }

  static bool _isGestureInstruction(String sentence) {
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return false;
    return _gestureVerbs.contains(trimmed.split(RegExp(r'\s+')).first);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final diagnostic = diagnosticOf(reason);
    return EvCard(
      color: p.warning.withValues(alpha: 0.07),
      borderColor: p.warning.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: p.warning, size: 20),
              const SizedBox(width: EvSpace.x3),
              Expanded(
                child: Text(
                  // Not "Could not check for updates." — the header subtitle
                  // already says exactly that, and two identical sentences in
                  // one card read as a stutter.
                  'The check failed',
                  style: context.type.label.copyWith(color: p.warningText),
                ),
              ),
            ],
          ),
          if (diagnostic.isNotEmpty) ...[
            const SizedBox(height: EvSpace.x2),
            Text(
              diagnostic,
              style: context.type.bodyMuted.copyWith(color: p.warningText),
            ),
          ],
          const SizedBox(height: EvSpace.x1),
          // The affordance the reader actually has. Without it the only
          // instruction on screen was the repository's "Pull to retry."
          Text(
            'Tap Retry to check again.',
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

    final headline = Text(
      update.examName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.type.tileTitle,
    );
    final meta = Text(
      '${update.category.label} · ${update.ageLabel()}',
      style: context.type.bodyMuted.copyWith(fontSize: 12),
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        // Full width: the row's parent is a Column (loose constraints), so
        // without this the Column sized to its content and the card centred it,
        // leaving the row indented from the card's edge at 1.0x.
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: first ? BorderSide.none : BorderSide(color: p.border),
          ),
        ),
        // One arrangement at every scale, mirroring `live_radar_tile.dart`: the
        // pill used to sit in a 2/5 flex share (~95px) that could not hold its
        // 134px intrinsic width even at 1.0x text, so `FittedBox` painted the
        // 11px label at 7.75px — under the 11px floor (theme_tokens.dart:11) at
        // the default text size on a 320dp phone. The pill now owns the row's
        // full width (248px at 320dp), which is more than its 233px intrinsic
        // width even at 2.0x, so it paints at its token size with no scaling and
        // no per-scale branch.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            headline,
            const SizedBox(height: 3),
            meta,
            const SizedBox(height: 6),
            EvStatusPill.status(update.status, compact: true),
          ],
        ),
      ),
    );
  }
}
