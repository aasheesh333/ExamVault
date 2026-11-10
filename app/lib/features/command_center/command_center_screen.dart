import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/core/utils/ev_haptics.dart';
import 'package:examvault/core/theme/theme_tokens.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/command_center/widgets/alerts_sheet.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/features/command_center/widgets/wallet_card_stack.dart';
import 'package:examvault/features/about/about_sheet.dart';
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
    final cardsAsync = ref.watch(admitCardsProvider);
    final cards = ref.watch(filteredCardsProvider);
    final allCards = cardsAsync.value ?? const <AdmitCard>[];
    final feed = ref.watch(liveFeedProvider).value;
    final updates = ref.watch(filteredUpdatesProvider);
    final filter = ref.watch(categoryFilterProvider);
    final searching = ref.watch(searchActiveProvider);
    final p = context.ev;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: p.accent,
          backgroundColor: p.surface,
          onRefresh: () =>
              ref.read(liveFeedProvider.notifier).refresh(force: true),
          // A sliver list, not a Column of 60 rows: the radar used to build every
          // row eagerly (~1,450 widgets) and re-lay all of them out on each 60 s
          // poll, which hitched while reading.
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _TopBar()),
              SliverToBoxAdapter(
                child: _Hero(
                  cardCount: cardsAsync.hasValue ? allCards.length : null,
                  liveCount: feed?.feed.liveCount ?? 0,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: EvSpace.x3)),
              const SliverToBoxAdapter(child: _SearchField()),
              const SliverToBoxAdapter(child: SizedBox(height: EvSpace.x3)),
              const SliverToBoxAdapter(child: _CategoryChips()),
              const SliverToBoxAdapter(child: SizedBox(height: EvSpace.x4)),
              SliverToBoxAdapter(
                child: EvSectionHeader(
                  label: 'My admit cards',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (allCards.isNotEmpty)
                        EvTextAction(
                          label: '${allCards.length} saved',
                          icon: Icons.chevron_right_rounded,
                          onPressed: () => ref
                              .read(tabIndexProvider.notifier)
                              .select(EvTab.vault),
                        ),
                      // Add is always available, not only in the empty state.
                      // A vault you cannot add to is not a vault.
                      const SizedBox(width: 8),
                      EvTextAction(
                        label: 'Add',
                        icon: Icons.add_rounded,
                        color: p.accentText,
                        onPressed: () => showVaultFormSheet(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: EvSpace.x2)),
              SliverToBoxAdapter(
                child: _VaultSection(state: cardsAsync, cards: cards),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: EvSpace.x5)),
              SliverToBoxAdapter(
                child: _RadarHeader(
                  snapshot: feed,
                  shown: updates.length,
                  total: feed?.feed.activeAt(DateTime.now()).length ?? 0,
                  searching: searching,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: EvSpace.x2)),
              _RadarSliver(updates: updates, filter: filter, searching: searching),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
                fontSize: 11.5,
                letterSpacing: 2.6,
              ),
            ),
            const Spacer(),
            EvIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              badgeCount: liveCount,
              // Opened a SnackBar restating the badge count. Now it opens the
              // alerts inbox and clears the badge once read.
              onPressed: () async {
                await showAlertsSheet(context, ref);
                if (!context.mounted) return;
                await ref.read(alertsSeenProvider.notifier).markSeen();
              },
            ),
            const SizedBox(width: 8),
            _AboutButton(),
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

/// Opens About / sources / privacy.
///
/// This slot used to hold a circle with a hardcoded "A" in it: an avatar for an
/// app with no accounts, implying a signed-in user who did not exist and doing
/// nothing when tapped. It now leads somewhere real — provenance, the copyright
/// stance and what the app stores.
class _AboutButton extends StatelessWidget {
  const _AboutButton();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Semantics(
      button: true,
      label: 'About ExamVault, data sources and privacy',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showAboutSheet(context),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.surfaceElevated,
            border: Border.all(color: p.accent.withValues(alpha: 0.4)),
          ),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: p.accentText,
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.cardCount, required this.liveCount});

  /// Null while the encrypted vault is still being read. It used to be `0` in
  /// that window, so every cold start briefly told a returning user that they had
  /// no cards — the most alarming thing this screen can say.
  final int? cardCount;
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
              fontSize: 11,
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
                  text: switch (cardCount) {
                    null => 'Reading your vault…',
                    1 => '1 exam tracked',
                    final n => '$n exams tracked',
                  },
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

