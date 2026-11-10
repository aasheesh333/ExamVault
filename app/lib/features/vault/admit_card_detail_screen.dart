import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/utils/clipboard_service.dart';
import '../../domain/entities/admit_card.dart';
import '../../features/shell/root_shell.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/ev_controls.dart';
import '../../shared/widgets/ev_surfaces.dart';
import 'vault_form_sheet.dart';

/// Status colours tuned for the navy pass: the theme's `*Text` tokens invert in
/// light mode and drop to ~2:1 on navy, so the pass never uses them.
abstract final class _OnPass {
  static const accent = Color(0xFFBFDBFE);
  static const success = Color(0xFF6EE7B7);
}

/// Screen 2 — Boarding-pass roll number vault.
///
/// This is the screen a user opens at 7:40 AM outside an exam centre, one-handed,
/// possibly on 2 % battery. Every field is a full-width tap target that copies and
/// confirms; nothing needs a long-press, a menu, or a second tap.
class AdmitCardDetailScreen extends ConsumerWidget {
  const AdmitCardDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(admitCardsProvider);
    final cards = cardsAsync.value ?? const <AdmitCard>[];
    final selectedId = ref.watch(selectedCardIdProvider);

    if (cards.isEmpty) {
      return Scaffold(
        backgroundColor: context.ev.bg,
        body: SafeArea(
          child: _EmptyState(onAdd: () => showVaultFormSheet(context, ref)),
        ),
      );
    }

    final initialIndex = () {
      if (selectedId == null) return 0;
      final at = cards.indexWhere((c) => c.id == selectedId);
      return at < 0 ? 0 : at;
    }();

    return Scaffold(
      backgroundColor: context.ev.bg,
      // The dock floats over the scroll view; the extra bottom padding keeps the
      // last card clear of it.
      body: SafeArea(
        bottom: false,
        child: _PassPager(cards: cards, initialIndex: initialIndex),
      ),
    );
  }
}

class _PassPager extends ConsumerStatefulWidget {
  const _PassPager({required this.cards, required this.initialIndex});

  final List<AdmitCard> cards;
  final int initialIndex;

  @override
  ConsumerState<_PassPager> createState() => _PassPagerState();
}

class _PassPagerState extends ConsumerState<_PassPager> {
  /// Created once and disposed with the widget. Building it in `build()` made a
  /// new controller on every selection change — mid-gesture — and leaked it.
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  /// The page actually on screen. The dock must act on this card, never on the
  /// stale `initialIndex` the parent computed before a swipe or a delete.
  late int _index = widget.initialIndex;

  @override
  void didUpdateWidget(covariant _PassPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Deleting the visible card shrinks the list underneath the pager.
    if (_index >= widget.cards.length) {
      _index = widget.cards.isEmpty ? 0 : widget.cards.length - 1;
      _jumpAfterLayout();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _indexOfSelected(String? id) {
    if (id == null || widget.cards.isEmpty) return 0;
    final at = widget.cards.indexWhere((c) => c.id == id);
    return at < 0 ? 0 : at;
  }

  /// Jump to the page the provider now points at (delete, dock, checker).
  void _jumpAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(_index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Follow selection changes that did not come from this PageView's gesture.
    ref.listen<String?>(selectedCardIdProvider, (_, next) {
      final target = _indexOfSelected(next);
      if (target != _index) {
        setState(() => _index = target);
        _jumpAfterLayout();
      }
    });

    final p = context.ev;
    final current = widget.cards[_index.clamp(0, widget.cards.length - 1)];

    return Stack(
      children: [
        Column(
          children: [
            _DetailNavBar(
              count: widget.cards.length,
              controller: _controller,
              card: current,
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.cards.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  ref
                      .read(selectedCardIdProvider.notifier)
                      .select(widget.cards[i].id);
                },
                itemBuilder: (context, i) => _PassPage(card: widget.cards[i]),
              ),
            ),
          ],
        ),
        // Fade behind the dock so content never collides with a floating button.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 130,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.bg.withValues(alpha: 0), p.bg],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: EvSpace.gutter,
          right: EvSpace.gutter,
          bottom: MediaQuery.paddingOf(context).bottom + 14,
          child: _ActionDock(card: current),
        ),
      ],
    );
  }
}

class _DetailNavBar extends ConsumerWidget {
  const _DetailNavBar({
    required this.count,
    required this.controller,
    required this.card,
  });

