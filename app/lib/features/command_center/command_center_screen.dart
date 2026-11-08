import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/core/theme/theme_tokens.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/features/command_center/widgets/wallet_card_stack.dart';
import 'package:examvault/features/shell/root_shell.dart';
import 'package:examvault/features/vault/vault_form_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
import 'package:examvault/shared/widgets/ev_surfaces.dart';

/// Screen 1 — Aspirant Command Center.
///
/// The whole screen answers one question in under a second: *"is anything
/// happening that I need to act on right now?"* Everything above the fold serves
/// that; everything below it is the archive.
class CommandCenterScreen extends ConsumerWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(filteredCardsProvider);
    final allCards = ref.watch(admitCardsProvider).value ?? const <AdmitCard>[];
    final feed = ref.watch(liveFeedProvider).value;
    final updates = ref.watch(filteredUpdatesProvider);
    final filter = ref.watch(categoryFilterProvider);

    return Scaffold(
      backgroundColor: context.ev.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.ev.accent,
          backgroundColor: context.ev.surface,
          onRefresh: () =>
              ref.read(liveFeedProvider.notifier).refresh(force: true),
          child: ListView(
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const _TopBar(),
              _Hero(
                cardCount: allCards.length,
                liveCount: feed?.feed.liveCount ?? 0,
              ),
              const SizedBox(height: EvSpace.x3),
              const _CategoryChips(),
              const SizedBox(height: EvSpace.x4),
              EvSectionHeader(
                label: 'My admit cards',
                trailing: allCards.isEmpty
                    ? null
                    : EvTextAction(
                        label: '${allCards.length} saved',
                        icon: Icons.chevron_right_rounded,
                        onPressed: () => ref
                            .read(tabIndexProvider.notifier)
                            .select(EvTab.vault),
                      ),
              ),
              const SizedBox(height: EvSpace.x2),
              _VaultSection(cards: cards, hasAnyCard: allCards.isNotEmpty),
              const SizedBox(height: EvSpace.x5),
              _RadarHeader(snapshot: feed),
              const SizedBox(height: EvSpace.x2),
              _RadarSection(updates: updates, filter: filter, snapshot: feed),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;
    final liveCount = ref.watch(liveRadarBadgeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(EvSpace.gutter, 6, EvSpace.gutter, 0),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            _VaultMark(size: 28),
            const SizedBox(width: 9),
            Text(
              'EXAMVAULT',
              style: context.type.statusPill.copyWith(
                color: p.textPrimary,
                fontSize: 10.5,
                letterSpacing: 2.6,
              ),
            ),
            const Spacer(),
            EvIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              badgeCount: liveCount,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      liveCount == 0
                          ? 'No new alerts. We will ping you the second a result drops.'
                          : '$liveCount live updates right now.',
                      style: context.type.label.copyWith(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            const _Avatar(),
          ],
        ),
      ),
    );
  }
}

