import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme_tokens.dart';

/// 52px primary action. The gradient + inner top highlight is what makes it read
/// as a physical key rather than a flat rectangle.
class EvPrimaryButton extends StatelessWidget {
  const EvPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.trailing,
    this.expand = true,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Widget? trailing;
  final bool expand;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final active = enabled && !busy && onPressed != null;

    final content = AnimatedSwitcher(
      duration: EvMotion.of(context, EvMotion.micro),
      child: busy
          ? SizedBox(
              key: const ValueKey('busy'),
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.button,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              ],
            ),
    );

    return Semantics(
      button: true,
      enabled: active,
      // No `label:` here — the inner Text *is* the accessible name. Setting
      // both made TalkBack read every primary button twice ("Check my result
      // instantly, Check my result instantly, button"): the Semantics label and
      // the un-excluded child Text merge into one node. While busy the content
      // is a spinner with no text, so the name is supplied then.
      label: busy ? label : null,
      child: AnimatedOpacity(
        duration: EvMotion.of(context, EvMotion.micro),
        opacity: active ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(EvRadius.button),
          child: Ink(
            height: EvSize.primaryButton,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EvRadius.button),
              gradient: EvGradient.primary,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: p.accent.withValues(alpha: 0.42),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                        spreadRadius: -12,
                      ),
                    ]
                  : null,
            ),
            child: InkWell(
              onTap: active ? onPressed : null,
              borderRadius: BorderRadius.circular(EvRadius.button),
              child: Stack(
                children: [
                  // 1px inner highlight along the top edge.
                  Positioned(
                    top: 0,
                    left: 12,
                    right: 12,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Center(child: content),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 44px outline action.
class EvSecondaryButton extends StatelessWidget {
  const EvSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? trailing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    // A null onPressed used to render a full-opacity button that TalkBack
    // announced as enabled but that did nothing — the primary button gates and
    // dims; its siblings must behave the same.
    final active = onPressed != null;

    return Semantics(
      button: true,
      enabled: active,
      // The inner Text is the accessible name; a Semantics label on top made
      // TalkBack read every secondary button twice.
      child: AnimatedOpacity(
        duration: EvMotion.of(context, EvMotion.micro),
        opacity: active ? 1 : 0.55,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(EvRadius.button),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(EvRadius.button),
            child: Container(
              height: EvSize.secondaryButton,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(EvRadius.button),
                border: Border.all(color: p.borderStrong),
              ),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: p.textSecondary),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.label.copyWith(
                        color: p.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Square icon button. [ghost] drops the fill for nav bars.
class EvIconButton extends StatelessWidget {
  const EvIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = EvSize.iconButton,
    this.iconSize = 18,
    this.ghost = false,
    this.tooltip,
    this.badgeCount,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool ghost;
  final String? tooltip;
  final int? badgeCount;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: ghost ? Colors.transparent : p.surface,
        borderRadius: BorderRadius.circular(EvRadius.tile),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(EvRadius.tile),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EvRadius.tile),
              border: ghost ? null : Border.all(color: p.border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: iconSize, color: iconColor ?? p.textSecondary),
                if (badgeCount != null && badgeCount! > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 14),
                      height: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        // `dangerStrong`, not `danger`: the 11px white count
                        // only reaches 3.76:1 on #EF4444 — under AA. #DC2626
                        // measures 4.83:1. Dots and borders elsewhere keep the
                        // brighter `danger`; only text-carrying fills use this.
                        color: p.dangerStrong,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: p.bg, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      // The Semantics label on the button already says
                      // "N unread"; letting the visible count merge into the
                      // same node announced "Notifications, 3 unread 3".
                      child: ExcludeSemantics(
                        child: Text(
                          badgeCount! > 9 ? '9+' : '$badgeCount',
                          style: context.type.statusPill.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // An icon-only button with no tooltip was announced as just "button" by
    // TalkBack, so back/close/share were unusable with a screen reader. The tooltip
    // doubles as the accessible name, and a hit area of at least 44px is enforced
    // around whatever visual size was asked for.
    final hit = SizedBox(
      width: math.max(size, EvSize.minTapTarget),
      height: math.max(size, EvSize.minTapTarget),
      child: Center(child: button),
    );

    // The badge is the app's only unread-alerts signal — it must exist for
    // screen readers too, not just visually. And a null onPressed now announces
    // as disabled instead of "enabled but dead".
    final enabled = onPressed != null;
    final badge = (badgeCount ?? 0) > 0
        ? '${badgeCount! > 9 ? '9+' : badgeCount} unread'
        : null;
    final label = [?tooltip, ?badge].join(', ');

    return Semantics(
      button: true,
      enabled: enabled,
      label: label.isEmpty ? null : label,
      child: AnimatedOpacity(
        duration: EvMotion.of(context, EvMotion.micro),
        opacity: enabled ? 1 : 0.55,
        child: tooltip == null
            ? hit
            : Tooltip(
                message: tooltip!,
                // The Semantics label above already carries the tooltip text
                // (plus the unread badge); letting the Tooltip contribute its
                // message as well announced "Notifications, Notifications".
                excludeFromSemantics: true,
                child: hit,
              ),
      ),
    );
  }
}

/// Filter chip. 32px tall, 44px hit area via [EvSize.minTapTarget].
class EvChip extends StatelessWidget {
  const EvChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      button: true,
      selected: selected,
      // No `label:`: the inner Text is the accessible name. Both together made
      // TalkBack announce every chip twice.
      //
      // InkWell, not GestureDetector: every other tappable in the design system
      // gives pressed feedback, and the chip — the control users tap most in
      // the category picker — gave none. The `Material(transparency)` is what
      // the InkWell paints its splash on when the chip sits outside a card's
      // Material (a bare sheet column); transparency keeps the pill's own
      // AnimatedContainer fill as the visible background.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(EvRadius.pill),
          // Intrinsic width. A bare `Container` sizes to its parent, so inside a
          // `Wrap` every chip became full-width and the category picker stacked
          // vertically down the sheet. `mainAxisSize.min` via a Row keeps the chip
          // hugging its label while the outer box keeps the 44px tap target —
          // the InkWell wraps this box (not just the pill) so the whole 44px
          // height stays tappable, which layout_regression_test pins.
          child: SizedBox(
            height: EvSize.minTapTarget,
            // `Center` alone is an `Align`: with bounded constraints and no
            // widthFactor it expands to constraints.maxWidth, so every chip filled
            // the whole row and the Wrap stacked them vertically. widthFactor: 1
            // makes it hug the chip instead.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: EvMotion.of(context, EvMotion.micro),
                curve: EvMotion.enter,
                // Floor, not fixed height: at 2.0x text the 12.5px label's line
                // box (~32.5px) exceeded the hard 32px pill and overhung it.
                // No `alignment:` here — a Container with alignment expands to
                // the largest incoming constraints, which un-hugs the chip (the
                // 328px-wide "SSC" the layout test caught). The Row fills the
                // minHeight and centres its own children.
                constraints: const BoxConstraints(minHeight: EvSize.chip),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
                  borderRadius: BorderRadius.circular(EvRadius.pill),
                  border: Border.all(
                    color: selected
                        ? p.accent.withValues(alpha: 0.45)
                        : p.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: context.type.label.copyWith(
                        color: selected ? p.accentText : p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
