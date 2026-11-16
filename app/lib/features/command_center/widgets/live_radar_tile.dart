import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../data/models/live_feed_dto.dart';
import '../../../domain/entities/live_update.dart';
import '../../../shared/widgets/status_pill.dart';

/// One row of the Live Radar.
///
/// Layout: a 36px icon tile, the copy block (headline, then
/// `context · latency · bell`), and a status line under both — the pill at its
/// token size with the age at the far right of that line when it fits. The age is
/// the quietest element on purpose — it is context, not content.
///
/// The pill used to share the row with a ~100px right-hand column that could not
/// hold its 134px intrinsic width even at the **default** 1.0x text size (233px
/// at 2.0x), so a `FittedBox(scaleDown)` painted the 11px label at 8.25px — under
/// this app's own 11px floor (`theme_tokens.dart:11`) on the 320dp phones this
/// design targets, not only for readers who raised their text scale. The column
/// was the cause, the scale was the symptom. The pill now owns a full-width line
/// (256px at 320dp) at every scale, so it paints at 11px x the reader's scale with
/// no `FittedBox` and no per-scale branch: one arrangement from 1.0x through 2.0x.
class LiveRadarTile extends StatelessWidget {
  const LiveRadarTile({
    super.key,
    required this.update,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
    this.alerting = false,
    this.onAlertToggle,
  });

  final LiveUpdate update;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  /// Whether the bell for THIS exam is on.
  final bool alerting;

  /// Null hides the bell (e.g. no push provider configured): offering a switch
  /// that cannot deliver anything would be a lie.
  final VoidCallback? onAlertToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    // Themed accent, not the frozen dark-palette hex: `pillColor` resolved
    // against EvPalette.dark at construction, so light theme rendered the
    // dark grey/amber icon tints. The pill widget itself was fixed in
    // status_pill.dart; this was its last caller.
    final accent = update.status.accentOn(context);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Two lines, not one: headlines come from the commission
          // pre-truncated at ~95 chars, and a single line showed ~35 —
          // dropping the stage ("Paper-II", "PET/PST") that makes the
          // row mean anything.
          update.examName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.type.tileTitle,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                update.contextLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodyMuted.copyWith(fontSize: 11.5),
              ),
            ),
            if (update.mirrorLatencyMs != null) ...[
              const SizedBox(width: 6),
              _LatencyChip(ms: update.mirrorLatencyMs!),
            ],
            if (onAlertToggle != null) ...[
              const SizedBox(width: 4),
              _AlertBell(
                examName: update.examName,
                on: alerting,
                onTap: onAlertToggle!,
              ),
            ],
          ],
        ),
      ],
    );

    // Shared by both the copy block and the status line: the age is the quietest
    // element on purpose — it is context, not content.
    final age = Text(
      update.ageLabel(),
      style: context.type.monoMeta.copyWith(
        fontSize: 11,
        color: p.textTertiary,
      ),
    );

    return Semantics(
      button: true,
      // No explicit `label`: the tile's own texts (headline, status pill,
      // context, age) merge into this button node, so a composed label made
      // TalkBack read every row twice — once as prose, once as raw text.
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(
            // 16, not 14: the radar's empty-state card uses EvCard's 16px
            // padding, so the section's left edge shifted 2px between states.
            horizontal: EvSpace.x4,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: isFirst
                  ? BorderSide.none
                  : BorderSide(color: context.hairline),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                // Top-aligned: the icon is a fixed 36px square and the copy
                // column grows with the type scale.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconTile(status: update.status, accent: accent),
                  const SizedBox(width: 11),
                  // Full remaining width: no status column competes with the
                  // headline or the meta line any more.
                  Expanded(child: copy),
                ],
              ),
              const SizedBox(height: 8),
              // No `FittedBox` anywhere above the pill: it owns this line's full
              // content width (256px at 320dp), so its 11px label paints at 11px
              // x the reader's scale instead of being shrunk into a column.
              //
              // Wrap, not Row: at 2.0x the pill alone measures 233px and the age
              // ~80px, so the age drops to its own run rather than squeezing the
              // pill's label into an ellipsis. The full-width box is what makes
              // `spaceBetween` put the age on the line's right edge — the quiet,
              // column-aligned position it has always had — instead of letting it
              // trail the pill at a different x on every row.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    EvStatusPill.status(update.status, compact: true),
                    age,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.status, required this.accent});

  final UpdateStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(EvRadius.tile),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Icon(status.icon, size: 17, color: accent),
    );
  }
}

/// Tiny green "82ms" chip proving the mirror is fast — the single most useful
/// data point on result day.
class _LatencyChip extends StatelessWidget {
  const _LatencyChip({required this.ms});

  final int ms;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final fast = ms < 500;
    final color = fast ? p.success : p.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        // Never below 8px anywhere in the app — this label sits on the busiest
        // row and is the number that tells a user the mirror is actually fast.
        '${ms}ms',
        style: context.type.statusPill.copyWith(
          color: fast ? p.successText : p.warningText,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Per-exam notification bell.
///
/// Sits in the row's meta line rather than as a fourth column: the row already
/// carries a 36px icon tile, two lines of copy and the status line, and a fourth
/// column would either shrink the headline or overflow at 320px @2.0x. The 44px
/// hit area is kept even though the glyph is 16px — this is a thumb-target on exam
/// morning, not a decoration.
class _AlertBell extends StatelessWidget {
  const _AlertBell({
    required this.examName,
    required this.on,
    required this.onTap,
  });

  final String examName;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      container: true,
      button: true,
      toggled: on,
      label: on
          ? 'Notifications on for $examName. Turn off.'
          : 'Notify me about $examName.',
      // `excludeSemantics` drops the InkResponse's own tap action along with its
      // semantics, so the wrapper carries the action itself. Without it the bell
      // was a button with zero actions: TalkBack focused it, double-tap did
      // nothing.
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: on ? 'Alerts on' : 'Alert me',
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                on
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 16,
                color: on ? p.accentText : p.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
