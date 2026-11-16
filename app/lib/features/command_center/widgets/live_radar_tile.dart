import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../data/models/live_feed_dto.dart';
import '../../../domain/entities/live_update.dart';
import '../../../shared/widgets/status_pill.dart';

/// One row of the Live Radar.
///
/// Layout: a 36px icon tile, the copy block (headline, then
/// `context · latency · bell`), and a status line under both — the pill at its
/// token size on the left, the age flush right on the same line when it fits and
/// on its own line (still flush right) when it does not. The age is the quietest
/// element on purpose — it is context, not content, so it always sits against the
/// row's right edge rather than trailing the pill.
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
              // Two columns that degrade, not a `Wrap`: the age must sit on the
              // line's right edge whether it shares the line with the pill or
              // drops to its own run beneath it. `Wrap(alignment: spaceBetween)`
              // applies one alignment to *every* run, and `spaceBetween` with a
              // lone child falls back to `start` (wrap.dart:111) — measured at
              // 320dp the age then landed at x=32, directly under the pill's left
              // edge, with 173.5px of dead space to its right at 2.0x and 181.4px
              // at 1.8x. That is the opposite of the quiet, column-aligned
              // timestamp this row has always had.
              _StatusLine(
                spacing: EvSpace.x2,
                // On the 8pt grid: the 2px this used to carry was off-grid, and
                // the gap only shows when the age drops to its own run.
                runSpacing: EvSpace.x1,
                children: [
                  EvStatusPill.status(update.status, compact: true),
                  age,
                ],
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

/// A line with a leading and a trailing child: [children] first against the left
/// edge, last against the right edge, on one line when both fit and on two when
/// they do not — the trailing child still flush right on its own run.
///
/// `Wrap` cannot express this. It applies one alignment to every run, and
/// `spaceBetween` with a lone child falls back to `start` (wrap.dart:111), so the
/// moment the age wrapped it left the right edge it belongs to. `OverflowBar`
/// cannot either: it lays every child out with `constraints.loosen()` in both its
/// row and column modes, so it can only align the whole column one way.
///
/// The pill must never be the child that gives ground: its label is the only
/// non-colour signal, so this measures both children at their natural size and
/// moves the trailing one down instead of squeezing either.
class _StatusLine extends MultiChildRenderObjectWidget {
  const _StatusLine({
    required this.spacing,
    required this.runSpacing,
    required super.children,
  }) : assert(
         children.length == 2,
         '_StatusLine lays out exactly two children (leading, trailing): the '
         'render object reads firstChild and childAfter(firstChild) and nothing '
         'else, so a third child would never be laid out and would fail inside '
         'paint with an unpositioned-box error instead of here.',
       );

  /// Gap between the two children while they share a line.
  final double spacing;

  /// Gap between the lines once the trailing child drops to its own.
  final double runSpacing;

  @override
  _RenderStatusLine createRenderObject(BuildContext context) =>
      _RenderStatusLine(spacing: spacing, runSpacing: runSpacing);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStatusLine renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class _StatusLineParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderStatusLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StatusLineParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StatusLineParentData> {
  _RenderStatusLine({required double spacing, required double runSpacing})
    : _spacing = spacing,
      _runSpacing = runSpacing;

  double get spacing => _spacing;
  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double get runSpacing => _runSpacing;
  double _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StatusLineParentData) {
      child.parentData = _StatusLineParentData();
    }
  }

  @override
  void performLayout() {
    final leading = firstChild;
    final trailing = leading == null ? null : childAfter(leading);
    if (leading == null || trailing == null) {
      size = constraints.smallest;
      return;
    }

    // A bounded width is the only sane case for a line; fall back to the
    // children's own extent rather than an infinite one if a future caller ever
    // drops this into an unbounded row.
    final lineWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : double.infinity;
    final childConstraints = BoxConstraints(maxWidth: lineWidth);
    leading.layout(childConstraints, parentUsesSize: true);
    trailing.layout(childConstraints, parentUsesSize: true);

    final resolved = _resolve(
      constraints.hasBoundedWidth
          ? lineWidth
          : leading.size.width + spacing + trailing.size.width,
      leading.size,
      trailing.size,
    );
    (leading.parentData! as _StatusLineParentData).offset = resolved.leading;
    (trailing.parentData! as _StatusLineParentData).offset = resolved.trailing;
    size = constraints.constrain(Size(resolved.width, resolved.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final leading = firstChild;
    final trailing = leading == null ? null : childAfter(leading);
    if (leading == null || trailing == null) return constraints.smallest;

    final lineWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : double.infinity;
    final childConstraints = BoxConstraints(maxWidth: lineWidth);
    final leadingSize = leading.getDryLayout(childConstraints);
    final trailingSize = trailing.getDryLayout(childConstraints);
    final resolved = _resolve(
      constraints.hasBoundedWidth
          ? lineWidth
          : leadingSize.width + spacing + trailingSize.width,
      leadingSize,
      trailingSize,
    );
    return constraints.constrain(Size(resolved.width, resolved.height));
  }

  /// The line's height and both children's offsets at [width].
  ({double width, double height, Offset leading, Offset trailing}) _resolve(
    double width,
    Size leading,
    Size trailing,
  ) {
    // Clamped: a trailing child wider than the line cannot be flush right
    // without painting off the left edge. Unreachable today (the age is 82.5px
    // against a 256px line at 2.0x), but a silent negative offset would clip
    // rather than fail loudly.
    final trailingX = width - trailing.width < 0 ? 0.0 : width - trailing.width;
    if (leading.width + spacing + trailing.width <= width) {
      // Both fit: same line, each child centred vertically in it.
      final height = leading.height > trailing.height
          ? leading.height
          : trailing.height;
      return (
        width: width,
        height: height,
        leading: Offset(0, (height - leading.height) / 2),
        trailing: Offset(trailingX, (height - trailing.height) / 2),
      );
    }
    // The trailing child drops to its own run, still against the right edge.
    return (
      width: width,
      height: leading.height + runSpacing + trailing.height,
      leading: Offset.zero,
      trailing: Offset(trailingX, leading.height + runSpacing),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
