import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../domain/entities/live_update.dart';

/// The single status pill used across the app.
///
/// Contract: colour is *always* accompanied by the label, so the three statuses
/// remain distinguishable for the ~8 % of Indian male users with red-green
/// deficiency. The dot is decoration; the word is the signal.
class EvStatusPill extends StatelessWidget {
  const EvStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.textColor,
    this.dot = true,
    this.compact = false,
  });

  EvStatusPill.status(UpdateStatus status, {super.key, this.compact = false})
      : label = status.label,
        color = status.pillColor,
        textColor = null,
        dot = true;

  final String label;
  final Color color;
  final Color? textColor;
  final bool dot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? color;
    final height = compact ? 19.0 : EvSize.statusPill;

    return Semantics(
      label: label,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(EvRadius.badge),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.7),
                      blurRadius: 6,
                      spreadRadius: -1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              maxLines: 1,
              style: context.type.statusPill.copyWith(
                color: fg,
                fontSize: compact ? 8 : 8.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension UpdateStatusColors on UpdateStatus {
  Color get pillColor => accentOf(this);

  static Color accentOf(UpdateStatus status) => switch (status) {
        UpdateStatus.resultOut => const Color(0xFF10B981),
        UpdateStatus.admitCardLive => const Color(0xFFF59E0B),
        UpdateStatus.formClosing => const Color(0xFFEF4444),
        UpdateStatus.answerKey => const Color(0xFF3B82F6),
        UpdateStatus.awaited => const Color(0xFF8695AB),
      };
}

extension UpdateStatusText on UpdateStatus {
  /// Text colour tuned per theme so the pill label passes AA on its 12 % tint.
  Color textOn(BuildContext context) {
    final p = context.ev;
    return switch (this) {
      UpdateStatus.resultOut => p.successText,
      UpdateStatus.admitCardLive => p.warningText,
      UpdateStatus.formClosing => p.dangerText,
      UpdateStatus.answerKey => p.accentText,
      UpdateStatus.awaited => p.textTertiary,
    };
  }

  IconData get icon => switch (this) {
        UpdateStatus.resultOut => Icons.picture_as_pdf_rounded,
        UpdateStatus.admitCardLive => Icons.access_time_rounded,
        UpdateStatus.formClosing => Icons.timer_outlined,
        UpdateStatus.answerKey => Icons.key_rounded,
        UpdateStatus.awaited => Icons.hourglass_empty_rounded,
      };
}
