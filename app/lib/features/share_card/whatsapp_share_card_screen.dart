import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
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

    final isResult =
        (update?.status ?? UpdateStatus.resultOut) == UpdateStatus.resultOut;

    // A student who checked straight from the radar has no saved card, but they
    // do have a verified roll number and a reason to celebrate. Before this,
    // "Share the news" led to a card with no roll on it.
    final lookedUp = lookup != null && lookup.isFound ? lookup : null;
    final roll = card?.rollNumber ?? lookedUp?.rollNumber ?? '';
    final verified = card?.rollNumberVerified ?? lookedUp != null;

    return ShareCardData(
      examName: examName,
      headline: isResult ? 'RESULT IS LIVE' : 'ADMIT CARD IS LIVE',
      // Never promise content the card does not carry: there are no cut-offs in
      // this feed, and the official document is a link, not an attachment.
      subline: isResult
          ? 'Official link & instant roll-number check'
          : 'Admit card link & exam-day details',
      dateLine: _shortDate(DateTime.now()),
      // Empty when we do not have the user's roll — never a "—" placeholder.
      rollNumber: roll,
      selected: verified,
      shareUrl: ref.read(resultIndexRepositoryProvider).shareUrl(examId),
      officialUrl: update?.officialUrl,
      // Cut-offs are only shown when a publisher actually released them.
      cutoffs: null,
      pdfSizeLabel: update?.pdfSizeLabel,
    );
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
      '🚨 ${data.examName.toUpperCase()} ${data.headline} — official link & '
          'instant roll-number check.',
      if (data.rollNumber.isNotEmpty)
        'Roll ${data.rollNumber}${data.selected ? ' · in the published list' : ''}',
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

  String _withUrl(String caption, ShareCardData data) {
    final url = data.link;
    if (url == null || url.isEmpty) return caption;
    if (caption.contains(url)) return caption;
    return '$caption\n\n$url';
  }

  Future<void> _share(ShareCardData data) async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final share = ref.read(shareServiceProvider);
    final caption = _captionController.text.trim().isEmpty
        ? _defaultCaption(data)
        : _captionController.text.trim();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    try {
      final png = await share.capturePng(_boundaryKey, pixelRatio: 3.0);
      if (png == null) {
        // Capture can fail on very low memory; a text share still gets the job
        // done, so the CTA never dead-ends.
        await share.shareText(
          caption: _withUrl(caption, data),
          subject: data.examName,
          origin: origin,
        );
      } else {
        await share.shareCardImage(
          png: png,
          caption: _withUrl(caption, data),
          subject: data.examName,
          origin: origin,
          fileName: 'examvault_${DateTime.now().millisecondsSinceEpoch}.png',
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final update = ref.watch(resultExamIdProvider);
    final cards = ref.watch(admitCardsProvider).value ?? const <AdmitCard>[];
    final card = cards.isEmpty ? null : cards.first;
    final lookup = ref.watch(resultCheckerProvider).result;
    final built = _buildCard(update, card, lookup);
    // Withholding the roll must also stop the caption from repeating it.
    final data = (built == null || _showRoll)
        ? built
        : built.copyWith(rollNumber: '', selected: false);

    // Keep the caption in sync with the data, unless the user edited it.
    _syncCaption(data);

    if (data == null) {
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            children: [
              _ShareNavBar(),
              Expanded(
                child: _NothingToShare(
                  onAddCard: () => showVaultFormSheet(context, ref),
                  onOpenRadar: () =>
                      ref.read(tabIndexProvider.notifier).select(EvTab.radar),
                ),
              ),
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
                    linkIsOfficial: data.linkIsOfficial,
                    onCopyCaption: () => ClipboardService.copy(
                      context,
                      value: _withUrl(
                        _captionController.text.trim().isEmpty
                            ? _defaultCaption(data)
                            : _captionController.text.trim(),
                        data,
                      ),
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
                  const SizedBox(height: 10),
                  _RollVisibilityRow(
                    value: _showRoll,
                    onChanged: (v) => setState(() => _showRoll = v),
                    hasRoll: built?.rollNumber.isNotEmpty ?? false,
                    hidden:
                        !_showRoll && (built?.rollNumber.isNotEmpty ?? false),
                  ),
                  const SizedBox(height: 14),
                  EvPrimaryButton(
                    label: 'Share to study group',
                    icon: Icons.ios_share_rounded,
                    busy: _sharing,
                    onPressed: () => _share(data),
                  ),
                  const SizedBox(height: 130),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareNavBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return SizedBox(
      height: EvSize.navBar,
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
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: EvSpace.x4),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.surfaceSunken,
                    borderRadius: BorderRadius.circular(EvRadius.pill),
                    border: Border.all(color: p.border),
                  ),
                  child: Text(
                    'PREVIEW',
                    style: context.type.statusPill.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text('Share Card', style: context.type.navTitle),
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
          color: const Color(0xFF25D366),
          highlight: true,
          onTap: onShare,
        ),
        _Target(
          label: 'Copy caption',
          icon: Icons.content_copy_rounded,
          color: onCopyCaption == null ? p.textTertiary : p.accentText,
          onTap: onCopyCaption ?? () {},
          enabled: onCopyCaption != null,
        ),
        _Target(
          label: linkIsOfficial ? 'Official link' : 'Copy link',
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
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(EvRadius.inner),
          child: SizedBox(
            width: 76,
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
                  maxLines: 1,
                  style: context.type.label.copyWith(
                    fontSize: 10,
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
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MESSAGE CAPTION', style: context.type.microLabel),
              ),
              GestureDetector(
                onTap: () => setState(() => _editing = !_editing),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    _editing ? 'DONE' : 'EDIT',
                    style: context.type.statusPill.copyWith(
                      color: p.accentText,
                      fontSize: 9,
                      letterSpacing: 0.9,
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
              style: context.type.body.copyWith(
                color: p.textPrimary,
                fontSize: 11.5,
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
            Text(
              widget.controller.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.type.body.copyWith(
                color: p.textPrimary,
                fontSize: 11.5,
                height: 1.4,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Show my roll number',
                  style: context.type.tileTitle.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 2),
                Text(
                  !hasRoll
                      ? 'No roll number checked yet'
                      : hidden
                      ? 'Hidden — the card still shows the result'
                      : 'Visible on the card you share',
                  style: context.type.bodyMuted.copyWith(fontSize: 9.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: hasRoll && value,
            onChanged: hasRoll ? onChanged : null,
            activeTrackColor: p.success,
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(EvRadius.inner),
              ),
              child: Icon(
                Icons.ios_share_rounded,
                color: p.accentText,
                size: 24,
              ),
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
              label: 'Open Radar',
              icon: Icons.radar_rounded,
              expand: false,
              onPressed: onOpenRadar,
            ),
          ],
        ),
      ),
    );
  }
}