/// Search across the radar and the saved cards.
///
/// Nothing in the app let a user ask for an exam by name. The radar carries ~60
/// rows from five commissions (five and a half screens) and the chips only narrow
/// it to about 20, so finding "RRB CEN 01/2025" — or the radar row matching the
/// card already in the wallet — was a blind scroll.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final query = ref.watch(searchQueryProvider);

    // Keep the field in step when something else clears the query.
    if (_controller.text != query && !_focus.hasFocus) {
      _controller.text = query;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(EvRadius.inner),
          border: Border.all(
            color: _focus.hasFocus ? p.accent : p.border,
            width: _focus.hasFocus ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded, size: 18, color: p.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onChanged: ref.read(searchQueryProvider.notifier).set,
                onSubmitted: (_) => _focus.unfocus(),
                style: context.type.body.copyWith(color: p.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  // The theme fills inputs, which painted a second rounded box
                  // inside the container's own border.
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Search exam, result or your card',
                  hintStyle: context.type.body.copyWith(
                    color: p.textTertiary,
                  ),
                ),
              ),
            ),
            if (query.isNotEmpty)
              Semantics(
                button: true,
                label: 'Clear search',
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).clear();
                    _focus.unfocus();
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

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
          // A chip sliced in half reads as a layout bug, but a fade that goes
          // fully opaque *hides the chip entirely* — which is what happened: the
          // strip measured ~470px against a 393px viewport, and "State PSC" (the
          // only state-PSC entry point) started at x≈386, under a 56px opaque
          // gradient. A narrow, semi-transparent fade signals "more" while still
          // letting the next chip peek through.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 22,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.bg.withValues(alpha: 0),
                      p.bg.withValues(alpha: 0.72),
                    ],
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
  const _VaultSection({required this.state, required this.cards});

  final AsyncValue<List<AdmitCard>> state;
  final List<AdmitCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    // Loading, failure and "genuinely empty" are three different facts, and the
    // screen used to collapse all of them into "Add your first admit card" — so a
    // slow Keystore read or a storage fault looked like data loss.
    if (state.isLoading && !state.hasValue) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: EvSpace.gutter),
        child: _VaultSkeleton(),
      );
    }

    if (state.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
        child: EvCard(
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: p.warning, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Could not open your vault. Your cards are still on this '
                  'device — tap retry.',
                  style: context.type.bodyMuted,
                ),
              ),
              const SizedBox(width: 8),
              EvTextAction(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(admitCardsProvider),
              ),
            ],
          ),
        ),
      );
    }

    if (cards.isEmpty) {
      return _EmptyVault(hasAnyCard: state.value?.isNotEmpty ?? false);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
      child: WalletCardStack(
        cards: cards,
        onOpen: (card) {
          ref.read(selectedCardIdProvider.notifier).select(card.id);
          // Opening a card must clear a previously tapped radar exam, or the
          // checker keeps searching that exam's index with this card's roll.
          ref.read(resultExamIdProvider.notifier).select(null);
          ref.read(tabIndexProvider.notifier).select(EvTab.vault);
        },
      ),
    );
  }
}

