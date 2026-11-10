import 'package:flutter/material.dart';

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

  /// Vertical offset between stacked cards, and the card's own height.
  static const _layer = 44.0;
  static const _cardHeight = 180.0;
  static const _insets = [20.0, 10.0, 0.0];

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final visible = cards.take(maxLayers).toList();

    // The "wallet" look only exists with two or more cards: the front card sits
    // lower so the cards behind it peek out at the top. With a single card that
    // offset was still applied, leaving a 220px hole between the section header
    // and the one card the user owns.
    final layers = visible.length - 1;

    return SizedBox(
      height: _cardHeight + layers * _layer,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted back-to-front so the front card sits on top.
          for (var i = visible.length - 1; i >= 0; i--)
            Positioned(
              top: (layers - i) * _layer,
              left: _insets[i],
              right: _insets[i],
              child: i == 0
                  ? WalletPassCard(
                      card: visible[i],
                      onOpen: () => onOpen(visible[i]),
                    )
                  : IgnorePointer(
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
        ],
      ),
    );
  }
}
