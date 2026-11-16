import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../data/models/live_feed_dto.dart';
import '../../../domain/entities/live_update.dart';
import '../../../shared/widgets/status_pill.dart';

/// One row of the Live Radar.
///
/// Layout is a 3-column grid inside a 62px row: 36px icon tile, flexible copy,
/// right-aligned status + age. The age is the quietest element on purpose — it is
/// context, not content.
///
/// Above 1.4x text the third column cannot hold the pill at its token size, so
/// the pill and the age move to their own line under the copy block (see
/// `stacked` below). At and below 1.4x the grid above is unchanged.
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

    // Above ~1.4x the right-hand column cannot hold the pill. Measured at a
    // 320dp viewport with 2.0x text: the pill's intrinsic width is 233px, the
    // column it is given is ~100px, and the `FittedBox` below scaled the 11px
    // label to ~9.5px — under this app's own 11px floor (theme_tokens.dart:11)
    // and *smaller* than at 1.0x, on the exact setting the reader raised because
    // they could not read it. The scale was the symptom; the column was the
    // cause. Past 1.4x the pill and the age move onto their own line under the
    // headline, where they get the row's full content width (256px at 320dp),
    // and the `FittedBox` is dropped so the label paints at its token size. At
    // and below 1.4x the single-line row is untouched.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.4;

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

    // Shared by both branches: the age is the quietest element on purpose — it
    // is context, not content.
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
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      // Top-aligned: the icon is a fixed 36px square and the
                      // copy column grows with the type scale.
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconTile(status: update.status, accent: accent),
                        const SizedBox(width: 11),
                        Expanded(child: copy),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // No `FittedBox` on this path: the pill owns the row's full
                    // content width, so its 11px label paints at 11px x the
                    // reader's scale instead of being shrunk to fit a column.
                    // Wrap, not Row: at 2.0x the pill alone measures 233px, so
                    // the age drops to its own run instead of squeezing the
                    // pill's label into an ellipsis.
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        EvStatusPill.status(update.status, compact: true),
                        age,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    _IconTile(status: update.status, accent: accent),
                    const SizedBox(width: 11),
                    Expanded(child: copy),
                    const SizedBox(width: 8),
                    // Flexible: at 320px and 2.0x text the "ADMIT CARD LIVE"
                    // pill's intrinsic width exceeded the row's free space and
                    // pushed the whole row into RenderFlex overflow. As a flex
                    // child it gets bounded and the pill's label ellipsises
                    // instead.
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // scaleDown, right-aligned: the pill's own Row lays
                          // its label out unbounded, so its ellipsis never
                          // engages and "ADMIT CARD LIVE" overflowed by 80px the
                          // first time rows rendered on a 360px device. This
                          // branch is the ≤1.4x path only; past 1.4x the row
                          // stacks (see `stacked`) instead of scaling the label
                          // below its token size.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: EvStatusPill.status(
                              update.status,
                              compact: true,
                            ),
                          ),
                          const SizedBox(height: 5),
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
/// carries a 34px icon tile, two lines of copy and a status/age column, and a
/// fourth column would either shrink the headline or overflow at 320px @2.0x.
/// The 44px hit area is kept even though the glyph is 16px — this is a
/// thumb-target on exam morning, not a decoration.
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
