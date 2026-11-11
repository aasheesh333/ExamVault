import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/admit_card.dart';
import 'wallet_pass_card.dart';

/// The fanned stack of admit cards.
///
/// Geometry copied from the Figma frame so the two never drift:
///   front   top 88,  inset 0
///   middle  top 40,  inset 10
///   back    top 0,   inset 20
///
/// Only the front card is interactive. The peeking headers are decorative — a
/// tap that opens the *wrong* exam's pass on exam morning is worse than no tap.
class WalletCardStack extends StatelessWidget {
  const WalletCardStack({
    super.key,
    required this.cards,
    required this.onOpen,
    this.maxLayers = 3,
  });

  final List<AdmitCard> cards;
  final void Function(AdmitCard card) onOpen;
  final int maxLayers;

  /// Vertical offset between stacked cards.
  static const _layer = 44.0;
  static const _insets = [20.0, 10.0, 0.0];

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final visible = cards.take(maxLayers).toList();

    // The "wallet" look only exists with two or more cards: the front card sits
    // lower so the cards behind it peek out at the top. With a single card that
    // offset was still applied, leaving a 220px hole between the section header
    // and the one card the user owns.
    //
    // At large text the deck is *dropped* rather than scaled: each peeking layer
    // costs 44px of height that the card itself needs, and the card carries the
    // roll number a student reads at the exam gate. The extra count is stated in
    // words instead.
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final layers = largeText ? 0 : visible.length - 1;

    if (largeText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WalletPassCard(card: visible[0], onOpen: () => onOpen(visible[0])),
          // cards.length, not visible.length: `visible` is capped at
          // maxLayers (3), so a user with 5 saved cards read "3 cards total"
          // here while the hero 300px above said "5 exams tracked".
          if (cards.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              '${cards.length} cards total — tap to open all of them',
              style: context.type.bodyMuted,
            ),
          ],
        ],
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Painted back-to-front so the front card sits on top.
        for (var i = visible.length - 1; i >= 1; i--)
          Positioned(
            top: (layers - i) * _layer,
            left: _insets[i],
            right: _insets[i],
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - (i * 0.05),
                child: WalletPassCard(
                  card: visible[i],
                  compact: true,
                  onOpen: () => onOpen(visible[i]),
                ),
              ),
            ),
          ),
        // The front card is deliberately *not* positioned: a Stack sizes itself
        // from its non-positioned children, so this is what makes the deck grow
        // with the type scale instead of painting over the next section.
        Padding(
          padding: EdgeInsets.only(top: layers * _layer),
          child: WalletPassCard(
            card: visible[0],
            onOpen: () => onOpen(visible[0]),
          ),
        ),
      ],
    );
  }
}
