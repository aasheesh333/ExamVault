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
    // Rebuilds at midnight (and on app resume) so `daysUntilExam` — computed
    // from DateTime.now() at build time — cannot go stale overnight. This tab
    // lives in an IndexedStack with no feed poll to refresh it: a student who
    // leaves the app open until exam morning used to see "IN 1 DAYS" all night.
    ref.watch(dayTickProvider);
    final cards = cardsAsync.value ?? const <AdmitCard>[];
    final selectedId = ref.watch(selectedCardIdProvider);

    // Loading and failure are *not* "empty". The repository deliberately
    // rethrows so the UI can tell them apart, and Home does — but this screen
    // collapsed all three into "Your vault is empty", so a slow Keystore read
    // on cold start (all tabs build at launch) greeted users with an Add CTA
    // over a vault that was full, and a Keystore failure claimed the vault was
    // empty forever.
    if (cardsAsync.isLoading) {
      return Scaffold(
        backgroundColor: context.ev.bg,
        body: const SafeArea(child: _VaultLoading()),
      );
    }

    if (cardsAsync.hasError) {
      return Scaffold(
        backgroundColor: context.ev.bg,
        body: SafeArea(
          child: _VaultError(onRetry: () => ref.invalidate(admitCardsProvider)),
        ),
      );
    }

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

  /// Measured height of the floating dock, so the list can reserve exactly that
  /// space instead of guessing 150px.
  final GlobalKey _dockKey = GlobalKey(debugLabel: 'pass-action-dock');
  double _dockHeight = 0;

  @override
  void didUpdateWidget(covariant _PassPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cards.isEmpty) return;
    // A delete shrinks the list and an edited exam date re-sorts it, so the old
    // index now points at a different card: re-resolve the page from the id.
    final target =
        _indexOfSelected(ref.read(selectedCardIdProvider)) ??
        _index.clamp(0, widget.cards.length - 1);
    if (target != _index) {
      _index = target;
      _jumpAfterLayout();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Page index of the selected card, or null when it is not in the list (for
  /// example the frame between a delete and the new selection).
  int? _indexOfSelected(String? id) {
    if (id == null || widget.cards.isEmpty) return null;
    final at = widget.cards.indexWhere((c) => c.id == id);
    return at < 0 ? null : at;
  }

  /// Jump to the page the provider now points at (delete, dock, checker).
  void _jumpAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(_index);
    });
  }

  /// The dock wraps taller as the caption takes a second line at 2.0×, so its
  /// real height is measured rather than assumed.
  void _measureDock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
      final height = box?.size.height ?? 0;
      if (height > 0 && (height - _dockHeight).abs() > 0.5) {
        setState(() => _dockHeight = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Follow selection changes that did not come from this PageView's gesture.
    ref.listen<String?>(selectedCardIdProvider, (_, next) {
      final target = _indexOfSelected(next) ?? _index;
      if (target != _index) {
        setState(() => _index = target);
        _jumpAfterLayout();
      }
    });

    _measureDock();

    final p = context.ev;
    final current = widget.cards[_index.clamp(0, widget.cards.length - 1)];
    // Reserve the dock's real footprint plus the safe-area inset, so the last
    // checklist row can always be scrolled clear of "Check my result".
    final dockBottom = MediaQuery.paddingOf(context).bottom + 14;
    final listBottom = dockBottom + _dockHeight + 16;

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
                itemBuilder: (context, i) =>
                    _PassPage(card: widget.cards[i], bottomInset: listBottom),
              ),
            ),
          ],
        ),
        // Fade behind the dock so content never collides with a floating button.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: dockBottom + _dockHeight + 24,
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
          bottom: dockBottom,
          child: _ActionDock(key: _dockKey, card: current),
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
    return ConstrainedBox(
      // A fixed 40px bar clipped "Saved Pass" to 7px of overflow at 2.0×, so the
      // token is a floor for content-driven height.
      constraints: const BoxConstraints(minHeight: EvSize.navBar),
      child: Stack(
        alignment: Alignment.center,
        // The kebab's 44px hit box is 4px taller than the 40px bar.
        clipBehavior: Clip.none,
        children: [
          // Title before actions: a screen reader used to announce "button,
          // button" and only then "Saved Pass".
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Saved Pass', style: context.type.navTitle),
                const SizedBox(height: 3),
                _PageCounter(count: count, controller: controller),
              ],
            ),
          ),
          Row(
            children: [
              const SizedBox(width: EvSpace.x2),
              EvIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                ghost: true,
                iconSize: 17,
                tooltip: 'Back',
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
        ],
      ),
    );
  }
}