  final int count;
  final PageController controller;
  final AdmitCard? card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    return SizedBox(
      height: EvSize.navBar,
      child: Stack(
        alignment: Alignment.center,
        // The kebab's 44px hit box is 4px taller than the 40px bar.
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              const SizedBox(width: EvSpace.x2),
              EvIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                ghost: true,
                iconSize: 17,
                // This screen is a tab, not a pushed route — `maybePop()` was a
                // no-op, so the chevron did nothing. Go to Home instead.
                onPressed: () =>
                    ref.read(tabIndexProvider.notifier).select(EvTab.home),
              ),
              const Spacer(),
              if (card != null)
                _CardMenu(card: card!)
              else
                const SizedBox(width: EvSpace.x2),
              const SizedBox(width: EvSpace.x2),
            ],
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Saved Pass', style: context.type.navTitle),
              const SizedBox(height: 5),
              // Dots communicate "there are 3 passes, swipe" far better than a
              // bordered "1 / 3" chip, which reads as a tappable counter.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        final page =
                            controller.hasClients &&
                                controller.position.haveDimensions
                            ? controller.page ?? 0
                            : 0;
                        final active = (page - i).abs() < 0.5;
                        return Container(
                          width: active ? 6 : 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: active ? p.accent : p.borderStrong,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassPage extends ConsumerWidget {
  const _PassPage({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        EvSpace.gutter,
        8,
        EvSpace.gutter,
        150,
      ),
      children: [
        _BoardingPass(card: card),
        const SizedBox(height: EvSpace.x3),
        _CountdownCard(card: card),
        const SizedBox(height: EvSpace.x3),
        _DocumentChecklist(card: card),
        const SizedBox(height: EvSpace.x3),
        if (card.centerAddress.isNotEmpty) _CenterCard(card: card),
      ],
    );
  }
}

/// The pass itself. Deliberately navy in both themes — see `theme_tokens.dart`.
class _BoardingPass extends ConsumerWidget {
  const _BoardingPass({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EvRadius.pass),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.walletTop, p.walletMid, p.walletBottom],
          stops: const [0, 0.46, 1],
        ),
        border: Border.all(color: p.walletBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.5 : 0.2),
            blurRadius: 30,
            offset: const Offset(0, 16),
            spreadRadius: -16,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(EvRadius.pass - 1),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 240,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      p.accentBright.withValues(alpha: 0.18),
                      p.accentBright.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 1,
              left: EvRadius.pass,
              right: EvRadius.pass,
              child: Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.examCode.isEmpty
                                  ? card.category.label.toUpperCase()
                                  : '${card.category.label} · ${card.examCode}'
                                        .toUpperCase(),
                              style: context.type.statusPill.copyWith(
                                color: _OnPass.accent,
                                fontSize: 11,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              card.conductingBody,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: EvFont.ui,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: p.onWalletMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: p.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(EvRadius.badge),
                          border: Border.all(
                            color: p.success.withValues(alpha: 0.34),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: p.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              card.rollNumberVerified ? 'VERIFIED' : 'SAVED',
                              style: context.type.statusPill.copyWith(
                                color: _OnPass.success,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ROLL NUMBER',
                    style: context.type.microLabel.copyWith(
                      color: p.onWalletFaint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            card.rollNumber,
                            style: context.type.rollHero,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SquareCopy(value: card.rollNumber, label: 'Roll number'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Perforation(pageColor: p.bg),
                  const SizedBox(height: 14),
                  _FieldGrid(card: card),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(child: _Barcode(height: 24)),
                      const SizedBox(width: 12),
                      Text(
                        'SAVED ON DEVICE',
                        style: context.type.statusPill.copyWith(
                          color: p.onWalletFaint,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context) {
    final fields = <({String label, String value, String copyLabel})>[
      (
        label: 'REGISTRATION ID',
        value: card.registrationId,
        copyLabel: 'Registration ID',
      ),
      (
        label: 'DOB / PORTAL PASSWORD',
        value: card.dobOrPortalPassword,
        copyLabel: 'Password',
      ),
      (
        label: 'EXAM CENTRE CODE',
        value: card.centerCode,
        copyLabel: 'Centre code',
      ),
      (
        label: 'EXAM DATE',
        value: _formatDate(card.examDate),
        copyLabel: 'Exam date',
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++)
          Padding(
            padding: EdgeInsets.only(bottom: row == 0 ? 14 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _CopyField(field: fields[row * 2])),
                const SizedBox(width: 14),
                Expanded(child: _CopyField(field: fields[row * 2 + 1])),
              ],
            ),
          ),
      ],
    );
  }

  static String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _CopyField extends StatelessWidget {
  const _CopyField({required this.field});

  final ({String label, String value, String copyLabel}) field;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final hasValue = field.value.trim().isNotEmpty;

    return Semantics(
      button: hasValue,
      label: '${field.label}: ${field.value}. Tap to copy.',
      child: InkWell(
        onTap: hasValue
            ? () => ClipboardService.copy(
                context,
                value: field.value,
                label: field.copyLabel,
              )
            : null,
        borderRadius: BorderRadius.circular(6),
        // A two-line field is ~37px; the floor keeps the whole row tappable.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  field.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.microLabel.copyWith(
                    color: p.onWalletFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hasValue ? field.value : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: EvFont.mono,
                          fontFamilyFallback: EvFont.fallbackMono,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                          color: hasValue ? p.onWallet : p.onWalletFaint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (hasValue) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.copy_rounded,
                        size: 12,
                        color: p.onWalletFaint,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareCopy extends StatelessWidget {
  const _SquareCopy({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      button: true,
      label: 'Copy $label',
      child: InkWell(
        onTap: () => ClipboardService.copy(context, value: value, label: label),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.accent.withValues(alpha: 0.34)),
          ),
          child: Icon(Icons.copy_rounded, size: 17, color: _OnPass.accent),
        ),
      ),
    );
  }
}

/// Dashed tear line with two punched notches.
class _Perforation extends StatelessWidget {
  const _Perforation({required this.pageColor});

  final Color pageColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _DashPainter())),
          Positioned(left: -26, child: _Notch(color: pageColor)),
          Positioned(right: -26, child: _Notch(color: pageColor)),
        ],
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Barcode extends StatelessWidget {
  const _Barcode({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _BarcodePainter()),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDDE3EC).withValues(alpha: 0.5);
    // Deterministic pattern derived from width so it looks like a real CODE128.
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final w = (i % 3 == 0) ? 2.0 : 1.0;
      if (i % 4 != 3) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      }
      x += w + 1.5;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Countdown + checklist + centre
// ---------------------------------------------------------------------------

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final days = card.daysUntilExam();
    final urgent = days <= 3 && days >= 0;

    return EvCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EXAM COUNTDOWN', style: context.type.microLabel),
                const SizedBox(height: 5),
                Text(
                  days < 0
                      ? 'Exam completed'
                      : card.reportBy.isEmpty
                      ? 'Report on time'
                      : 'Report by ${card.reportBy}',
                  style: context.type.bodyMuted.copyWith(),
                ),
              ],
            ),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (urgent ? p.danger : p.accent).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(EvRadius.tile),
              border: Border.all(
                color: (urgent ? p.danger : p.accent).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              days < 0
                  ? 'PAST'
                  : days == 0
                  ? 'TODAY'
                  : 'IN $days DAYS',
              style: context.type.statusPill.copyWith(
                color: urgent ? p.dangerText : p.accentText,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentChecklist extends ConsumerWidget {
  const _DocumentChecklist({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final done = card.checklist.length;

    return EvCard(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DOCUMENT CHECKLIST',
                  style: context.type.microLabel,
                ),
              ),
              Text(
                '$done / ${ChecklistItem.values.length} READY',
                style: context.type.statusPill.copyWith(
                  color: done == ChecklistItem.values.length
                      ? p.successText
                      : p.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final item in ChecklistItem.values)
            _CheckRow(
              item: item,
              checked: card.checklist.contains(item),
              onToggle: () => ref
                  .read(admitCardsProvider.notifier)
                  .toggleChecklist(card.id, item),
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.item,
    required this.checked,
    required this.onToggle,
  });

  final ChecklistItem item;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      checked: checked,
      label: item.title,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          // Two-line rows already clear this; the floor covers single-line ones.
          constraints: const BoxConstraints(minHeight: EvSize.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: EvMotion.of(context, EvMotion.micro),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: checked
                        ? p.success.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: checked
                          ? p.success.withValues(alpha: 0.5)
                          : p.borderStrong,
                      width: 1.2,
                    ),
                  ),
                  child: checked
                      ? Icon(Icons.check_rounded, size: 14, color: p.success)
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: context.type.tileTitle.copyWith(
                          decoration: checked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: p.textTertiary,
                          color: checked ? p.textSecondary : p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.subtitle,
                        style: context.type.bodyMuted.copyWith(),
                      ),
                    ],
                  ),
                ),
                Text(
                  checked ? 'DONE' : 'TAP',
                  style: context.type.statusPill.copyWith(
                    color: checked ? p.successText : p.textTertiary,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    final query = Uri.encodeComponent(
      '${card.centerAddress} ${card.centerCode}'.trim(),
    );

    return EvCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      onTap: () async {
        final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$query',
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      semanticLabel: 'Exam centre ${card.centerAddress}. Open in maps.',
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.accent.withValues(alpha: 0.26)),
            ),
            child: Icon(Icons.place_outlined, size: 17, color: p.accentText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXAM CENTRE · ${card.centerCode}'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.microLabel.copyWith(),
                ),
                const SizedBox(height: 2),
                Text(
                  card.centerAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.tileTitle.copyWith(),
                ),
                if (card.gate.isNotEmpty || card.reportBy.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (card.gate.isNotEmpty) card.gate,
                      if (card.reportBy.isNotEmpty)
                        'report by ${card.reportBy}',
                    ].join(' · '),
                    style: context.type.bodyMuted.copyWith(),
                  ),
                ],
              ],
            ),
          ),
          Text(
            'MAP',
            style: context.type.statusPill.copyWith(
              color: p.accentText,
              fontSize: 11,
              letterSpacing: 0.9,
            ),
          ),
          Icon(Icons.open_in_new_rounded, size: 11, color: p.accentText),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dock
