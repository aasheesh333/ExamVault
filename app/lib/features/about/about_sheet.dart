import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../data/services/app_logger.dart';
import '../../domain/entities/exam_category.dart';
import '../../domain/entities/live_update.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';

/// About, data provenance, privacy and "Delete all data".
///
/// ## Why this is a screen and not a footnote
///
/// Every fact this app shows comes from a government website, and the app reduces
/// those documents to hashes rather than redistributing them. That is a claim
/// users are entitled to check, and a store reviewer is entitled to see. So the
/// sources are listed with the exact URLs and the time each was last checked,
/// taken from the feed's own health block rather than written by hand. A source
/// the feed carries no `checked_at` for simply does not show a time: a stale
/// cache must never read as a fresh check.
///
/// It also replaces the fake "A" avatar that used to sit in the top bar of an app
/// with no accounts: a letter in a circle reads as "you are signed in", which was
/// never true.
Future<void> showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AboutSheet(),
  );
}

class _AboutSheet extends ConsumerWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final snapshot = ref.watch(liveFeedProvider).value;
    final sources = snapshot?.feed.sources ?? const <SourceHealth>[];
    final byId = {for (final s in sources) s.id: s};

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border),
      ),
      // A rounded decoration does not clip its child, so scrolled text painted
      // over the dimmed page outside the sheet's corners.
      clipBehavior: Clip.antiAlias,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        // The messenger lives *inside* the builder, never around the route
        // child. The route child is what the modal bottom sheet bottom-anchors
        // at 90%; a Scaffold wrapping it fills the route's full height instead,
        // so the decorated Container shrink-wrapped to the top edge and the
        // whole surface — rounded corners, border, barrier — moved to the top of
        // the screen (measured at 393x852: sheet (1,1)-(392,766) instead of
        // (1,76)-(392,851)), with the bottom tenth showing the dimmed page.
        builder: (context, controller) => ScaffoldMessenger(
          // The sheet's own messenger: a SnackBar shown through the root one
          // renders *under* the modal barrier and the 90%-tall sheet, so a
          // failed link tap gave zero feedback — the row looked dead.
          child: Scaffold(
            // A messenger with no descendant Scaffold has nothing to present to:
            // showSnackBar asserted in debug and was a *silent no-op* in release
            // — the failed-link feedback this messenger exists for never
            // rendered. Transparent so the sheet surface outside keeps its own
            // colour and rounded corners.
            backgroundColor: Colors.transparent,
            // Ink canvas above the sheet's opaque surface: the link rows'
            // InkWell splashes painted on the bottom-sheet route's Material
            // *underneath* the Container, so presses gave no feedback
            // (pattern: command_center radar rows).
            body: Material(
              type: MaterialType.transparency,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, EvSpace.x4, 20, 32),
                children: [
                  // Not const: the subtitle embeds the build-injected version.
                  _SheetHeader(
                    title: 'About ExamVault',
                    subtitle: AppConfig.appVersion.isEmpty
                        ? 'Free · no account required'
                        : 'Version ${AppConfig.appVersion} · free · no account '
                              'required',
                  ),
                  const SizedBox(height: 16),

                  // --- Appearance ---------------------------------------------------
                  const EvSectionHeader(
                    label: 'Appearance',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _ThemePicker(),

                  const SizedBox(height: 20),

                  // --- Where the data comes from -----------------------------------
                  const EvSectionHeader(
                    label: 'Where the data comes from',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _Paragraph(
                    'Every result, notice and date in this app is copied from the '
                    'commission that published it. Nothing is written by hand and '
                    'nothing is invented. If a source does not answer, the app shows '
                    'nothing rather than a guess.',
                  ),
                  const SizedBox(height: 10),
                  if (sources.isEmpty)
                    _Paragraph(
                      'Source status is unavailable until the feed loads.',
                    )
                  else
                    for (final source in sources) _SourceRow(source: source),

                  const SizedBox(height: 20),

                  // --- The copyright stance ----------------------------------------
                  const EvSectionHeader(
                    label: 'Why we never host the PDF',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _Paragraph(
                    'The official result documents belong to the commissions, so this '
                    'app links to them on the commission\u2019s own website. It does '
                    'not keep a copy of any government document.',
                  ),
                  const SizedBox(height: 8),
                  _Paragraph(
                    'To answer \u201cis my roll number in the list?\u201d quickly, the '
                    'list is reduced to one-way hashes. Your phone hashes the number '
                    'you type and looks for a match, so the actual candidate list never '
                    'reaches your device \u2014 and nobody can use what we publish to '
                    'rebuild it.',
                  ),

                  const SizedBox(height: 20),

                  // --- Privacy ------------------------------------------------------
                  const EvSectionHeader(
                    label: 'What we store',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _Bullet(
                    'Admit cards, roll numbers and passwords are encrypted with '
                    'your device\u2019s Keystore. They never leave the phone.',
                  ),
                  _Bullet(
                    'There is no account, so there is nothing to sign in to and '
                    'nothing to leak from a server.',
                  ),
                  _Bullet(
                    'Roll numbers you type are checked on your device and are not '
                    'sent to us.',
                  ),

                  const SizedBox(height: 20),

                  // --- Notifications ------------------------------------------------
                  const _NotificationCategories(),

                  const SizedBox(height: 20),

                  // --- Your data ----------------------------------------------------
                  const EvSectionHeader(
                    label: 'Your data',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _Paragraph(
                    'Your admit cards and your settings live only on this device. '
                    'You can remove them here without uninstalling the app.',
                  ),
                  const SizedBox(height: 8),
                  _DeleteAllData(),

                  const SizedBox(height: 20),
                  const EvSectionHeader(
                    label: 'Official sources',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  for (final link in _commissionLinks)
                    _Link(
                      // The hand-written label stays: the feed carries a short
                      // code ("SSC"), not a full commission name. The URL comes
                      // from the publisher's own health block when it supplies
                      // one, so a moved site is fixed in the feed rather than in
                      // an app release.
                      label: link.label,
                      url: commissionUrlFor(link.id, byId, link.url),
                    ),

                  const SizedBox(height: 16),
                  const EvSectionHeader(
                    label: 'Privacy policy',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _Paragraph(
                    'The full policy ships inside the app and states exactly what is '
                    'stored, what leaves the phone and what does not.',
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    // The bare InkWell exposed no trait at all: TalkBack read a
                    // flat text run with no hint it was tappable. The child Text is
                    // the name (codebase rule — a composed label plus un-excluded
                    // children double-announces).
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(EvRadius.inner),
                      onTap: () => _showPolicy(context),
                      // Same 44px floor as the commission links.
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: EvSize.minTapTarget,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Read the privacy policy',
                                  style: context.type.bodyMuted.copyWith(),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: p.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'ExamVault is not affiliated with, endorsed by, or acting on behalf '
                    'of any of these commissions. Always verify against the official '
                    'notice before acting on a result.',
                    style: context.type.bodyMuted.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle + close button.
///
/// These sheets open at 92% of the viewport, which leaves only a thin strip of
/// barrier at the top — and a modal sheet can also be dismissed by dragging down,
/// which nobody discovers unprompted. Without an explicit control the screen looks
/// like a page you are stuck on.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Container boundary: without it the title (and the subtitle
            // below) merged into the Close button's semantics node, so
            // TalkBack announced the whole header as one button named
            // "About ExamVault Close Version …".
            Expanded(
              // Semantics INSIDE Expanded: ParentData widgets must sit
              // directly under their Flex, so the container boundary that
              // keeps the title out of the Close button's node goes on the
              // inner side.
              child: Semantics(
                container: true,
                header: true,
                child: Text(title, style: context.type.sectionTitle),
              ),
            ),
            Semantics(
              button: true,
              label: 'Close',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).maybePop(),
                // 44px hit box around the 32px circle: the visual can be small,
                // the tap target may not.
                child: Container(
                  width: EvSize.minTapTarget,
                  height: EvSize.minTapTarget,
                  margin: const EdgeInsets.only(left: 4),
                  alignment: Alignment.center,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Semantics(
            container: true,
            child: Text(subtitle!, style: context.type.microLabel.copyWith()),
          ),
        ],
      ],
    );
  }
}

/// Light / dark / follow-system, persisted in the settings box.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(themePreferenceProvider);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final pref in ThemePreference.values)
          EvChip(
            label: pref.label,
            selected: active == pref,
            onTap: () =>
                ref.read(themePreferenceProvider.notifier).select(pref),
          ),
      ],
    );
  }
}

/// The exam categories this device's push token is subscribed to.
///
/// The About sheet and the privacy policy both said the token was used "for the
/// categories you follow", while every device was subscribed to all five and
/// nothing let a student follow anything. These chips are that promise kept.
///
/// Hidden where a push cannot arrive: on the web and in a build without push
/// credentials the switch would change nothing, and offering it would be a lie.
/// The one-line note that replaces the section says why.
class _NotificationCategories extends ConsumerWidget {
  const _NotificationCategories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(pushServiceProvider).canDeliver) {
      return _Paragraph(
        'This build cannot deliver push notifications (web, or a build without '
        'push credentials), so there are no categories to choose.',
      );
    }

    final followed = ref.watch(followedCategoriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EvSectionHeader(label: 'Notifications', padding: EdgeInsets.zero),
        const SizedBox(height: 8),
        // What the token is for, before the switches: the policy's claim and
        // this control must be the same sentence.
        _Paragraph(
          'Your push token is subscribed only to the categories you follow; '
          'turning one off stops those alerts on this device.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final category in ExamCategory.values)
              EvChip(
                label: category.label,
                selected: followed.contains(category),
                onTap: () => _toggle(ref, category),
              ),
          ],
        ),
        if (followed.isEmpty) ...[
          const SizedBox(height: 8),
          // An empty set is a legal choice, but five unselected chips do not
          // say what it means. State it, rather than leaving the user to guess.
          _Paragraph('No categories — you will not get exam alerts.'),
        ],
      ],
    );
  }

  /// Optimistic, log-only failure — the posture of the per-exam bells in
  /// `command_center_screen.dart`: flip the state, then reconcile the backend.
  /// `syncTopics` is idempotent, so a subscription dropped by a Play Services
  /// update repairs itself on the next boot.
  Future<void> _toggle(WidgetRef ref, ExamCategory category) async {
    final next = await ref
        .read(followedCategoriesProvider.notifier)
        .toggle(category);
    unawaited(ref.read(pushServiceProvider).syncTopics(next));
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.type.bodyMuted.copyWith(height: 1.55));
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 7),
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: context.type.bodyMuted.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One commission, with the state the pipeline actually observed.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});

  final SourceHealth source;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final ok = source.isAvailable;
    final colour = ok ? p.success : p.warning;
    // The publisher's own observation time. Without it the panel presented a
    // stale cache's health as current — the one thing it exists to prevent.
    // Absent stays absent: no "checked recently" guess.
    final checkedAt = source.checkedAt;
    final checked = checkedAt == null
        ? null
        : sourceCheckedLabel(checkedAt, DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          // The label and its metadata are stacked rather than two Row cells:
          // "17 items · checked 4h ago" plus a commission name does not fit one
          // line at 320px @2.0x, and a `Row` would have ellipsised the age —
          // the fact this panel exists to show.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.label, style: context.type.tileTitle.copyWith()),
                const SizedBox(height: 2),
                Text(
                  // Never "OK" when it is not: the count and the status come
                  // from the publisher's own refresh, so a quiet or broken
                  // source is visible.
                  [
                    ok ? '${source.rows} items' : source.status,
                    ?checked,
                  ].join(' \u00b7 '),
                  style: context.type.microLabel.copyWith(
                    // 11, not the token's 10.5: the theme's own floor.
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: ok ? p.textTertiary : p.warningText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `checked 4h ago`, or the full date once the observation is over a day old.
///
/// Relative labels are only useful while they are short; "checked 32d ago" is
/// harder to place than the date. [now] is a parameter so a test can pin the
/// label to a fixed clock — a function of `DateTime.now()` alone could not be
/// asserted exactly.
///
/// Returns null for a stamp in the future. That is clock skew, not a check that
/// has happened, and the verb would assert something untrue — so the row says
/// nothing about time rather than printing a date for a future check.
@visibleForTesting
String? sourceCheckedLabel(DateTime checkedAt, DateTime now) {
  final age = now.difference(checkedAt);
  if (age.isNegative) return null;
  if (age.inMinutes < 1) return 'checked just now';
  if (age.inHours < 1) return 'checked ${age.inMinutes}m ago';
  if (age.inHours < 24) return 'checked ${age.inHours}h ago';
  return 'checked ${_fullDate(checkedAt)}';
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Day, month and year in the device's own zone — `checked_at` arrives as UTC.
String _fullDate(DateTime at) {
  final local = at.toLocal();
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}';
}

/// The commissions the app covers, with the label each is listed under.
///
/// `url` is only the fallback: the feed's `sources[].homepage` wins whenever the
/// publisher supplied one (see the "Official sources" section).
const _commissionLinks = <({String id, String label, String url})>[
  (
    id: 'ssc',
    label: 'SSC \u2014 Staff Selection Commission',
    url: 'https://ssc.gov.in/',
  ),
  (
    id: 'upsc',
    label: 'UPSC \u2014 Union Public Service Commission',
    url: 'https://www.upsc.gov.in/',
  ),
  (id: 'ibps', label: 'IBPS', url: 'https://www.ibps.in/'),
  (id: 'railways', label: 'RRB Chennai', url: 'https://rrbchennai.gov.in/'),
  (
    id: 'tnpsc',
    label: 'TNPSC \u2014 Tamil Nadu Public Service Commission',
    url: 'https://www.tnpsc.gov.in/',
  ),
];

/// The URL an "Official sources" row links to.
///
/// The publisher's own `homepage` wins whenever the feed carries one; the
/// hand-written [fallback] only covers a feed with no health block (older
/// documents) or a source that omits the field. Extracted so a test can assert
/// the resolution itself rather than the fact that *some* InkWell has a callback.
@visibleForTesting
String commissionUrlFor(
  String id,
  Map<String, SourceHealth> byId,
  String fallback,
) => byId[id]?.homepage ?? fallback;

/// "Delete all data", under the "Your data" heading.
///
/// The vault's `wipe()` was documented as "used by Delete all data" with no
/// caller and no UI: a documented promise the app never kept. It now wipes the
/// vault, every settings key, the cached feed and the HTTP cache, drops the push
/// topic subscriptions, and resets the in-memory providers so the screens empty
/// without a restart.
class _DeleteAllData extends ConsumerStatefulWidget {
  const _DeleteAllData();

  @override
  ConsumerState<_DeleteAllData> createState() => _DeleteAllDataState();
}

class _DeleteAllDataState extends ConsumerState<_DeleteAllData> {
  /// A dialog is a route too: a fast double tap used to stack two confirms.
  final _guard = SheetOpenGuard();
  bool _busy = false;

  Future<void> _confirmAndDelete() async {
    await _guard.run<void>(() async {
      final confirmed = await _confirm();
      if (!confirmed || !mounted) return;

      setState(() => _busy = true);
      try {
        // Bounded like every other storage path in this app: a hung Keystore
        // wipe would otherwise leave the button a permanent "Deleting…" with no
        // way to know whether anything happened.
        await ref
            .read(dataWiperProvider)
            .deleteAll()
            .timeout(const Duration(seconds: 15));
        if (!mounted) return;
        // Says what the code actually did. It does not claim the public feed
        // cache is gone for good: a refresh already in flight can repopulate it,
        // and that copy holds no personal data.
        _toast('Your admit cards and settings were deleted.');
      } catch (e, st) {
        AppLogger.e('about', 'delete-all failed', e, st);
        if (!mounted) return;
        _toast('Could not delete everything. Try again.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  Future<bool> _confirm() async {
    final p = context.ev;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
        // The dialog fits at the mandated floor (measured 320x568 @2.0x: both
        // actions hit-testable inside the viewport), but on anything shorter —
        // 320x480, or the keyboard up at 2.0x — the body would be the first
        // thing to clip. Scrolling costs nothing when it already fits.
        scrollable: true,
        title: Text('Delete all data?', style: context.type.sectionTitle),
        content: Text(
          'This removes every admit card and every setting on this device. It '
          'cannot be undone.\n\nCached copies of the public feed and result '
          'indexes hold none of your data and may be downloaded again.',
          style: context.type.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Keep my data',
              style: context.type.label.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: context.type.label.copyWith(
                color: p.dangerText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: context.type.label.copyWith(color: Colors.white),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Semantics(
      button: true,
      enabled: !_busy,
      // The child Text is the name (codebase rule: a composed label on top of
      // un-excluded children double-announces).
      child: InkWell(
        borderRadius: BorderRadius.circular(EvRadius.inner),
        onTap: _busy ? null : _confirmAndDelete,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                if (_busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.danger,
                    ),
                  )
                else
                  Icon(Icons.delete_outline_rounded, size: 14, color: p.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _busy ? 'Deleting…' : 'Delete all data',
                    style: context.type.bodyMuted.copyWith(color: p.dangerText),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Semantics(
      // Opens in a browser, so the honest trait is `link`, not `button` —
      // TalkBack then says "double tap to visit link" and the child Text is
      // the name (a composed label here would double-announce, the failure
      // the whole codebase's semantics rule exists to prevent).
      link: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(EvRadius.inner),
        onTap: () async {
          final uri = Uri.parse(url);
          bool ok;
          try {
            ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e) {
            // url_launcher *throws* PlatformException when no activity can
            // handle the URL (Android Go, de-Googled devices) instead of
            // returning false — unhandled, the tap looked completely dead.
            AppLogger.w('about', 'launchUrl failed for $url: $e');
            ok = false;
          }
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not open the link. $url',
                  style: context.type.label.copyWith(color: Colors.white),
                ),
              ),
            );
          }
        },
        // 44px floor: the row was ~35.5px tall — under the app's own
        // EvSize.minTapTarget — on the primary way users reach commission sites.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: context.type.bodyMuted.copyWith()),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 12,
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

/// The policy, readable offline.
///
/// A store listing needs a hosted URL, but a student on exam morning does not have
/// one: the text that matters must be in the app they already installed. The
/// hosted copy at `docs/PRIVACY.md` is generated from the same statements.
Future<void> _showPolicy(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PolicySheet(),
  );
}

class _PolicySheet extends StatelessWidget {
  const _PolicySheet();

  static const _sections = <(String, String)>[
    (
      'No account, no profile',
      'The app never asks for an email, phone number or password. Nothing you '
          'enter is uploaded.',
    ),
    (
      'Your vault stays on the phone',
      'Admit cards, roll numbers and portal passwords are encrypted with the '
          'Android Keystore. They are excluded from backup, so even a device '
          'migration does not move them.',
    ),
    (
      'Roll checks happen on your device',
      'The published index contains only one-way hashes of the official roll '
          'numbers. Your phone hashes what you type and compares locally, so the '
          'number never leaves the device and we cannot tell what you searched.',
    ),
    (
      'What the app downloads',
      'A public JSON feed and, when you check a result, one small index. The '
          'request carries no personal data — the same request a browser makes '
          'for the same public file.',
    ),
    (
      'Notifications',
      'If you allow them, a push token is used only to send result alerts for '
          'the categories you follow. Pick those categories in About \u2192 '
          'Notifications; turning one off unsubscribes it. It is not linked to '
          'your vault or your roll number, and denying the permission changes '
          'nothing else.',
    ),
    (
      'No analytics, no adverts',
      'There is no analytics SDK, no advertising identifier and no location '
          'permission in this app.',
    ),
    (
      'Deleting your data',
      'Delete a card to remove that card, or use Delete all data in About to '
          'remove every card, every setting and the cached feed at once. '
          'Uninstalling removes everything. We hold no copy, so there is nothing '
          'to request from us.',
    ),
    (
      'Official documents',
      'Result PDFs belong to the commissions. The app links to them on the '
          "commission's own site and never hosts or redistributes a copy.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border),
      ),
      // Same clip as the About sheet: the policy list is taller than the sheet and
      // its lines were drawn over the page above the rounded corners.
      clipBehavior: Clip.antiAlias,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, EvSpace.x4, 20, 32),
          children: [
            const _SheetHeader(
              title: 'Privacy policy',
              subtitle:
                  'What is stored, what leaves the phone, and what does not.',
            ),
            const SizedBox(height: 16),
            for (final (title, body) in _sections) ...[
              Text(title, style: context.type.tileTitle.copyWith()),
              const SizedBox(height: 4),
              _Paragraph(body),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small shortcut used by the top bar.
void openAbout(BuildContext context) => showAboutSheet(context);
