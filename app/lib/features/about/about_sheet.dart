import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../data/services/app_logger.dart';
import '../../domain/entities/live_update.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';

/// About, data provenance and privacy.
///
/// ## Why this is a screen and not a footnote
///
/// Every fact this app shows comes from a government website, and the app reduces
/// those documents to hashes rather than redistributing them. That is a claim
/// users are entitled to check, and a store reviewer is entitled to see. So the
/// sources are listed with the exact URLs and the time each was last checked,
/// taken from the feed's own health block rather than written by hand.
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

    return ScaffoldMessenger(
      // The sheet's own messenger: a SnackBar shown through the root one
      // renders *under* the modal barrier and the 90%-tall sheet, so a failed
      // link tap gave zero feedback — the row looked dead.
      child: Scaffold(
        // A messenger with no descendant Scaffold has nothing to present to:
        // showSnackBar asserted in debug and was a *silent no-op* in release —
        // the failed-link feedback this messenger exists for never rendered.
        // Transparent so the sheet surface below keeps its own colour and
        // rounded corners.
        backgroundColor: Colors.transparent,
        body: Container(
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
            // Ink canvas above the sheet's opaque surface: the link rows'
            // InkWell splashes painted on the bottom-sheet route's Material
            // *underneath* the Container, so presses gave no feedback
            // (pattern: command_center radar rows).
            builder: (context, controller) => Material(
              type: MaterialType.transparency,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, EvSpace.x4, 20, 32),
                children: [
                  const _SheetHeader(
                    title: 'About ExamVault',
                    subtitle: 'Version 1.0.0 · free · no account required',
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
                  const EvSectionHeader(
                    label: 'Official sources',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  _Link(
                    label: 'SSC \u2014 Staff Selection Commission',
                    url: 'https://ssc.gov.in/',
                  ),
                  _Link(
                    label: 'UPSC \u2014 Union Public Service Commission',
                    url: 'https://www.upsc.gov.in/',
                  ),
                  _Link(label: 'IBPS', url: 'https://www.ibps.in/'),
                  _Link(
                    label: 'RRB Chennai',
                    url: 'https://rrbchennai.gov.in/',
                  ),
                  _Link(
                    label: 'TNPSC \u2014 Tamil Nadu Public Service Commission',
                    url: 'https://www.tnpsc.gov.in/',
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
            Expanded(child: Text(title, style: context.type.sectionTitle)),
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
          Text(subtitle!, style: context.type.microLabel.copyWith()),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(source.label, style: context.type.tileTitle.copyWith()),
          ),
          Text(
            // Never "OK" when it is not: the count and the status come from the
            // publisher's own refresh, so a quiet or broken source is visible.
            ok ? '${source.rows} items' : source.status,
            style: context.type.microLabel.copyWith(
              color: ok ? p.textTertiary : p.warningText,
            ),
          ),
        ],
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
          'the categories you follow. It is not linked to your vault or your roll '
          'number, and denying the permission changes nothing else.',
    ),
    (
      'No analytics, no adverts',
      'There is no analytics SDK, no advertising identifier and no location '
          'permission in this app.',
    ),
    (
      'Deleting your data',
      'Delete a card in the app, or uninstall. Both remove everything — we hold '
          'no copy, so there is nothing to request from us.',
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