// ---------------------------------------------------------------------------

class _ActionDock extends ConsumerWidget {
  const _ActionDock({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: EvPrimaryButton(
                label: 'Check my result',
                icon: Icons.bolt_rounded,
                onPressed: () {
                  ref.read(selectedCardIdProvider.notifier).select(card.id);
                  ref.read(tabIndexProvider.notifier).select(EvTab.radar);
                },
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: EvSize.primaryButton,
              height: EvSize.primaryButton,
              child: EvSecondaryButton(
                label: '',
                icon: Icons.ios_share_rounded,
                expand: false,
                onPressed: () async {
                  final service = ref.read(shareServiceProvider);
                  await service.shareText(
                    caption:
                        '${card.examName} — roll ${card.rollNumber}. ${card.centerAddress}.',
                    subject: card.examName,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'TAP ANY FIELD TO COPY · AES-256 · OFFLINE',
          style: context.type.microLabel.copyWith(
            letterSpacing: 0.7,
            color: context.ev.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: p.textTertiary),
            const SizedBox(height: 16),
            Text('Your vault is empty', style: context.type.sectionTitle),
            const SizedBox(height: 6),
            Text(
              'Roll numbers, registration IDs and centre details — encrypted on this device.',
              textAlign: TextAlign.center,
              style: context.type.bodyMuted,
            ),
            const SizedBox(height: 20),
            EvPrimaryButton(
              label: 'Add admit card',
              icon: Icons.add_rounded,
              expand: false,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit / delete for the card currently on screen.
///
/// Without this the vault was write-once: a mistyped roll number could never be
/// corrected and a finished exam could never be cleared, so the only escape was
/// reinstalling the app.
class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.card});

  final AdmitCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    return SizedBox(
      // The 20px glyph sits in a 44px target; the popup's default padding made
      // the kebab a ~36px tap.
      width: EvSize.minTapTarget,
      height: EvSize.minTapTarget,
      child: PopupMenuButton<String>(
        tooltip: 'Card options',
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EvRadius.inner),
          side: BorderSide(color: p.border),
        ),
        icon: Icon(Icons.more_horiz_rounded, size: 20, color: p.textSecondary),
        onSelected: (value) async {
          switch (value) {
            case 'edit':
              await showVaultFormSheet(context, ref, existing: card);
            case 'delete':
              final confirmed = await _confirmDelete(context, card);
              if (!confirmed) return;
              await ref.read(admitCardsProvider.notifier).delete(card.id);
              ref.read(selectedCardIdProvider.notifier).select(null);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      '${card.examName} deleted',
                      style: context.type.label.copyWith(color: Colors.white),
                    ),
                  ),
                );
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16, color: p.textSecondary),
                const SizedBox(width: 10),
                Text('Edit details', style: context.type.body),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 16, color: p.danger),
                const SizedBox(width: 10),
                Text(
                  'Delete card',
                  style: context.type.body.copyWith(color: p.dangerText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, AdmitCard card) async {
    final p = context.ev;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
        title: Text('Delete this card?', style: context.type.sectionTitle),
        content: Text(
          '${card.examName} and its roll number will be removed from this '
          'device. This cannot be undone.',
          style: context.type.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Keep',
              style: context.type.label.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: context.type.label.copyWith(
                color: p.dangerText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