class _VaultMark extends StatelessWidget {
  const _VaultMark({this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF60A5FA), Color(0xFF2563EB), Color(0xFF1D4ED8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Icon(
        Icons.shield_outlined,
        size: size * 0.56,
        color: Colors.white,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surfaceElevated,
        border: Border.all(color: p.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        'A',
        style: context.type.label.copyWith(
          color: p.accentText,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.cardCount, required this.liveCount});

  final int cardCount;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final now = DateTime.now();
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    const weekdays = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    final dateLine =
        '${weekdays[now.weekday - 1]} · ${now.day.toString().padLeft(2, '0')} '
        '${months[now.month - 1]} ${now.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EvSpace.gutter,
        EvSpace.x4 + 2,
        EvSpace.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateLine,
            style: context.type.microLabel.copyWith(
              color: p.textTertiary,
              fontSize: 9,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 5),
          Text('Command Center', style: context.type.hero),
          const SizedBox(height: 5),
          // Both numbers are derived, never hardcoded — the subtitle can never
          // contradict the list underneath it.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: cardCount == 1
                      ? '1 exam tracked'
                      : '$cardCount exams tracked',
                  style: context.type.body.copyWith(color: p.textSecondary),
                ),
                TextSpan(
                  text: '   ·   ',
                  style: context.type.body.copyWith(color: p.textTertiary),
                ),
                TextSpan(
                  text: liveCount == 1
                      ? '1 live update'
                      : '$liveCount live updates',
                  style: context.type.body.copyWith(
                    color: liveCount > 0 ? p.successText : p.textTertiary,
                    fontWeight: FontWeight.w600,
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

// ---------------------------------------------------------------------------
// Chips
// ---------------------------------------------------------------------------

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(categoryFilterProvider);
    final p = context.ev;

    return SizedBox(
      height: EvSize.minTapTarget,
      child: Stack(
        children: [
          ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter - 4),
            children: [
              EvChip(
                label: 'All Exams',
                selected: active == null,
                onTap: () =>
                    ref.read(categoryFilterProvider.notifier).select(null),
              ),
              for (final c in ExamCategory.values) ...[
                const SizedBox(width: 7),
                EvChip(
                  label: c.label,
                  selected: active == c,
                  onTap: () =>
                      ref.read(categoryFilterProvider.notifier).select(c),
                ),
              ],
              const SizedBox(width: 28),
            ],
          ),
          // Fades the last chip so the row reads as scrollable rather than cut.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [p.bg.withValues(alpha: 0), p.bg],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault section
// ---------------------------------------------------------------------------

class _VaultSection extends ConsumerWidget {
  const _VaultSection({required this.cards, required this.hasAnyCard});

  final List<AdmitCard> cards;
  final bool hasAnyCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) {
      return _EmptyVault(hasAnyCard: hasAnyCard);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
      child: WalletCardStack(
        cards: cards,
        onOpen: (card) {
          ref.read(selectedCardIdProvider.notifier).select(card.id);
          ref.read(tabIndexProvider.notifier).select(EvTab.vault);
        },
      ),
    );
  }
}

class _EmptyVault extends ConsumerWidget {
  const _EmptyVault({required this.hasAnyCard});

  final bool hasAnyCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
      child: EvCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(EvRadius.tile),
              ),
              child: Icon(
                Icons.add_card_rounded,
                color: p.accentText,
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              hasAnyCard
                  ? 'No cards in this category'
                  : 'Add your first admit card',
              textAlign: TextAlign.center,
              style: context.type.sectionTitle.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              hasAnyCard
                  ? 'Try “All Exams” or save a new card.'
                  : 'Roll number, centre and password — one tap away on exam day.',
              textAlign: TextAlign.center,
              style: context.type.bodyMuted,
            ),
            const SizedBox(height: 14),
            EvSecondaryButton(
              label: 'Add admit card',
              icon: Icons.add_rounded,
              expand: false,
              onPressed: () => showVaultFormSheet(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Radar
// ---------------------------------------------------------------------------

class _RadarHeader extends StatelessWidget {
  const _RadarHeader({this.snapshot});

  final LiveFeedSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final source = snapshot?.source;

    final String status;
    if (snapshot == null) {
      status = 'CONNECTING…';
    } else if (source == FeedSource.network) {
      status = 'LIVE · EDGE';
    } else if (source == FeedSource.cache) {
      status = 'CACHED';
    } else {
      status = 'SAMPLE DATA';
    }

    return EvSectionHeader(
      label: 'Live radar',
      leading: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: source == FeedSource.network ? p.success : p.textTertiary,
          shape: BoxShape.circle,
          boxShadow: source == FeedSource.network
              ? [
                  BoxShadow(
                    color: p.success.withValues(alpha: 0.8),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
      trailing: Text(
        status,
        style: context.type.microLabel.copyWith(
          fontSize: 8.5,
          letterSpacing: 1.1,
          color: source == FeedSource.network ? p.successText : p.textTertiary,
        ),
      ),
    );
  }
}

class _RadarSection extends ConsumerWidget {
  const _RadarSection({
    required this.updates,
    required this.filter,
    this.snapshot,
  });

  final List<LiveUpdate> updates;
  final ExamCategory? filter;
  final LiveFeedSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    if (updates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
        child: EvCard(
          child: Row(
            children: [
              Icon(Icons.radar_rounded, color: p.textTertiary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  filter == null
                      ? 'Nothing live yet. We poll the edge every 60 s.'
                      : 'Nothing live for ${filter!.label} right now.',
                  style: context.type.bodyMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
      child: EvCard(
        padding: EdgeInsets.zero,
        onTap: null,
        child: Column(
          children: [
            for (var i = 0; i < updates.length; i++)
              LiveRadarTile(
                key: ValueKey('${updates[i].examId}-${updates[i].publishedAt}'),
                update: updates[i],
                isFirst: i == 0,
                isLast: i == updates.length - 1,
                onTap: () => _openResult(context, ref, updates[i]),
              ),
          ],
        ),
      ),
    );
  }

  void _openResult(BuildContext context, WidgetRef ref, LiveUpdate update) {
    ref.read(resultExamIdProvider.notifier).select(update);
    ref.read(tabIndexProvider.notifier).select(EvTab.radar);
  }
}
