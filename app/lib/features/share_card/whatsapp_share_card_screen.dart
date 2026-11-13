import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../data/services/app_logger.dart';
import '../../data/services/share_service.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/live_update.dart';
import '../result_checker/engine/roll_index_engine.dart';
import '../../providers/app_providers.dart';
import '../../features/shell/root_shell.dart';
import '../../features/vault/vault_form_sheet.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';
import 'widgets/share_infographic.dart';

/// Screen 4 — the viral share card.
///
/// The card is rasterised at 3x inside a `RepaintBoundary`. 1080 px wide is the
/// WhatsApp sweet spot: sharp on every phone, still under 200 KB so a 2G user in
/// a hostel can actually send it.
class WhatsappShareCardScreen extends ConsumerStatefulWidget {
  const WhatsappShareCardScreen({super.key});

  @override
  ConsumerState<WhatsappShareCardScreen> createState() =>
      _WhatsappShareCardScreenState();
}

class _WhatsappShareCardScreenState
    extends ConsumerState<WhatsappShareCardScreen> {
  final _boundaryKey = GlobalKey();
  final _captionController = TextEditingController();

  /// Whether the exported card carries the student's roll number.
  ///
  /// This replaced an "Attach PDF to message" switch that (a) was never read and
  /// (b) claimed to send a PDF the app does not host. Sharing a screenshot into a
  /// 200-person study group with your roll number on it is the default people
  /// expect, but they deserve a switch — so this one actually does something.
  bool _showRoll = true;
  bool _sharing = false;

  /// True once the user edits the caption; auto-sync stops from then on.
  bool _captionTouched = false;

  /// The exam the current caption describes. When this changes, auto-sync
  /// resumes so the caption tracks the newly selected exam instead of staying
  /// frozen on the previous one.
  String? _captionExamId;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  /// Null when there is genuinely nothing to share — no radar row and no saved
  /// card. The screen then shows an explainer instead of a card built on
  /// placeholders like "SSC CGL Tier-1 2026" + "Roll —".
  ShareCardData? _buildCard(
    LiveUpdate? update,
    AdmitCard? card,
    RollLookupResult? lookup,
  ) {
    final examName = update?.examName ?? card?.examName;
    final examId = update?.examId ?? card?.examId;
    if (examName == null || examId == null) return null;

    // Bug: this defaulted to `resultOut` whenever there was no radar row, so a
    // saved admit card was shared under a "RESULT IS LIVE" strip. A saved card
    // is an admit card; only a radar row knows about a published result.
    final status = update?.status ?? UpdateStatus.admitCardLive;

    // A student who checked straight from the radar has no saved card, but they
    // do have a verified roll number and a reason to celebrate. Before this,
    // "Share the news" led to a card with no roll on it.
    //
    // The caller only passes a lookup whose ResultCheckState belongs to this
    // exam, so another exam's roll can never be borrowed here.
    final lookedUp = lookup != null && lookup.isFound ? lookup : null;
    final roll = card?.rollNumber ?? lookedUp?.rollNumber ?? '';
    final verified = card?.rollNumberVerified ?? lookedUp != null;

    return ShareCardData(
      examName: examName,
      headline: _headlineFor(status),
      // Never promise content the card does not carry: there are no cut-offs in
      // this feed, and the official document is a link, not an attachment.
      subline: _sublineFor(status),
      dateLine: _shortDate(DateTime.now()),
      // Empty when we do not have the user's roll — never a "—" placeholder.
      rollNumber: roll,
      // The student's own name travels with their card: it is the one detail
      // that makes a shared result *theirs*. Radar-only shares have no card
      // and therefore no name — the card then stays anonymous, honestly.
      candidateName: card?.candidateName ?? '',
      selected: verified,
      shareUrl: ref.read(resultIndexRepositoryProvider).shareUrl(examId),
      officialUrl: update?.officialUrl,
      pdfSizeLabel: update?.pdfSizeLabel,
    );
  }

  /// The alert strip and the big headline must say the same thing.
  ///
  /// Bug: every share, including an admit-card one, was headed "RESULT IS LIVE".
  static String _headlineFor(UpdateStatus status) => switch (status) {
    UpdateStatus.resultOut => 'RESULT IS LIVE',
    UpdateStatus.admitCardLive => 'ADMIT CARD IS LIVE',
    UpdateStatus.answerKey => 'ANSWER KEY IS OUT',
    UpdateStatus.formClosing => 'LAST DATE IS NEAR',
    UpdateStatus.notification => 'NEW VACANCY OUT',
    UpdateStatus.awaited => 'UPDATE AWAITED',
  };

  static String _sublineFor(UpdateStatus status) => switch (status) {
    UpdateStatus.resultOut => 'Official link & instant roll-number check',
    UpdateStatus.admitCardLive => 'Admit card link & exam-day details',
    UpdateStatus.answerKey => 'Official key & objection window',
    UpdateStatus.formClosing => 'Deadline & direct application link',
    UpdateStatus.notification => 'Vacancy details & how to apply',
    UpdateStatus.awaited => 'Official notice & next update',
  };

  /// Picks the saved card that belongs to the exam being shared.
  ///
  /// Bug: this used `cards.first`, so tapping the UPSC result could render SSC's
  /// roll number under UPSC's headline and a false "IN THE LIST" badge.
  AdmitCard? _cardFor(
    List<AdmitCard> cards,
    LiveUpdate? update,
    String? selectedId,
  ) {
    if (update != null) {
      for (final c in cards) {
        if (c.examId == update.examId) return c;
      }
      // No saved card for this exam: another exam's credentials are not a
      // substitute, so fall through to the radar-only card.
      return null;
    }
    for (final c in cards) {
      if (c.id == selectedId) return c;
    }
    return cards.isEmpty ? null : cards.first;
  }

  static String _shortDate(DateTime d) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${d.day.toString().padLeft(2, '0')} '
        '${months[d.month - 1]} ${d.year}';
  }

  String _defaultCaption(ShareCardData data) {
    final lines = <String>[
      // The caption echoes the card's own subline so an admit-card share does
      // not promise an "instant roll-number check" the card never offers.
      '🚨 ${data.examName.toUpperCase()} ${data.headline} — ${data.subline}.',
      // The student's own name leads their line when present: the caption is
      // what lands in the group chat, and "Roll 123…" alone is not a person.
      if (data.candidateName.isNotEmpty && data.rollNumber.isNotEmpty)
        '${data.candidateName} · Roll ${data.rollNumber}${data.selected ? ' · in the published list' : ''}'
      else if (data.rollNumber.isNotEmpty)
        'Roll ${data.rollNumber}${data.selected ? ' · in the published list' : ''}'
      else if (data.candidateName.isNotEmpty)
        data.candidateName,
      if (data.link != null) data.link!,
    ];
    return lines.join('\n');
  }

  /// Rebuilds the caption whenever the underlying data changes, as long as the
  /// user has not edited it.
  ///
  /// The previous version seeded the caption once, during the provider's loading
  /// state, so it permanently read "Roll — · verified on ExamVault" even after the
  /// vault resolved.
  void _syncCaption(ShareCardData? data) {
    if (_captionTouched) return;
    final next = data == null ? '' : _defaultCaption(data);
    if (_captionController.text != next) {
      _captionController.text = next;
    }
  }

  /// Syncs the caption, resetting "edited" when the exam itself changes.
  ///
  /// Bug: `_captionTouched` was never cleared, so after switching from one exam
  /// to another the old exam's caption stayed on screen forever.
  void _syncCaptionFor(String? examId, ShareCardData? data) {
    if (examId != _captionExamId) {
      _captionExamId = examId;
      _captionTouched = false;
    }
    _syncCaption(data);
  }

  /// The caption exactly as it leaves the app — shared, and copied.
  ///
  /// An untouched caption is machine-generated, so appending the link there is
  /// a safety net (one generated before the link was known would otherwise go
  /// out without it). A *touched* caption is the user's own text: if they
  /// deleted the link, `_withUrl` used to re-append it at share AND copy time,
  /// silently overruling a deliberate edit. The user's words go out verbatim.
  String _outgoingCaption(ShareCardData data) {
    final caption = _captionController.text.trim().isEmpty
        ? _defaultCaption(data)
        : _captionController.text.trim();
    return _captionTouched ? caption : _withUrl(caption, data);
  }

  String _withUrl(String caption, ShareCardData data) {
    final url = data.link;
    if (url == null || url.isEmpty) return caption;
    if (caption.contains(url)) return caption;
    return '$caption\n\n$url';
  }

  Future<void> _share(ShareCardData data) async {
    // Re-entrancy guard: the tile and the primary button both land here, and a
    // second tap while the sheet is opening must not start a second share.
    if (_sharing) return;
    setState(() => _sharing = true);

    final share = ref.read(shareServiceProvider);
    final caption = _outgoingCaption(data);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    try {
      // Bug: one 3x capture either blew the bitmap budget on a low-memory phone
      // or silently dropped the image. Retry smaller before giving up on it.
      Uint8List? png;
      for (final ratio in const [3.0, 2.0, 1.0]) {
        png = await share.capturePng(_boundaryKey, pixelRatio: ratio);
        if (png != null) break;
      }

      if (png == null) {
        // Bug: this fallback was silent, so the user thought the image had been
        // sent. A text share still gets the job done — and now says so.
        await _shareTextFallback(
          share,
          caption,
          data,
          origin,
          reason: 'The card image could not be rendered',
        );
      } else {
        try {
          await share.shareCardImage(
            png: png,
            caption: caption,
            subject: data.examName,
            origin: origin,
            fileName: 'examvault_${DateTime.now().millisecondsSinceEpoch}.png',
          );
        } catch (e, st) {
          // Bug: a platform that refused the image handoff (share sheet would
          // not open; a browser without Web Share file support) landed in the
          // generic catch below and the successfully captured PNG was silently
          // discarded. The bytes cannot survive this frame, but the caption
          // carries the same information — send it instead of losing both.
          AppLogger.e('share', 'image share failed after capture', e, st);
          await _shareTextFallback(
            share,
            caption,
            data,
            origin,
            reason: 'The card image could not be sent',
          );
        }
      }
    } catch (e, st) {
      // Bug: a failed share left the button spinning with no explanation. The
      // caption is still in the editor, so tell the user what to do next.
      AppLogger.e('share', 'share failed', e, st);
      _showSnack(
        'Could not open the share sheet. Your caption is still here — '
        'try again.',
      );
    } finally {
      // Native wrote the PNG into the cache dir; prune it so repeated shares
      // do not accumulate images. Web never touches the disk, so skip the
      // (no-op) walk there. Best-effort and never throwing, hence unawaited.
      if (!kIsWeb) unawaited(share.clearCache());
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Sends the caption as plain text and says so. Both fallback paths (capture
  /// failed / image handoff failed) must be audible: a silent downgrade lets
  /// the user believe the image went out.
  Future<void> _shareTextFallback(
    ShareService share,
    String caption,
    ShareCardData data,
    Rect? origin, {
    required String reason,
  }) async {
    await share.shareText(
      caption: caption,
      subject: data.examName,
      origin: origin,
    );
    _showSnack('$reason — shared the message text instead.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
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
    final update = ref.watch(resultExamIdProvider);
    final cardsAsync = ref.watch(admitCardsProvider);
    final cards = cardsAsync.value ?? const <AdmitCard>[];
    final selectedId = ref.watch(selectedCardIdProvider);
    final card = _cardFor(cards, update, selectedId);
    final examId = update?.examId ?? card?.examId;
    final checkState = ref.watch(resultCheckerProvider);
    // Bug: the globally last lookup was rendered on whatever exam this screen
    // happened to resolve. Only a verdict that belongs to this exam is used.
    final lookup = examId != null && checkState.belongsTo(examId)
        ? checkState.result
        : null;
    final built = _buildCard(update, card, lookup);
    // Withholding the roll must also stop the caption from repeating it.
    final data = (built == null || _showRoll)
        ? built
        : built.copyWith(rollNumber: '', selected: false);

    // Bug: the caption was rewritten inside build(), so the controller was
    // reset to the generated text before the user's edit could survive a
    // rebuild. Sync after the frame instead, and only while untouched.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncCaptionFor(examId, data);
    });

    if (data == null) {
      // Bug: loading and error states were both collapsed into an empty list,
      // so a slow or failed vault read looked like "nothing to share yet".
      final Widget body;
      if (cardsAsync.isLoading) {
        body = const _ShareLoading();
      } else if (cardsAsync.hasError) {
        body = _ShareError(onRetry: () => ref.invalidate(admitCardsProvider));
      } else {
        body = _NothingToShare(
          onAddCard: () => showVaultFormSheet(context, ref),
          // Home, not the Radar tab: this state means nothing is tapped and
          // nothing is saved, and the checker then shows an empty form whose
          // own advice is "open a result from Home" — the button used to route
          // into a dead end that pointed back here.
          onOpenRadar: () =>
              ref.read(tabIndexProvider.notifier).select(EvTab.home),
        );
      }
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            children: [
              _ShareNavBar(),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ShareNavBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EvSpace.gutter,
                8,
                EvSpace.gutter,
                0,
              ),
              child: Column(
                children: [
                  // The captured widget. Everything inside is theme-independent
                  // so the exported PNG looks identical in any chat client.
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: ShareInfographic(data: data),
                  ),
                  const SizedBox(height: EvSpace.x5),
                  _ShareTargets(
                    onShare: () => _share(data),
                    sharing: _sharing,
                    linkIsOfficial: data.linkIsOfficial,
                    onCopyCaption: () => ClipboardService.copy(
                      context,
                      value: _outgoingCaption(data),
                      label: 'Caption',
                    ),
                    // Never a dead button: with no app URL we copy the
                    // commission's own link, which is what a study group
                    // actually needs.
                    onCopyLink: data.link == null
                        ? null
                        : () => ClipboardService.copy(
                            context,
                            value: data.link!,
                            label: data.linkIsOfficial
                                ? 'Official result link'
                                : 'Share link',
                          ),
                  ),
                  const SizedBox(height: EvSpace.x4),
                  _CaptionEditor(
                    controller: _captionController,
                    onChanged: () {
                      _captionTouched = true;
                    },
                  ),
                  const SizedBox(height: EvSpace.x3),
                  _RollVisibilityRow(
                    value: _showRoll,
                    onChanged: (v) => setState(() {
                      _showRoll = v;
                      if (!v) {
                        // OFF: privacy outranks customisation. _syncCaption
                        // skips touched captions, so an edited caption could
                        // keep quoting the roll in the shared *text* after
                        // this switch hid it from the *image* — broadcasting
                        // exactly what the user asked to withhold. Only this
                        // direction sacrifices the edit: reset the flag and
                        // the next frame regenerates from scrubbed data, so
                        // card and text always agree.
                        _captionTouched = false;
                      }
                      // ON: nothing to scrub. An edited caption is the user's
                      // own text — the old reset in BOTH directions destroyed
                      // it here for no reason privacy can claim, and the
                      // regenerated default would re-add a roll line the user
                      // may have deliberately removed. Touched captions pass
                      // through untouched; an untouched one regenerates from
                      // the roll-bearing data via _syncCaption.
                    }),
                    hasRoll: built?.rollNumber.isNotEmpty ?? false,
                    hidden:
                        !_showRoll && (built?.rollNumber.isNotEmpty ?? false),
                  ),
                  const SizedBox(height: EvSpace.x4),
                  EvPrimaryButton(
                    label: 'Share to study group',
                    icon: Icons.ios_share_rounded,
                    busy: _sharing,
                    onPressed: () => _share(data),
                  ),
                  SizedBox(height: EvChrome.bottomInset(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareNavBar extends ConsumerWidget {
  const _ShareNavBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    return ConstrainedBox(
      // A floor, not a fixed height. At a fixed 40px this bar squeezed its own
      // 44px icon buttons down to 40, so back/close missed the 44px minimum.
      constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              const SizedBox(width: EvSpace.x2),
              EvIconButton(
                icon: Icons.close_rounded,
                ghost: true,
                iconSize: 18,
                tooltip: 'Close',
                // Same defect as the checker: a tab has no route to pop, so this
                // × did nothing and system back quit the app instead.
                onPressed: () =>
                    ref.read(tabIndexProvider.notifier).select(EvTab.home),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: EvSpace.x4),
                child: Container(
                  // minHeight + min-sized Row child, never `alignment:` — an
                  // aligned Container inside a Row expands to the row's free
                  // width; this pill was rendering hundreds of px wide, and a
                  // fixed 24px height sliced the label at large text scales.
                  constraints: const BoxConstraints(minHeight: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: p.surfaceSunken,
                    borderRadius: BorderRadius.circular(EvRadius.pill),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PREVIEW',
                        maxLines: 1,
                        style: context.type.statusPill.copyWith(
                          letterSpacing: 1.1,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: Padding(
              // Same guard as the checker's nav bar: title and pill are
              // independent Stack children and overlapped on a 320px screen at
              // 2.0x text. The title owns only the space between × and pill.
              padding: const EdgeInsets.symmetric(horizontal: 96),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Share Card',
                    maxLines: 1,
                    style: context.type.navTitle,
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

class _ShareTargets extends StatelessWidget {
  const _ShareTargets({
    required this.onShare,
    required this.onCopyLink,
    required this.onCopyCaption,
    required this.linkIsOfficial,
    this.sharing = false,
  });

  final VoidCallback onShare;

  /// Copies the editable caption. Useful on its own: a student may want the text
  /// in a group without the image.
  final VoidCallback? onCopyCaption;

  /// Null when we have no link at all — the tile is then disabled rather than
  /// copying an empty string.
  final VoidCallback? onCopyLink;

  /// True when the copied link is the commission's own, so the tile says so.
  final bool linkIsOfficial;

  /// True while a share is in flight. `_share()` already ignores re-entrant
  /// taps, but the tile must also *look* inert — a button that silently
  /// swallows taps invites exactly the double-tap it guards against.
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // These tiles used to say WhatsApp / Telegram / Save PNG and all three
        // called the same generic share sheet. A tile labelled "Save PNG" that
        // opens a share sheet is a broken promise, and two coloured tiles for
        // apps we cannot target directly were decoration. The real actions are
        // the ones the platform actually supports.
        _Target(
          label: 'Share card',
          icon: Icons.chat_rounded,
          // Bug: this tile still wore WhatsApp's brand green (#25D366) after
          // the WhatsApp-targeted tile was merged into the generic share
          // sheet — a brand colour for an action that opens whatever sheet the
          // platform provides, and on web is not WhatsApp at all.
          color: p.accentText,
          highlight: true,
          onTap: onShare,
          enabled: !sharing,
        ),
        _Target(
          label: 'Copy caption',
          icon: Icons.content_copy_rounded,
          color: onCopyCaption == null ? p.textTertiary : p.accentText,
          onTap: onCopyCaption ?? () {},
          enabled: onCopyCaption != null,
        ),
        _Target(
          // Bug: the tile said "Official link" but only copied it. Name the
          // action that actually happens.
          label: linkIsOfficial ? 'Copy official link' : 'Copy link',
          icon: Icons.link_rounded,
          color: onCopyLink == null ? p.textTertiary : p.accentText,
          onTap: onCopyLink ?? () {},
          enabled: onCopyLink != null,
        ),
      ],
    );
  }
}

class _Target extends StatelessWidget {
  const _Target({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.highlight = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool highlight;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      button: true,
      enabled: enabled,
      // The visible label Text below is the single accessible name; a
      // Semantics label on top made TalkBack read every tile twice.
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(EvRadius.inner),
          child: SizedBox(
            // Wider than 76 so "Copy official link" can wrap to two honest
            // lines instead of being clipped into an unreadable fragment.
            width: 88,
            child: Column(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: highlight
                        ? color.withValues(alpha: 0.12)
                        : p.surface,
                    borderRadius: BorderRadius.circular(EvRadius.inner),
                    border: Border.all(
                      color: highlight
                          ? color.withValues(alpha: 0.34)
                          : p.border,
                    ),
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.label.copyWith(
                    color: highlight ? p.textPrimary : p.textSecondary,
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

class _CaptionEditor extends StatefulWidget {
  const _CaptionEditor({required this.controller, this.onChanged});

  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<_CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<_CaptionEditor> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return EvCard(
      // Matches the roll-visibility card below it: the two adjacent cards used
      // to disagree (14/10/10/10 vs 14/12), so their content edges did not line up.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MESSAGE CAPTION', style: context.type.microLabel),
              ),
              Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                label: _editing ? 'Done editing caption' : 'Edit caption',
                // InkWell, not a bare GestureDetector: the toggle gave zero
                // pressed feedback, so a slow first frame made it feel dead
                // and users tapped it twice. The enclosing EvCard supplies
                // the Material the ink paints on.
                child: InkWell(
                  onTap: () => setState(() => _editing = !_editing),
                  borderRadius: BorderRadius.circular(EvRadius.inner),
                  // Fixed 48x44 box, NOT a constraints+alignment Container: an
                  // aligned Container inside a Row expands to the row's free
                  // width — the previous "minWidth 44 + alignment" version
                  // ballooned and starved the "MESSAGE CAPTION" label beside it
                  // to zero width. A SizedBox cannot expand.
                  child: SizedBox(
                    width: 48,
                    height: EvSize.minTapTarget,
                    child: Center(
                      // Scaled to fit: at 2.0x the 11px label is ~62px wide and
                      // was clipped mid-word inside the fixed 48px box.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _editing ? 'DONE' : 'EDIT',
                          maxLines: 1,
                          style: context.type.statusPill.copyWith(
                            color: p.accentText,
                            fontSize: 11,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_editing)
            TextField(
              controller: widget.controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              // Bug: this field never reported edits, so the screen never learned
              // the caption was touched and rebuilt the user's text away.
              onChanged: (_) => widget.onChanged?.call(),
              style: context.type.body.copyWith(
                color: p.textPrimary,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 10,
                ),
              ),
            )
          else
            // The caption is seeded after the frame, so the preview must listen
            // to the controller or it would show the previous exam's text.
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => Text(
                widget.controller.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.type.body.copyWith(
                  color: p.textPrimary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RollVisibilityRow extends StatelessWidget {
  const _RollVisibilityRow({
    required this.value,
    required this.onChanged,
    required this.hasRoll,
    required this.hidden,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// False when there is no roll to show, so the switch is not offered as if it
  /// controlled something.
  final bool hasRoll;

  /// True when a roll exists but the user turned it off. Distinct from "no roll
  /// checked yet", which is what the old copy implied for both cases.
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return EvCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Show my roll number',
                  style: context.type.tileTitle.copyWith(),
                ),
                const SizedBox(height: 2),
                Text(
                  !hasRoll
                      ? 'No roll number checked yet'
                      : hidden
                      // The old copy ("the card still shows the result") read
                      // as if nothing changed; hiding the roll removes the
                      // entire dark result block, so say exactly that.
                      ? 'Hidden — the card shows the result without your roll'
                      : 'Visible on the card you share',
                  style: context.type.bodyMuted.copyWith(),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Show my roll number on the shared card',
            child: Switch.adaptive(
              value: hasRoll && value,
              onChanged: hasRoll ? onChanged : null,
              activeTrackColor: p.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the vault is still being read, so a slow first frame does not
/// masquerade as an empty vault.
class _ShareLoading extends StatelessWidget {
  const _ShareLoading();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return EvCenteredScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(p.accentText),
            ),
          ),
          const SizedBox(height: 12),
          Text('Loading your saved cards…', style: context.type.bodyMuted),
        ],
      ),
    );
  }
}

/// A failed vault read is not the same as an empty vault.
class _ShareError extends StatelessWidget {
  const _ShareError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return EvCenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: p.danger, size: 28),
          const SizedBox(height: 16),
          Text(
            'Could not load your saved cards',
            textAlign: TextAlign.center,
            style: context.type.sectionTitle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Your vault is stored on this device. Nothing was lost — try '
            'again in a moment.',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
          const SizedBox(height: 20),
          EvSecondaryButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            expand: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Shown when there is neither a radar row nor a saved card to talk about.
class _NothingToShare extends StatelessWidget {
  const _NothingToShare({required this.onAddCard, required this.onOpenRadar});

  final VoidCallback onAddCard;
  final VoidCallback onOpenRadar;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return EvCenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(EvRadius.inner),
            ),
            child: Icon(Icons.ios_share_rounded, color: p.accentText, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing to share yet',
            textAlign: TextAlign.center,
            style: context.type.sectionTitle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'A share card is built from a result on the Radar, or from your own '
            'saved admit card. Add one and this screen fills itself in.',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
          const SizedBox(height: 20),
          EvPrimaryButton(
            label: 'Add an admit card',
            icon: Icons.add_rounded,
            expand: false,
            onPressed: onAddCard,
          ),
          const SizedBox(height: 8),
          EvSecondaryButton(
            label: 'Browse live results',
            icon: Icons.radar_rounded,
            expand: false,
            onPressed: onOpenRadar,
          ),
        ],
      ),
    );
  }
}