/// Placeholder shape while the encrypted vault is read.
class _VaultSkeleton extends StatelessWidget {
  const _VaultSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    return Container(
      height: 176,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(EvRadius.card),
        border: Border.all(color: p.border),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: p.textTertiary,
          ),
        ),
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
      // A plain container, not `EvCard`: EvCard contributes a semantic container
      // which merged this whole block into one 361x209 button. With nothing but
      // the CTA left in the tree, VoiceOver reads "Add admit card, button".
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(EvRadius.card),
          border: Border.all(color: p.border),
        ),
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
  const _RadarHeader({
    this.snapshot,
    this.shown = 0,
    this.total = 0,
    this.searching = false,
  });

  final LiveFeedSnapshot? snapshot;

  /// Rows currently listed, and rows available before filtering. Showing both
  /// while a search runs is the difference between "nothing exists" and "nothing
  /// matched", which are very different answers.
  final int shown;
  final int total;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final source = snapshot?.source;

    // A network fetch is not the same thing as *fresh* data: the edge object can
    // legitimately be hours old. Printing "LIVE" for a day-old document is the
    // kind of small lie that destroys trust on result day, so the age is shown
    // whenever it exceeds the poll interval.
    final generated = snapshot?.feed.generatedAt;
    final age = generated == null ? null : DateTime.now().difference(generated);

    // A cached document always states its age, even when fresh: "CACHED" alone
    // gives no way to tell "saved four seconds ago" from "saved yesterday", and
    // the age is the whole reason the label exists.
    final String status;
    if (snapshot == null) {
      status = 'CONNECTING…';
    } else if (source == FeedSource.none) {
      status = 'NO FEED';
    } else if (source == FeedSource.cache) {
      status = age == null ? 'CACHED' : 'CACHED · ${_shortAge(age)}';
    } else if (age != null && age.inMinutes >= 2) {
      status = 'EDGE · ${_shortAge(age)} OLD';
    } else {
      status = 'LIVE · EDGE';
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
        // While a search is running the useful number is how many rows matched,
        // not how old the feed is: "3 of 34" answers "did you even look?".
        searching ? '$shown of $total' : status,
        style: context.type.microLabel.copyWith(
          letterSpacing: 1.1,
          color: searching
              ? p.textSecondary
              : (source == FeedSource.network &&
                        (age == null || age.inMinutes < 2)
                    ? p.successText
                    : p.textTertiary),
        ),
      ),
    );
  }
}

class _RadarSliver extends ConsumerWidget {
  const _RadarSliver({
    required this.updates,
    required this.filter,
    this.searching = false,
  });

  final List<LiveUpdate> updates;
  final ExamCategory? filter;
  final bool searching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ev;

    if (updates.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
          child: EvCard(
            child: Row(
              children: [
                Icon(
                  searching
                      ? Icons.search_off_rounded
                      : Icons.radar_rounded,
                  color: p.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    // "Nothing live yet" was a lie when the real answer was
                    // "nothing matched your search".
                    searching
                        ? 'No exam matches that search. Try the exam name, '
                              'the commission, or a year.'
                        : filter == null
                        ? 'Nothing live right now. We check the edge every '
                              '60 seconds.'
                        : 'Nothing live for ${filter!.label} right now.',
                    style: context.type.bodyMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
      sliver: SliverList.builder(
        itemCount: updates.length,
        itemBuilder: (context, i) {
          final first = i == 0;
          final last = i == updates.length - 1;
          return _RadarRowShell(
            first: first,
            last: last,
            child: LiveRadarTile(
              key: ValueKey('${updates[i].examId}-${updates[i].publishedAt}'),
              update: updates[i],
              isFirst: first,
              isLast: last,
              onTap: () => _openResult(context, ref, updates[i]),
            ),
          );
        },
      ),
    );
  }

  void _openResult(BuildContext context, WidgetRef ref, LiveUpdate update) {
    EvHaptics.tap();
    ref.read(resultExamIdProvider.notifier).select(update);
    ref.read(tabIndexProvider.notifier).select(EvTab.radar);
  }
}

/// Draws the shared card surface row by row.
///
/// The radar used to be one `EvCard` wrapping a `Column` of every row, which meant
/// a 3,700px layer built eagerly and clipped as a single Material. Painting the
/// border per row lets the list be lazy while looking identical.
class _RadarRowShell extends StatelessWidget {
  const _RadarRowShell({
    required this.first,
    required this.last,
    required this.child,
  });

  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.ev;
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? EvRadius.card : 0),
      bottom: Radius.circular(last ? EvRadius.card : 0),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: radius,
        border: Border(
          left: BorderSide(color: p.border),
          right: BorderSide(color: p.border),
          top: first ? BorderSide(color: p.border) : BorderSide.none,
          bottom: last ? BorderSide(color: p.border) : BorderSide.none,
        ),
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

String _shortAge(Duration age) {
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  return '${age.inDays}d';
}
