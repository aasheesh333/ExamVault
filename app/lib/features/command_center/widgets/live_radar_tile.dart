import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../data/models/live_feed_dto.dart';
import '../../../domain/entities/live_update.dart';
import '../../../shared/widgets/status_pill.dart';

/// One row of the Live Radar.
///
/// Layout is a 3-column grid inside a 62px row: 34px icon tile, flexible copy,
/// right-aligned status + age. The age is the quietest element on purpose — it is
/// context, not content.
class LiveRadarTile extends StatelessWidget {
  const LiveRadarTile({
    super.key,
    required this.update,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final LiveUpdate update;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    // Themed accent, not the frozen dark-palette hex: `pillColor` resolved
    // against EvPalette.dark at construction, so light theme rendered the
    // dark grey/amber icon tints. The pill widget itself was fixed in
    // status_pill.dart; this was its last caller.
    final accent = update.status.accentOn(context);

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
          child: Row(
            children: [
              _IconTile(status: update.status, accent: accent),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
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
                            style: context.type.bodyMuted.copyWith(
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        if (update.mirrorLatencyMs != null) ...[
                          const SizedBox(width: 6),
                          _LatencyChip(ms: update.mirrorLatencyMs!),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Flexible: at 320px and 2.0x text the "ADMIT CARD LIVE" pill's
              // intrinsic width exceeded the row's free space and pushed the
              // whole row into RenderFlex overflow. As a flex child it gets
              // bounded and the pill's label ellipsises instead.
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // scaleDown, right-aligned: the pill's own Row lays its
                    // label out unbounded, so its ellipsis never engages and
                    // "ADMIT CARD LIVE" overflowed by 80px the first time rows
                    // rendered on a 360px device. Scaling keeps the label whole
                    // and inside the row until the shared pill gains a
                    // Flexible-wrapped label (the root fix, tracked upstream).
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: EvStatusPill.status(update.status, compact: true),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      update.ageLabel(),
                      style: context.type.monoMeta.copyWith(
                        fontSize: 11,
                        color: p.textTertiary,
                      ),
                    ),
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
