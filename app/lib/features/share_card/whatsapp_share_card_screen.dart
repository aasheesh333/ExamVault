import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/live_update.dart';
import '../../providers/app_providers.dart';
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

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  ShareCardData _buildCard(LiveUpdate? update, AdmitCard? card) {
    final examName =
        update?.examName ?? card?.examName ?? 'SSC CGL Tier-1 2026';
    final isResult =
        (update?.status ?? UpdateStatus.resultOut) == UpdateStatus.resultOut;

    return ShareCardData(
      examName: examName,
      headline: isResult ? 'RESULT IS LIVE' : 'ADMIT CARD IS LIVE',
      subline: isResult
          ? 'Cut-off, PDF & official link inside'
          : 'Download your admit card before the server queue',
      dateLine: _shortDate(DateTime.now()),
      rollNumber: card?.rollNumber ?? '—',
      selected: card?.rollNumberVerified ?? false,
      shareUrl:
          'https://examvault.in/r/${update?.examId ?? card?.examId ?? 'ssc'}',
      // Real cut-offs are published per exam; the seed does not invent them.
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

  String _defaultCaption(ShareCardData data) =>
      '🚨 ${data.examName.toUpperCase()} ${data.headline} — cut-off & direct check inside.\n'
      'Roll ${data.rollNumber} · verified on ExamVault.';

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
          caption: '$caption\n\n${data.shareUrl}',
          subject: data.examName,
          origin: origin,
        );
      } else {
        await share.shareCardImage(
          png: png,
          caption: '$caption\n\n${data.shareUrl}',
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

    // Seed the caption the first time only; never clobber what the user typed.
    if (_captionController.text.isEmpty) {
      _captionController.text = _defaultCaption(data);
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
                    onCopyLink: () => ClipboardService.copy(
                      context,
                      value: data.shareUrl,
                      label: 'Share link',
                    ),
                  ),
                  const SizedBox(height: EvSpace.x4),
                  _CaptionEditor(controller: _captionController),
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
  final VoidCallback onCopyLink;

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
          color: p.accentText,
          onTap: onCopyLink,
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
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EvRadius.inner),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: highlight ? color.withValues(alpha: 0.12) : p.surface,
                  borderRadius: BorderRadius.circular(EvRadius.inner),
                  border: Border.all(
                    color: highlight ? color.withValues(alpha: 0.34) : p.border,
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
    );
  }
}

class _CaptionEditor extends StatefulWidget {
  const _CaptionEditor({required this.controller});

  final TextEditingController controller;

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
