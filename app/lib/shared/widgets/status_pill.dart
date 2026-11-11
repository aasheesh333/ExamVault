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
  }) : _status = null;

  EvStatusPill.status(UpdateStatus status, {super.key, this.compact = false})
    : label = status.label,
      color = status.pillColor,
      _status = status,
      textColor = null,
      dot = true;

  /// Set when this pill was built from an [UpdateStatus]; used to pick an
  /// AA-compliant label colour instead of the raw accent hue.
  final UpdateStatus? _status;

  final String label;
  final Color color;
  final Color? textColor;
  final bool dot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // The label used to be painted in the raw accent hue on a 12 % tint of
    // itself — 2.27:1 for green and 1.96:1 for amber in light mode. The word is
    // the *only* signal for colour-blind users, so it must be readable text, not
    // a decoration: prefer the status's tuned text token, then any explicit
    // override, then darken the accent until it passes on its own tint.
    final base = color.computeLuminance();
    final fg =
        _status?.textOn(context) ??
        textColor ??
        (base > 0.35 ? const Color(0xFF1F2937) : color);

    return Container(
      // A floor, not a ceiling: the fixed 22px box let the label overhang the
      // pill's border at 2.0x text (11px × 1.2 line height × 2 = 26.4px) — the
      // same fixed-height bug every sibling chrome had already shed. No
      // `alignment:` — that would expand the pill to its row's full width; the
      // inner min-sized Row fills the minHeight and centres itself.
      constraints: BoxConstraints(
        minHeight: compact ? 22.0 : EvSize.statusPill,
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 8, vertical: 2),
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
              fontSize: compact ? 11 : 11.5,
            ),
          ),
        ],
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
