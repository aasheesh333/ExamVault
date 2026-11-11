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
      // Landscape cutouts and notches report as MediaQuery padding.left/right;
      // reading only `bottom` here let the floating bar slide under a cutout
      // (and its first/last tab with it) on any landscape device. The bar's
      // own 16px inset is kept on top of the device inset in both axes.
      padding: EdgeInsets.only(
        left: EvSize.tabBarInset + MediaQuery.paddingOf(context).left,
        right: EvSize.tabBarInset + MediaQuery.paddingOf(context).right,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            // Height follows the label scale: the fixed 58px box sliced label
            // text through its baseline at 2.0x and the selected pill cut the
            // word in half. Icon (19) + gap (3) + label, plus padding, with the
            // token as the floor.
            height: _barHeight(context),
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
              // Stretch, not the default center: the buttons then fill the bar's
              // ~48px interior and every tab clears the 44px tap-target floor.
              // Centered, a button hugs its content (~42px at scale 1.0).
              crossAxisAlignment: CrossAxisAlignment.stretch,
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

/// The floating chrome's total footprint, measured by the framework.
///
/// Screens used to end their scroll views with a guessed `SizedBox(height: 120)`
/// (or 130) to clear the tab bar. When the bar's height was made text-aware those
/// constants became wrong, and content disappeared underneath it.
///
/// The first replacement formula (`tabBar + 12 + padding.bottom + 12`) was also
/// wrong, in the opposite direction: under `extendBody: true` the Scaffold
/// already rewrites the body's `MediaQuery.padding.bottom` to
/// `max(deviceInset, bottomNavigationBarHeight)` (see `_BodyBuilder` in
/// scaffold.dart), so adding the bar's height again reserved ~82px of dead
/// space at the end of every scroll view. `padding.bottom` *is* the bar's real
/// footprint — including its text-scale growth and its own bottom margin — so
/// the correct inset is that value plus breathing room.
abstract final class EvChrome {
  /// Vertical space the floating tab bar occupies, plus a little clearance.
  static double bottomInset(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom + 12;
  }
}

/// Tab bar height for the current text scale.
///
/// Deliberately a computed height rather than `minHeight`: a Column inside an
/// unconstrained Row would stretch to the screen instead of hugging its content.
double _barHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final extra = ((scale - 1).clamp(0.0, 1.0)) * 22.0;
  return EvSize.tabBar + extra;
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
      // No `label:`: the visible Text below is the accessible name. Both
      // together made TalkBack announce every tab twice ("Home, Home").
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
          // The label used to paint outside the pill and over its neighbour
          // ("HomeVaultRadarShare"): a Column inside an Expanded receives a
          // *loose* width, and children size to their intrinsic width. `stretch`
          // below pins every child to the tab's real width, and the FittedBox
          // around the label shrinks it to fit before it can ever bleed.
          // Horizontal breathing room: at 2.0x on a 320px screen each column is
          // ~72px and the FittedBox-scaled label fills it exactly, so adjacent
          // labels touched and read as one word ("HomeVaultRadarShare"). The
          // padding both separates them and gives the FittedBox a slightly
          // smaller box, so it scales the label down a touch more.
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Centered explicitly: `stretch` hands the Stack a *tight* full-width
              // constraint, and a Stack with the default topStart alignment then
              // pinned the icon to the pill's left edge while the badge floated at
              // its far right. Center lets the Stack hug the icon, so the badge
              // sits on the icon's corner again.
              Center(
                child: Stack(
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
              ),
              const SizedBox(height: 3),
              // At 2.0x on a 320px screen each column is ~80px wide and four
              // full labels overlapped ("VaultRadaShar"). Scaling the label down
              // to fit keeps the name visible and readable instead of either
              // overlapping or silently disappearing.
              // Bounded by the real remaining width via `LayoutBuilder`, then
              // scaled down to fit. `double.infinity` was not enough: the parent
              // hands down a loose constraint, so the FittedBox sized to its child
              // and drew outside the pill.
              LayoutBuilder(
                builder: (context, box) => SizedBox(
                  width: box.maxWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      style: context.type.label.copyWith(
                        letterSpacing: 0.2,
                        color: selected ? p.accentText : p.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cross-fades between tab bodies while keeping all of them mounted — and,
/// critically, while keeping every tab's `State` alive.
///
/// The previous implementation wrapped each visible tab in a
/// `TweenAnimationBuilder(key: ValueKey(i == _current))`. Those keys *swap* on
/// every switch, so `updateChildren` moved the elements between slots and
/// swapped their `child:` — which unmounted the outgoing screen and inflated
/// the incoming one fresh. Every tab switch silently destroyed both screens'
/// state: scroll offsets, the checker's typed roll number, the share screen's
/// caption edits and its privacy switch. The file's own contract ("each tab
/// keeps its scroll offset") was violated by its own animation.
///
/// The rebuild keeps a *stable* slot per tab: the same widget type at the same
/// position with the same key on every frame, only `offstage`/`opacity` values
/// change. State can then never be lost, and the fade is driven by one
/// AnimationController instead of re-keyed tweens.
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher>
    with SingleTickerProviderStateMixin {
  late int _current = widget.index;
  late int _previous = widget.index;

  /// Starts completed: the initial tab is fully visible, nothing animates.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: EvMotion.paneIn,
    value: 1,
  );

  @override
  void didUpdateWidget(_TabSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != _current) {
      _previous = _current;
      _current = widget.index;
      final duration = EvMotion.of(context, EvMotion.paneIn);
      if (duration == Duration.zero) {
        // Reduced motion: instant swap, same tree shape.
        _fade.value = 1;
      } else {
        _fade
          ..duration = duration
          ..forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        final animating = _fade.isAnimating;
        final tIn = EvMotion.curveOf(
          context,
          EvMotion.enter,
        ).transform(_fade.value);
        final tOut = EvMotion.curveOf(
          context,
          EvMotion.exit,
        ).transform(_fade.value);

        return Stack(
          children: [
            for (var i = 0; i < widget.children.length; i++)
              // Stable identity per slot — this key never changes, so the
              // element (and its screen's State) survives every switch.
              Offstage(
                key: ValueKey('tab-$i'),
                // Only the current tab and the one fading out are on stage.
                offstage: !(i == _current || (i == _previous && animating)),
                child: IgnorePointer(
                  // The outgoing tab must not accept taps while it fades.
                  ignoring: i != _current,
                  child: Opacity(
                    opacity: !animating
                        ? (i == _current ? 1 : 0)
                        : (i == _current ? tIn : 1 - tOut).clamp(0.0, 1.0),
                    child: widget.children[i],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
