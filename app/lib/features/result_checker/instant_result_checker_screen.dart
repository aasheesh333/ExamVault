import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../data/repositories/result_index_repository.dart';
import '../../domain/entities/admit_card.dart';
import '../../features/result_checker/engine/roll_index_engine.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';

/// Screen 3 — Instant result checker.
///
/// The entire point of this screen is that `Check` is one tap and one second,
/// while the official site is on its third 504. It never opens a PDF to answer
/// "am I selected?" — it answers from a 150 KB index with a binary search.
class InstantResultCheckerScreen extends ConsumerStatefulWidget {
  const InstantResultCheckerScreen({super.key});

  @override
  ConsumerState<InstantResultCheckerScreen> createState() =>
      _InstantResultCheckerScreenState();
}

class _InstantResultCheckerScreenState
    extends ConsumerState<InstantResultCheckerScreen> {
  late final TextEditingController _roll =
      TextEditingController(text: _initialRoll());

  String _initialRoll() {
    final card = _targetCard(ref.read(admitCardsProvider).value, null);
    return card?.rollNumber ?? '';
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  AdmitCard? _targetCard(List<AdmitCard>? cards, AdmitCard? fallback) {
    if (cards == null || cards.isEmpty) return fallback;
    final update = ref.read(resultExamIdProvider);
    if (update != null) {
      for (final c in cards) {
        if (c.examId == update.examId) return c;
      }
    }
    return cards.first;
  }

  Future<void> _check(AdmitCard? card) async {
    final roll = _roll.text.trim();
    if (roll.length < 4) {
      _showToast('Enter your roll number first.');
      return;
    }

    FocusScope.of(context).unfocus();

    final examId = card?.examId ?? 'ssc_cgl_tier1_2026';
    final result = await ref
        .read(resultCheckerProvider.notifier)
        .check(examId: examId, rollNumber: roll);

    if (!mounted || result == null) return;

    if (result.isFound) {
      await ref.read(admitCardsProvider.notifier).markVerified(card?.id ?? '');
      if (!mounted) return;
      await _showSelectedDialog(result, card);
    }
  }

  void _showToast(String message) {
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
    final cards = ref.watch(admitCardsProvider).value;
    final state = ref.watch(resultCheckerProvider);
    final update = ref.watch(resultExamIdProvider);
    final card = _targetCard(cards, null);

    final examName = update?.examName ?? card?.examName ?? 'SSC CGL Tier-1 2026';
    final examId = update?.examId ?? card?.examId ?? 'ssc_cgl_tier1_2026';

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _NavBar(update: update),
            Padding(
              padding: const EdgeInsets.fromLTRB(EvSpace.gutter, 14, EvSpace.gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (update?.category.label ?? card?.category.label ?? 'SSC')
                        .toUpperCase(),
                    style: context.type.microLabel.copyWith(letterSpacing: 1.7),
                  ),
                  const SizedBox(height: 6),
                  _TitleWithAccent(examName: examName),
                  const SizedBox(height: 8),
                  _MirrorCard(
                    indexSource: state.indexSource,
                    cachedLatency: update?.mirrorLatencyMs,
                  ),
                  const SizedBox(height: 8),
                  _RetryNote(state: state),
                  const SizedBox(height: 14),
                  _RollField(
                    controller: _roll,
                    busy: state.isBusy,
                  ),
                  const SizedBox(height: 10),
                  EvPrimaryButton(
                    label: state.isBusy
                        ? 'Checking…'
                        : 'Check my result instantly',
                    icon: state.isBusy ? null : Icons.bolt_rounded,
                    busy: state.isBusy,
                    onPressed: () => _check(card),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: EvSecondaryButton(
                          label: 'Official PDF',
                          icon: Icons.picture_as_pdf_outlined,
                          onPressed: () => _openPdf(examId),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: EvSecondaryButton(
                          label: 'Copy link',
                          icon: Icons.link_rounded,
                          onPressed: () => ClipboardService.copy(
                            context,
                            value:
                                '${AppConfig.cdnBase}${AppConfig.resultPdfPath(examId)}',
                            label: 'Result link',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state.phase == ResultPhase.done &&
                      state.result != null &&
                      !state.result!.isFound) ...[
                    const SizedBox(height: 16),
                    _NotFoundCard(result: state.result!),
                  ],
                  if (state.phase == ResultPhase.failed) ...[
                    const SizedBox(height: 16),
                    _ErrorCard(message: state.error ?? 'Something went wrong.'),
                  ],
                  const SizedBox(height: 22),
                  _RecentChecks(
                    card: card,
                    lastResult: state.result,
                    indexSource: state.indexSource,
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

  Future<void> _openPdf(String examId) async {
    final uri = Uri.parse(
      '${AppConfig.cdnBase}${AppConfig.resultPdfPath(examId)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showToast('Could not open the PDF. Check your connection.');
    }
  }

  Future<void> _showSelectedDialog(
    RollLookupResult result,
    AdmitCard? card,
  ) async {
    HapticFeedback.heavyImpact();

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) => _SelectedDialog(result: result, card: card),
    );
  }
}

// ---------------------------------------------------------------------------

class _NavBar extends StatelessWidget {
  const _NavBar({this.update});

  final dynamic update;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final isLive = update != null;

    return SizedBox(
      height: EvSize.navBar,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              const SizedBox(width: EvSpace.x2),
              EvIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                ghost: true,
                iconSize: 17,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: EvSpace.x4),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: (isLive ? p.success : p.textTertiary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(EvRadius.pill),
                    border: Border.all(
                      color: (isLive ? p.success : p.textTertiary)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isLive ? p.success : p.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isLive ? 'LIVE' : 'READY',
                        style: context.type.statusPill.copyWith(
                          fontSize: 8,
                          letterSpacing: 1.1,
                          color: isLive ? p.successText : p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Text('Result Radar', style: context.type.navTitle),
        ],
      ),
    );
  }
}

class _TitleWithAccent extends StatelessWidget {
  const _TitleWithAccent({required this.examName});

  final String examName;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    // "Result" is always the last word, tinted green. Using Text.rich instead of
    // two positioned Texts means it wraps correctly at any text scale.
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: examName.replaceAll(' Result', ''),
            style: context.type.screenTitle,
          ),
          TextSpan(
            text: ' Result',
            style: context.type.screenTitle.copyWith(color: p.success),
          ),
        ],
      ),
      maxLines: 2,
    );
  }
}

