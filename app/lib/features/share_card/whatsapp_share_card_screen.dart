import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/live_update.dart';
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

  bool _attachPdf = true;
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
  ShareCardData? _buildCard(LiveUpdate? update, AdmitCard? card) {
    final examName = update?.examName ?? card?.examName;
    final examId = update?.examId ?? card?.examId;
    if (examName == null || examId == null) return null;

    final isResult =
        (update?.status ?? UpdateStatus.resultOut) == UpdateStatus.resultOut;

    return ShareCardData(
      examName: examName,
      headline: isResult ? 'RESULT IS LIVE' : 'ADMIT CARD IS LIVE',
      subline: isResult
          ? 'Cut-off, PDF & official link inside'
          : 'Download your admit card before the server queue',
      dateLine: _shortDate(DateTime.now()),
      // Empty when we do not have the user's roll — never a "—" placeholder.
      rollNumber: card?.rollNumber ?? '',
      selected: card?.rollNumberVerified ?? false,
      shareUrl: ref.read(resultIndexRepositoryProvider).shareUrl(examId),
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
      '🚨 ${data.examName.toUpperCase()} ${data.headline} — cut-off & direct '
          'check inside.',
      if (data.rollNumber.isNotEmpty)
        'Roll ${data.rollNumber}${data.selected ? ' · found in the merit list' : ''}',
      if (data.shareUrl != null) data.shareUrl!,
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
    final url = data.shareUrl;
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
    final data = _buildCard(update, card);

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
                    onCopyLink: data.shareUrl == null
                        ? null
                        : () => ClipboardService.copy(
                            context,
                            value: data.shareUrl!,
                            label: 'Share link',
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
                  _AttachRow(
                    value: _attachPdf,
                    onChanged: (v) => setState(() => _attachPdf = v),
                    data: data,
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
                      fontSize: 8,
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
  const _ShareTargets({required this.onShare, required this.onCopyLink});

  final VoidCallback onShare;

  /// Null when no share URL is configured — the tile is then disabled rather
  /// than copying an empty string.
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Target(
          label: 'WhatsApp',
          icon: Icons.chat_rounded,
          color: const Color(0xFF25D366),
          highlight: true,
          onTap: onShare,
        ),
        _Target(
          label: 'Telegram',
          icon: Icons.send_rounded,
          color: const Color(0xFF54A9EB),
          onTap: onShare,
        ),
        _Target(
          label: 'Copy link',
          icon: Icons.link_rounded,
          color: onCopyLink == null ? p.textTertiary : p.accentText,
          onTap: onCopyLink ?? () {},
          enabled: onCopyLink != null,
        ),
        _Target(
          label: 'Save PNG',
          icon: Icons.download_rounded,
          color: p.textSecondary,
          onTap: onShare,
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
                      fontSize: 8.5,
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

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.value,
    required this.onChanged,
    required this.data,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final ShareCardData data;

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
                  'Attach PDF to message',
                  style: context.type.tileTitle.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'PDF + card image sent together'
                      : 'Card image and link only',
                  style: context.type.bodyMuted.copyWith(fontSize: 9.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
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
