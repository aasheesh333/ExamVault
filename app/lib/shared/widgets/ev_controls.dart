import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
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
      duration: EvMotion.fast,
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
      label: label,
      child: AnimatedOpacity(
        duration: EvMotion.fast,
        opacity: active ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(EvRadius.button),
          child: Ink(
            height: EvSize.primaryButton,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EvRadius.button),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF4E90F9),
                  Color(0xFF2F74E8),
                  Color(0xFF2563EB),
                ],
                stops: [0, 0.55, 1],
              ),
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

    return Semantics(
      button: true,
      label: label,
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
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
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
                        color: p.danger,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: p.bg, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount! > 9 ? '9+' : '$badgeCount',
                        style: context.type.statusPill.copyWith(
                          color: Colors.white,
                          fontSize: 8,
                          letterSpacing: 0,
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

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
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
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Intrinsic width. A bare `Container` sizes to its parent, so inside a
        // `Wrap` every chip became full-width and the category picker stacked
        // vertically down the sheet. `mainAxisSize.min` via a Row keeps the chip
        // hugging its label while the outer box keeps the 44px tap target.
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
              duration: EvMotion.fast,
              curve: EvMotion.curve,
              height: EvSize.chip,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? p.accent.withValues(alpha: 0.15)
                    : p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
                borderRadius: BorderRadius.circular(EvRadius.pill),
                border: Border.all(
                  color: selected ? p.accent.withValues(alpha: 0.45) : p.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.type.label.copyWith(
                      fontSize: 11.5,
                      color: selected ? p.accentText : p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
