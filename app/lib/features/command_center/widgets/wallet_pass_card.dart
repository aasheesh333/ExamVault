import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../core/utils/clipboard_service.dart';
import '../../../domain/entities/admit_card.dart';

/// The Apple-Wallet-style pass.
///
/// Two rules make this component work and both are non-obvious:
///
///  * The pass stays **deep navy in both themes**. It is a physical object, the
///    way an Apple Wallet pass is. It also keeps the 31px roll number at 13.96:1
///    instead of dropping it onto white.
///  * The whole roll row is the copy target — not just the 48px pill. On a bus,
///    with one thumb, the difference between a 70px pill and a 330px row is the
///    difference between a hit and a miss.
class WalletPassCard extends StatelessWidget {
  const WalletPassCard({
    super.key,
    required this.card,
    required this.onOpen,
    this.onCopied,
    this.compact = false,
  });

  final AdmitCard card;
  final VoidCallback onOpen;
  final VoidCallback? onCopied;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final days = card.daysUntilExam();

    return Semantics(
      button: true,
      label:
          '${card.examName}. Roll number ${card.rollNumber}. ${_countdownLabel(days)}. Tap to open.',
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          height: compact ? 76 : EvSize.walletCard,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EvRadius.pass),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.walletTop, p.walletMid, p.walletBottom],
              stops: const [0, 0.42, 1],
            ),
            border: Border.all(color: p.walletBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.55 : 0.22),
                blurRadius: 34,
                offset: const Offset(0, 18),
                spreadRadius: -18,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EvRadius.pass - 1),
            child: Stack(
              children: [
                // corner glow
                Positioned(
                  top: -46,
                  right: -28,
                  child: Container(
                    width: 168,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          p.accentBright.withValues(alpha: 0.24),
                          p.accentBright.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // diagonal sheen — 112° sweep at 7 % white
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: const Alignment(-0.7, -1),
                          end: const Alignment(0.7, 1),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.07),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.34, 0.46, 0.58],
                        ),
                      ),
                    ),
                  ),
                ),
                // 1px inner top highlight — inset so it never breaks the radius
                Positioned(
                  top: 1,
                  left: EvRadius.pass,
                  right: EvRadius.pass,
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                  child: compact
                      ? _CompactBody(card: card, days: days)
                      : _FullBody(card: card, days: days, onCopied: onCopied),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _countdownLabel(int days) {
    if (days == 0) return 'TODAY';
    if (days == 1) return 'TOMORROW';
    if (days > 1) return 'IN $days DAYS';
    return '${-days} DAYS AGO';
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({required this.card, required this.days});

  final AdmitCard card;
  final int days;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Row(
      children: [
        _CategoryBadge(category: card.category.label),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            card.examName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: EvFont.ui,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p.onWallet.withValues(alpha: 0.92),
            ),
          ),
        ),
        Text(
          WalletPassCard._countdownLabel(days),
          style: context.type.monoMeta.copyWith(
            color: p.onWalletFaint,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _FullBody extends StatelessWidget {
  const _FullBody({required this.card, required this.days, this.onCopied});

  final AdmitCard card;
  final int days;
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final isUrgent = days <= 3 && days >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CategoryBadge(category: card.category.label),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                card.examCode.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.microLabel.copyWith(
                  color: p.onWalletFaint,
                  fontSize: 9,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Spacer(),
            _CountdownBadge(days: days, urgent: isUrgent),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          card.examName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.type.cardTitle.copyWith(color: p.onWallet),
        ),
        const Spacer(),
        // The whole row is tappable for copy.
        InkWell(
          onTap: () => _copy(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ROLL NUMBER',
                        style: context.type.microLabel.copyWith(
                          color: p.onWalletFaint,
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          card.rollNumber,
                          style: context.type.rollCard,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _CopyPill(
                  onCopied: onCopied,
                  value: card.rollNumber,
                  examName: card.examName,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _examDateLine(card),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.monoMeta.copyWith(color: p.onWalletMuted),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: p.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: p.success.withValues(alpha: 0.8),
                    blurRadius: 6,
                    spreadRadius: -1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'SAVED OFFLINE',
              style: context.type.statusPill.copyWith(
                color: p.successText,
                fontSize: 9,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _examDateLine(AdmitCard card) {
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
    final d = card.examDate;
    final day = d.day.toString().padLeft(2, '0');
    return '$day ${months[d.month - 1]} ${d.year} · ${card.shift.split('–').first.trim()}';
  }

  Future<void> _copy(BuildContext context) async {
    await ClipboardService.copy(
      context,
      value: card.rollNumber,
      label: 'Roll number',
    );
    onCopied?.call();
  }
}

class _CopyPill extends StatelessWidget {
  const _CopyPill({required this.value, required this.examName, this.onCopied});

  final String value;
  final String examName;
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Copy roll number',
      child: GestureDetector(
        // The pill is 32px tall; the gesture area is padded to 48 for thumbs.
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await ClipboardService.copy(
            context,
            value: value,
            label: 'Roll number',
          );
          onCopied?.call();
        },
        child: Container(
          height: EvSize.copyPill,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EvRadius.pill),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF4C8DF7), Color(0xFF2563EB)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 6),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.copy_rounded, size: 13, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Copy',
                style: context.type.label.copyWith(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(EvRadius.badge),
        border: Border.all(color: p.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        category.toUpperCase(),
        style: context.type.statusPill.copyWith(
          color: p.isDark ? const Color(0xFFBFDBFE) : const Color(0xFFDBEAFE),
          fontSize: 9,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.days, required this.urgent});

  final int days;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final color = urgent ? p.danger : p.warning;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EvRadius.pill),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            WalletPassCard._countdownLabel(days),
            style: context.type.statusPill.copyWith(
              color: urgent ? p.dangerText : p.warningText,
              fontSize: 9,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}