/// "3 / 10" position indicator.
///
/// The old 4×4px dots carried no count, were not announced, and the inactive
/// dot sat at ~1.5:1 on navy.
class _PageCounter extends StatelessWidget {
  const _PageCounter({required this.count, required this.controller});

  final int count;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ready =
            controller.hasClients && controller.position.haveDimensions;
        final page = ready ? (controller.page ?? 0) : 0;
        final index = page.round().clamp(0, count - 1);

        return Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Pass ${index + 1} of $count',
          child: Text(
            '${index + 1} / $count',
            style: context.type.monoMeta.copyWith(color: p.textSecondary),
          ),
        );
      },
    );
  }
}

class _PassPage extends ConsumerWidget {
  const _PassPage({required this.card, required this.bottomInset});

  final AdmitCard card;

  /// Space reserved for the floating dock, measured by the pager.
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        EvSpace.gutter,
        8,
        EvSpace.gutter,
        bottomInset,
      ),
      children: [
        _BoardingPass(card: card),
        const SizedBox(height: EvSpace.x3),
        _CountdownCard(card: card),
        const SizedBox(height: EvSpace.x3),
        _DocumentChecklist(card: card),
        const SizedBox(height: EvSpace.x3),
        // Gate and reporting time matter even when no address was saved.
        if (card.centerAddress.isNotEmpty ||
            card.gate.isNotEmpty ||
            card.reportBy.isNotEmpty)
          _CenterCard(card: card),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
                        // Floor, not fixed: the hard 22px box sliced VERIFIED /
                        // SAVED at large text scales. The child Row is min-sized
                        // and fills the minHeight, centring itself — no
                        // `alignment:` (an aligned Container in a Row expands to
                        // the row's free width).
                        constraints: const BoxConstraints(minHeight: 22),
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
                      // The label used to be an unbounded Text beside a flexible
                      // barcode: at 2.0x on a 320px phone the barcode collapsed to
                      // zero and the label overflowed 107px past the card edge.
                      Flexible(
                        child: Text(
                          'SAVED ON DEVICE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.statusPill.copyWith(
                            color: p.onWalletFaint,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
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
        // Short labels: the full words ellipsised at 1.0× on a 393px screen.
        label: 'REG. ID',
        value: card.registrationId,
        copyLabel: 'Registration ID',
      ),
      (
        label: 'DOB / PASSWORD',
        value: card.dobOrPortalPassword,
        copyLabel: 'Password',
      ),
      (label: 'CENTRE', value: card.centerCode, copyLabel: 'Centre code'),
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
      // The old label promised "Tap to copy." even for empty optional fields,
      // where onTap is null and the row shows "—" — an instruction for an
      // interaction that does not exist.
      label: hasValue
          ? '${field.label}: ${field.value}. Tap to copy.'
          : '${field.label}: not provided.',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            // minHeight, no `alignment:` — an aligned Container inside a Row
            // expands to the row's free width, which starved the Expanded
            // countdown text beside it to a sliver. The min-sized Row child
            // fills the minHeight and centres itself.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: (urgent ? p.danger : p.accent).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(EvRadius.tile),
              border: Border.all(
                color: (urgent ? p.danger : p.accent).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  days < 0
                      ? 'PAST'
                      : days == 0
                      ? 'TODAY'
                      : 'IN $days DAYS',
                  maxLines: 1,
                  style: context.type.statusPill.copyWith(
                    color: urgent ? p.dangerText : p.accentText,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 6),
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
    final hasAddress = card.centerAddress.isNotEmpty;
    final heading = card.centerCode.isEmpty
        ? 'EXAM CENTRE'
        : 'EXAM CENTRE · ${card.centerCode}'.toUpperCase();

    final query = Uri.encodeComponent(
      '${card.centerAddress} ${card.centerCode}'.trim(),
    );

    return EvCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      // Maps needs an address; a gate-only card stays informative, not a dead link.
      onTap: hasAddress
          ? () async {
              final uri = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$query',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          : null,
      semanticLabel: [
        heading,
        if (hasAddress) card.centerAddress,
        if (card.gate.isNotEmpty) card.gate,
        if (card.reportBy.isNotEmpty) 'report by ${card.reportBy}',
      ].join('. '),
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
                  heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.microLabel.copyWith(),
                ),
                if (hasAddress) ...[
                  const SizedBox(height: 2),
                  Text(
                    card.centerAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.tileTitle.copyWith(),
                  ),
                ],
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
          if (hasAddress) ...[
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dock
// ---------------------------------------------------------------------------

class _ActionDock extends ConsumerWidget {
  const _ActionDock({super.key, required this.card});

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
                  // Opening a card must clear a previously tapped radar exam —
                  // the checker prioritises `resultExamIdProvider` over the
                  // chosen card everywhere (header, examId, stale-roll guard).
                  // Without this reset, a radar row tapped any time earlier in
                  // the session hijacked this card's check: the roll field was
                  // wiped as "stale" and a retyped roll was searched against
                  // the *other* exam's index — a confident wrong verdict.
                  // Home's card-open path already did this; the dock didn't.
                  ref.read(resultExamIdProvider.notifier).select(null);
                  ref.read(selectedCardIdProvider.notifier).select(card.id);
                  ref.read(tabIndexProvider.notifier).select(EvTab.radar);
                },
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: EvSize.primaryButton,
              height: EvSize.primaryButton,
              // Icon-only secondary action: the icon button exposes a real name
              // ("Share pass"), where `EvSecondaryButton(label: '')` announced a
              // bare button with no label at all.
              child: EvIconButton(
                icon: Icons.ios_share_rounded,
                tooltip: 'Share pass',
                size: EvSize.primaryButton,
                iconSize: 17,
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

/// Shown while the encrypted store is still being read.
///
/// Distinct from [_EmptyState] on purpose: "Your vault is empty" while the
/// Keystore read is in flight told users with saved cards that their data was
/// gone, and offered an Add CTA on top of it.
class _VaultLoading extends StatelessWidget {
  const _VaultLoading();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return EvCenteredScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(p.accentText),
            ),
          ),
          const SizedBox(height: 12),
          Text('Reading your vault…', style: context.type.bodyMuted),
        ],
      ),
    );
  }
}

