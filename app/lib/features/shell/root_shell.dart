import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
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

    return Scaffold(
      backgroundColor: context.ev.bg,
      extendBody: true,
      body: IndexedStack(
        index: tab.index,
        children: const [
          CommandCenterScreen(),
          AdmitCardDetailScreen(),
          InstantResultCheckerScreen(),
          WhatsappShareCardScreen(),
        ],
      ),
      bottomNavigationBar: const EvTabBar(),
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
              border: Border.all(color: p.isDark ? p.borderStrong.withValues(alpha: 0.8) : p.border),
            ),
            child: Row(
              children: [
                for (final t in EvTab.values)
                  Expanded(
                    child: _TabButton(
                      tab: t,
                      selected: active == t,
                      badge: t == EvTab.radar && liveCount > 0 ? liveCount : null,
                      onTap: () => ref.read(tabIndexProvider.notifier).select(t),
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
          duration: EvMotion.fast,
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.13) : Colors.transparent,
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
                  fontSize: 8.5,
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