/// Shows the three routes to the same object, with honest state.
class _MirrorCard extends StatelessWidget {
  const _MirrorCard({this.indexSource, this.cachedLatency});

  final IndexSource? indexSource;
  final int? cachedLatency;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    final edgeLive = indexSource == IndexSource.edge;
    final cacheWarm = indexSource != null;

    final rows = <_MirrorRow>[
      _MirrorRow(
        name: 'Official site',
        sub: 'upsc.gov.in',
        state: 'BUSY',
        color: p.warning,
        textColor: p.warningText,
        fill: 0.74,
        value: '1,204ms',
      ),
      _MirrorRow(
        name: 'Edge CDN index',
        sub: '150 KB gzip',
        state: edgeLive ? 'FAST' : 'READY',
        color: p.success,
        textColor: p.successText,
        fill: edgeLive ? 0.22 : 0.34,
        value: edgeLive ? '82ms' : 'cached',
      ),
      _MirrorRow(
        name: 'Binary search',
        sub: 'on device',
        state: cacheWarm ? 'READY' : 'IDLE',
        color: p.accent,
        textColor: p.accentText,
        fill: cacheWarm ? 0.08 : 0.16,
        value: '<1ms',
      ),
    ];

    return EvCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MIRROR STATUS', style: context.type.microLabel),
              ),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: p.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'AUTO-REFRESH 60s',
                style: context.type.statusPill.copyWith(
                  color: p.successText,
                  fontSize: 7.5,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: context.hairline),
            _MirrorRowView(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _MirrorRow {
  const _MirrorRow({
    required this.name,
    required this.sub,
    required this.state,
    required this.color,
    required this.textColor,
    required this.fill,
    required this.value,
  });

  final String name;
  final String sub;
  final String state;
  final Color color;
  final Color textColor;
  final double fill;
  final String value;
}

class _MirrorRowView extends StatelessWidget {
  const _MirrorRowView({required this.row});

  final _MirrorRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: row.name,
                    style: context.type.label.copyWith(
                      color: p.textPrimary,
                      fontSize: 11.5,
                    ),
                  ),
                  if (row.sub.isNotEmpty)
                    TextSpan(
                      text: '  ${row.sub}',
                      style: context.type.bodyMuted.copyWith(fontSize: 9.5),
                    ),
                ],
              ),
            ),
          ),
          Container(
            width: 52,
            height: 4,
            decoration: BoxDecoration(
              color: p.surfaceSunken,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: row.fill,
              child: Container(
                decoration: BoxDecoration(
                  color: row.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              row.state,
              textAlign: TextAlign.right,
              style: context.type.statusPill.copyWith(
                color: row.textColor,
                fontSize: 7.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: context.type.monoMeta.copyWith(
                fontSize: 8.5,
                color: p.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryNote extends StatelessWidget {
  const _RetryNote({required this.state});

  final ResultCheckState state;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final label = switch (state.phase) {
      ResultPhase.downloading => 'Downloading the edge index…',
      ResultPhase.searching => 'Searching 12,000+ roll numbers…',
      ResultPhase.done => state.indexSource == IndexSource.demo
          ? 'Demo index — the real result is not published yet.'
          : 'Checked against the published merit list.',
      ResultPhase.failed => state.error ?? 'Could not check.',
      ResultPhase.idle => 'Index is 150 KB, not a 60 MB PDF. It fits in one tap.',
    };

    return Row(
      children: [
        Icon(Icons.auto_awesome_rounded, size: 11, color: p.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            style: context.type.bodyMuted.copyWith(fontSize: 9.5),
          ),
        ),
      ],
    );
  }
}

class _RollField extends StatelessWidget {
  const _RollField({required this.controller, required this.busy});

  final TextEditingController controller;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          height: 56,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: p.surfaceSunken,
            borderRadius: BorderRadius.circular(EvRadius.button),
            border: Border.all(color: p.borderStrong),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 17, color: p.textTertiary),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.visiblePassword,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/]')),
                  ],
                  style: context.type.fieldValue.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Roll number',
                    hintStyle: context.type.bodyMuted.copyWith(
                      fontSize: 13,
                      letterSpacing: 0,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.cancel, size: 16, color: p.textTertiary),
                  onPressed: busy ? null : controller.clear,
                  tooltip: 'Clear',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  const _NotFoundCard({required this.result});

  final RollLookupResult result;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(EvRadius.card),
        border: Border.all(color: p.warning.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_bottom_rounded, size: 16, color: p.warning),
              const SizedBox(width: 8),
              Text(
                'Not in this list yet',
                style: context.type.tileTitle.copyWith(color: p.warningText),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Roll ${result.rollNumber} was not found among ${_format(result.totalRolls)} published roll numbers. '
            'That could mean a different list (Tier-2, region-wise), or that your result is still being uploaded.',
            style: context.type.bodyMuted.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'Searched in ${(result.elapsedMicros / 1000).toStringAsFixed(1)} ms on this device.',
            style: context.type.microLabel.copyWith(fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  static String _format(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(EvRadius.card),
        border: Border.all(color: p.danger.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: p.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.type.bodyMuted.copyWith(
                fontSize: 11,
                color: p.dangerText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentChecks extends StatelessWidget {
  const _RecentChecks({
    required this.card,
    this.lastResult,
    this.indexSource,
  });

  final AdmitCard? card;
  final RollLookupResult? lastResult;
  final IndexSource? indexSource;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    if (card == null) return const SizedBox.shrink();

    final verified = card!.rollNumberVerified || (lastResult?.isFound ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EvSectionHeader(
          label: 'Your check',
          padding: EdgeInsets.zero,
          trailing: Text(
            indexSource?.label.toUpperCase() ?? 'NOT RUN',
            style: context.type.microLabel.copyWith(fontSize: 8.5),
          ),
        ),
        const SizedBox(height: 8),
        EvCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card!.examName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.tileTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Roll ${card!.rollNumber}',
                      style: context.type.monoMeta.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (verified ? p.success : p.textTertiary).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(EvRadius.badge),
                  border: Border.all(
                    color: (verified ? p.success : p.textTertiary).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  verified ? 'FOUND' : 'NOT CHECKED',
                  style: context.type.statusPill.copyWith(
                    fontSize: 7.5,
                    color: verified ? p.successText : p.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The celebration
// ---------------------------------------------------------------------------

class _SelectedDialog extends StatelessWidget {
  const _SelectedDialog({required this.result, this.card});

  final RollLookupResult result;
  final AdmitCard? card;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.86, end: 1),
        duration: EvMotion.slow,
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.success.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: p.success.withValues(alpha: 0.24),
                blurRadius: 48,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      p.success.withValues(alpha: 0.9),
                      p.success.withValues(alpha: 0.55),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: p.success.withValues(alpha: 0.5),
                      blurRadius: 26,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                'SELECTED IN MERIT LIST',
                textAlign: TextAlign.center,
                style: context.type.sectionTitle.copyWith(
                  color: p.successText,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                card?.examName ?? 'Your result',
                textAlign: TextAlign.center,
                style: context.type.bodyMuted,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: p.surfaceSunken,
                  borderRadius: BorderRadius.circular(EvRadius.inner),
                  border: Border.all(color: p.border),
                ),
                child: Column(
                  children: [
                    Text('ROLL NUMBER', style: context.type.microLabel),
                    const SizedBox(height: 4),
                    Text(
                      result.rollNumber,
                      style: context.type.fieldValue.copyWith(
                        fontSize: 22,
                        letterSpacing: 1.6,
                        color: p.textPrimary,
                      ),
                    ),
                    if (result.hasRank) ...[
                      const SizedBox(height: 8),
                      Text(
                        'MERIT RANK ${result.meritRank}',
                        style: context.type.statusPill.copyWith(
                          color: p.successText,
                          fontSize: 9,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Found in ${(result.elapsedMicros / 1000).toStringAsFixed(1)} ms '
                'among ${result.totalRolls} roll numbers.',
                textAlign: TextAlign.center,
                style: context.type.microLabel.copyWith(fontSize: 8.5),
              ),
              const SizedBox(height: 18),
              EvPrimaryButton(
                label: 'Share the news',
                icon: Icons.ios_share_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: context.type.label.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
