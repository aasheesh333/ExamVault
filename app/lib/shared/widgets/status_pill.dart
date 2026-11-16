import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';
import '../../domain/entities/live_update.dart';

/// The single status pill used across the app.
///
/// Contract: colour is *always* accompanied by the label, so the three statuses
/// remain distinguishable for the ~8 % of Indian male users with red-green
/// deficiency. The dot is decoration; the word is the signal.
///
/// [EvStatusPill.status] is the only constructor: the label, the accent and the
/// AA-compliant label colour are all derived from one [UpdateStatus], so a
/// caller cannot pair the word "LIVE" with another status's colour.
class EvStatusPill extends StatelessWidget {
  /// Defers the accent to build time: the old constructor took a `color` and
  /// froze a hardcoded hex at construction, which made the pill theme-blind
  /// (the light theme rendered the DARK palette's grey for AWAITED). [build]
  /// resolves the accent from `context.ev` instead.
  const EvStatusPill.status(this.status, {super.key, this.compact = false});

  /// The status being announced; also the source of the visible label.
  final UpdateStatus status;

  String get label => status.label;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    // The label used to be painted in the raw accent hue on a 12 % tint of
    // itself — 2.27:1 for green and 1.96:1 for amber in light mode. The word is
    // the *only* signal for colour-blind users, so it must be readable text, not
    // a decoration: paint it in the status's tuned text token over the accent.
    final accent = status.accentOn(context);
    final fg = status.textOn(context);

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
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(EvRadius.badge),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.7),
                  blurRadius: 6,
                  spreadRadius: -1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              // Ellipsis, not the default soft-wrap: in a tight row (radar tile at
              // 320px, 2.0x) "ADMIT CARD LIVE" would otherwise wrap to a second
              // line inside a one-line pill.
              overflow: TextOverflow.ellipsis,
              style: context.type.statusPill.copyWith(
                color: fg,
                fontSize: compact ? 11 : 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension UpdateStatusColors on UpdateStatus {
  /// The status accent resolved against the *active* palette. This is the only
  /// theme-correct accessor: the old static table hardcoded one palette's
  /// hexes, so light mode rendered the dark palette's grey (#8695AB instead of
  /// #5B6B80) for AWAITED.
  Color accentOn(BuildContext context) => accentIn(context.ev);

  /// The same mapping against an explicit palette — the single definition both
  /// accessors share, so the table cannot drift from the tokens again.
  Color accentIn(EvPalette p) => switch (this) {
    UpdateStatus.resultOut => p.success,
    UpdateStatus.admitCardLive => p.warning,
    UpdateStatus.formClosing => p.danger,
    // A new vacancy is good news, not a warning: accent blue, not red.
    UpdateStatus.notification => p.accent,
    UpdateStatus.answerKey => p.accent,
    UpdateStatus.awaited => p.textTertiary,
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
      UpdateStatus.notification => p.accentText,
      UpdateStatus.answerKey => p.accentText,
      UpdateStatus.awaited => p.textTertiary,
    };
  }

  IconData get icon => switch (this) {
    UpdateStatus.resultOut => Icons.picture_as_pdf_rounded,
    UpdateStatus.admitCardLive => Icons.access_time_rounded,
    UpdateStatus.formClosing => Icons.timer_outlined,
    UpdateStatus.notification => Icons.work_outline_rounded,
    UpdateStatus.answerKey => Icons.key_rounded,
    UpdateStatus.awaited => Icons.hourglass_empty_rounded,
  };
}
