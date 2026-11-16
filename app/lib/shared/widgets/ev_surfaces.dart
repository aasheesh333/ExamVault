import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_tokens.dart';

/// The standard card surface: 1px border, 18px radius, hairline-only elevation.
///
/// ExamVault never uses a drop shadow on a card inside the scroll view — the
/// navy-on-navy page already separates surfaces, and shadows on a dark theme read
/// as dirt. Only floating chrome (tab bar, dock) gets elevation.
class EvCard extends StatelessWidget {
  const EvCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(EvSpace.x4),
    this.radius = EvRadius.card,
    this.color,
    this.borderColor,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final content = Padding(padding: padding, child: child);

    return Semantics(
      container: true,
      // ALWAYS split into child nodes. When this was `onTap != null`, a
      // non-interactive card with a single button inside collapsed into ONE
      // 361x209 button node — a screen reader read the entire empty-state card as
      // a button and the real "Add admit card" CTA was unreachable.
      explicitChildNodes: true,
      label: semanticLabel,
      button: onTap != null,
      // `explicitChildNodes` also splits the card's own InkWell into a child
      // node, so its tap action never reached this labelled node: TalkBack
      // focused the card ("… Open notice details, button") and the double-tap
      // did nothing while the action sat on an unnamed child. The wrapper
      // carries the action itself.
      onTap: onTap,
      child: Material(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // A labelled, tappable card produced TWO focus stops: this wrapper
          // ("Open notice details", button, tap) and the InkWell's own node
          // ("SSC CGL Tier-1 2026 / Result out", focus, tap). A screen reader
          // read the summary and then the raw content, both activating the same
          // callback. Excluding the InkWell's semantics drops only its own tap
          // node — the child text nodes stay — so the labelled wrapper is the
          // one stop. Unlabelled cards keep the InkWell node (there is no
          // wrapper label to announce instead).
          excludeFromSemantics: onTap != null && semanticLabel != null,
          borderRadius: BorderRadius.circular(radius),
          splashColor: p.accent.withValues(alpha: 0.08),
          highlightColor: p.accent.withValues(alpha: 0.04),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor ?? p.border, width: 1),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Hairline used to separate rows inside a card.
class EvHairline extends StatelessWidget {
  const EvHairline({super.key, this.inset = EvSpace.x4});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Container(height: 1, color: context.hairline),
    );
  }
}

/// Section label + trailing action. The label is deliberately uppercase mono —
/// it reads as a system label, not as content.
class EvSectionHeader extends StatelessWidget {
  const EvSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
  });

  final String label;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // At large text the label and its trailing actions cannot share a line: the
    // title collapsed to "MY ADMIT C…" while "2 saved" and "Add" stayed full size.
    // Past 1.4x they stack instead of fighting.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Wrapping is independent of `stacked`: "WHERE THE DATA COMES FROM" and
    // "WHY WE NEVER HOST THE PDF" have no trailing action, so `stacked` was
    // false and they stayed at one line — ellipsised mid-phrase at 320 @2.0x.
    // Two lines is enough for every label in the app at the 2.0x ceiling.
    final wrapTitle = scale > 1.4;
    final stacked = trailing != null && wrapTitle;

    final title = Semantics(
      // Header text is a label, never a control — and a *heading*: heading
      // navigation ("jump between headings" in TalkBack) was empty app-wide,
      // so screen-reader users had no landmark to skip between sections with.
      // (The widget flag is spelled `header`; it maps to the semantics
      // `heading` trait platforms expose.) The trailing action stays its own
      // node.
      container: true,
      header: true,
      child: Text(
        label.toUpperCase(),
        style: context.type.microLabel,
        maxLines: wrapTitle ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Padding(
      padding: padding,
      child: ConstrainedBox(
        // A fixed 20px box clipped the trailing action: EvTextAction renders
        // ~30px tall, so "3 saved" was sliced in half. Size to the tallest child.
        constraints: const BoxConstraints(minHeight: 32),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (leading != null) ...[
                        leading!,
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: title),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerRight, child: trailing!),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Expanded(child: title),
                  ?trailing,
                ],
              ),
      ),
    );
  }
}

/// Small text action used in section headers ("Manage", "Add exam").
class EvTextAction extends StatelessWidget {
  const EvTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.ev.textSecondary;

    // `container: true` is required. Without it Flutter merges this button into
    // any adjacent text node, so the section header announced itself as a single
    // button reading "MY ADMIT CARDS Add" with a 393px-wide tap target, and the
    // actual "Add" affordance was unreachable for a screen reader.
    return Semantics(
      container: true,
      // `excludeSemantics` collapses the child Text into this single node, so the
      // action is announced once ("Add, button") instead of twice with a
      // duplicated label. It also drops the InkWell's own semantics, so this
      // wrapper must carry the tap action itself: without `onTap` the node was
      // announced as "Add, button" with zero actions and TalkBack's double-tap
      // did nothing.
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(EvRadius.pill),
        // Visual height stays 32 so headers keep their rhythm, but the hit area
        // is 44. The InkWell was the tap surface and it inherited the 32px
        // container, so these text actions were undersized by 12px.
        child: Container(
          constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label first, chevron after. Reading order matters: "3 saved ›"
              // is a destination, "› 3 saved" reads as a back button.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.label.copyWith(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 2),
                Icon(icon, size: 13, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Synchronous single-flight guard for "open a modal sheet" callbacks.
///
/// `showModalBottomSheet` inserts its barrier a frame *after* it is called, so a
/// fast double tap on the trigger stacked a second sheet on the first — the
/// About panel and the exam detail sheet both did, and the alerts bell needed
/// the same guard inline (`command_center_screen.dart`, `_alertsOpen`). The
/// flag is read and set synchronously before the first await, which is the only
/// window a second tap has.
///
/// Own one instance per trigger (a `State` field), never a global: two different
/// buttons may legitimately open two different sheets.
class SheetOpenGuard {
  bool _open = false;

  /// True while the sheet this guard opened is still on screen.
  bool get isOpen => _open;

  /// Runs [open] unless a sheet from this guard is already open.
  ///
  /// Returns `null` when the call was ignored, otherwise the sheet's result.
  Future<T?> run<T>(Future<T?> Function() open) async {
    if (_open) return null;
    _open = true;
    try {
      return await open();
    } finally {
      _open = false;
    }
  }
}

/// A vertically centred block that scrolls when it cannot fit.
///
/// Every empty/error state in the app was `Center(child: Column(...))`, which
/// cannot scroll: on a 320x568 screen at 2.0x text the content is taller than the
/// viewport and the Column overflows off both edges. This centres when there is
/// room and scrolls when there is not, which is the behaviour those states always
/// needed.
class EvCenteredScroll extends StatelessWidget {
  const EvCenteredScroll({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Derived from the *resolved* padding — the hardcoded 64 was only
        // correct for the default all-32 and pushed callers passing
        // vertical: 24 padding 8px off true centre.
        final resolved = padding.resolve(Directionality.of(context));
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            // Fill the viewport minus the padding, so `Center` still centres in
            // the normal case and only starts scrolling once content exceeds it.
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - resolved.vertical).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