/// Shown when the encrypted store could not be read.
///
/// Mirrors Home's vault-error card: the cards are still on the device, and the
/// honest action is a retry — never "your vault is empty".
class _VaultError extends StatelessWidget {
  const _VaultError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return EvCenteredScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 40, color: p.warning),
          const SizedBox(height: 16),
          Text('Could not open your vault', style: context.type.sectionTitle),
          const SizedBox(height: 6),
          Text(
            'Your cards are still on this device — nothing was lost. '
            'Tap retry to read them again.',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
          const SizedBox(height: 20),
          EvPrimaryButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            expand: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return EvCenteredScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              if (!context.mounted) return;
              // Saving re-sorts by exam date; keep the pager on this card's id
              // instead of the index it happened to occupy before the edit.
              ref.read(selectedCardIdProvider.notifier).select(card.id);
            case 'delete':
              final confirmed = await _confirmDelete(context, card);
              if (!confirmed) return;
              // The list is sorted, so the card's index before the delete is the
              // index of the card that should stay on screen afterwards.
              final before = ref.read(admitCardsProvider).value;
              final at = before?.indexWhere((c) => c.id == card.id) ?? -1;
              await ref.read(admitCardsProvider.notifier).delete(card.id);
              final after = ref.read(admitCardsProvider).value;
              final stay = (after == null || after.isEmpty)
                  ? null
                  : after[(at < 0 ? 0 : at).clamp(0, after.length - 1)].id;
              ref.read(selectedCardIdProvider.notifier).select(stay);
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
