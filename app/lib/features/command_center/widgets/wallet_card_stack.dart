import 'package:flutter/material.dart';

import '../../../core/theme/theme_tokens.dart';
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

  static const _frontTop = 88.0;
  static const _insets = [20.0, 10.0, 0.0];

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final visible = cards.take(maxLayers).toList();

    return SizedBox(
      height: EvSize.walletStack,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted back-to-front so the front card sits on top.
          for (var i = visible.length - 1; i >= 0; i--)
            Positioned(
              top: _frontTop - (i * 44),
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
