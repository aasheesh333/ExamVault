import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/utils/ev_haptics.dart';
import '../../core/theme/theme_tokens.dart';
import '../../features/command_center/command_center_screen.dart';
import '../../features/result_checker/instant_result_checker_screen.dart';
import '../../features/share_card/whatsapp_share_card_screen.dart';
import '../../features/vault/admit_card_detail_screen.dart';
import '../../providers/app_providers.dart';

/// The four destinations, in the order they appear in the tab bar.
enum EvTab {
  home('Home', Icons.home_rounded),
  vault('Vault', Icons.lock_rounded),
  radar('Radar', Icons.radar_rounded),
  share('Share', Icons.ios_share_rounded);

  const EvTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class TabIndexNotifier extends Notifier<EvTab> {
  @override
  EvTab build() => EvTab.home;

  void select(EvTab tab) => state = tab;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, EvTab>(
  TabIndexNotifier.new,
);

/// Root shell.
///
/// Uses an `IndexedStack` rather than a `PageView`: each tab keeps its scroll
/// offset and — critically — its downloaded state. A user who checks a result,
/// swipes to Share, and comes back must not re-download the 150 KB index.
class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabIndexProvider);

    // Android back, handled.
    //
    // Every tab lives in one IndexedStack under a single route, so
    // `Navigator.canPop` is always false and the system back gesture finished the
    // activity from *any* tab — including mid-check, and immediately after landing
    // there from a radar tap. The manifest opts into predictive back, so the OS
    // even previewed the exit.
    //
    // Back now means "go up one level": leave the current tab for Home, and only
    // exit when Home is already showing.
    return PopScope(
      canPop: tab == EvTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(tabIndexProvider.notifier).select(EvTab.home);
      },
      child: Scaffold(
        backgroundColor: context.ev.bg,
        extendBody: true,
        // A cross-fade, not a hard swap.
        //
        // `IndexedStack` keeps every tab alive (scroll offsets, downloaded
        // indexes) but changed screens in a single frame, so a tap felt
        // unregistered until the new screen had already replaced the old one.
        // Fading the outgoing tab out and the incoming one in — while both stay
        // mounted — gives the change a direction without losing state.
        body: _TabSwitcher(
          index: tab.index,
          children: const [
            CommandCenterScreen(),
            AdmitCardDetailScreen(),
            InstantResultCheckerScreen(),
            WhatsappShareCardScreen(),
          ],
        ),
        bottomNavigationBar: const EvTabBar(),
      ),
    );
  }
}

class EvTabBar extends ConsumerWidget {
  const EvTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final active = ref.watch(tabIndexProvider);
    final liveCount = ref.watch(liveRadarBadgeProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: EvSize.tabBarInset,
        right: EvSize.tabBarInset,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: EvSize.tabBar,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: p.isDark ? 0.82 : 0.9),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: p.isDark
                    ? p.borderStrong.withValues(alpha: 0.8)
                    : p.border,
              ),
            ),
            child: Row(
              children: [
                for (final t in EvTab.values)
                  Expanded(
                    child: _TabButton(
                      tab: t,
                      selected: active == t,
                      badge: t == EvTab.radar && liveCount > 0
                          ? liveCount
                          : null,
                      onTap: () {
                        if (active == t) return;
                        EvHaptics.select();
                        ref.read(tabIndexProvider.notifier).select(t);
                      },
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final EvTab tab;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EvRadius.button),
        child: AnimatedContainer(
          duration: EvMotion.of(context, EvMotion.micro),
          decoration: BoxDecoration(
            color: selected
                ? p.accent.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(EvRadius.button),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    tab.icon,
                    size: 19,
                    color: selected ? p.accentText : p.textTertiary,
                  ),
                  if (badge != null)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: p.danger,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: p.danger.withValues(alpha: 0.8),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: context.type.label.copyWith(
                  letterSpacing: 0.2,
                  color: selected ? p.accentText : p.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cross-fades between tab bodies while keeping all of them mounted.
///
/// Only the incoming and outgoing tabs are painted, so the cost is one fade rather
/// than four always-visible layers.
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher> {
  late int _current = widget.index;
  late int _previous = widget.index;

  @override
  void didUpdateWidget(_TabSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != _current) {
      _previous = _current;
      _current = widget.index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = EvMotion.of(context, EvMotion.paneIn);

    // Reduced motion (or a zero duration) collapses to the plain stack.
    if (duration == Duration.zero) {
      return IndexedStack(index: _current, children: widget.children);
    }

    return Stack(
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (i == _current || i == _previous)
            TweenAnimationBuilder<double>(
              key: ValueKey(i == _current),
              tween: Tween(begin: i == _current ? 0 : 1, end: i == _current ? 1 : 0),
              duration: duration,
              curve: EvMotion.curveOf(
                context,
                i == _current ? EvMotion.enter : EvMotion.exit,
              ),
              builder: (context, t, child) => IgnorePointer(
                // The outgoing tab must not accept taps while it fades.
                ignoring: i != _current,
                child: Opacity(opacity: t, child: child),
              ),
              child: widget.children[i],
            )
          else
            // Off-stage tabs stay mounted but unsized.
            Offstage(offstage: true, child: widget.children[i]),
      ],
    );
  }
}
