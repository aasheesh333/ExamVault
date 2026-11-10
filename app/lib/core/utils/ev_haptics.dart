import 'package:flutter/services.dart';

/// The app's whole haptic vocabulary, in one place.
///
/// There were exactly two haptics in the entire app: one on copy, one on a found
/// result. Tab switches, chip selects, opening a result, saving a card, closing a
/// sheet and deleting all landed in silence — and in a crowded exam-centre queue,
/// with the phone half-watched, silence reads as "the tap missed".
///
/// Reserved meaning: `heavy` belongs to failure only. If everything is heavy,
/// nothing is.
abstract final class EvHaptics {
  /// A deliberate selection: tab, chip, segmented choice.
  static Future<void> select() => HapticFeedback.selectionClick();

  /// A navigation or state change the user initiated: open a result, save a card.
  static Future<void> tap() => HapticFeedback.lightImpact();

  /// The answer arrived and it matters: a result found.
  static Future<void> success() => HapticFeedback.mediumImpact();

  /// Something failed and the user must notice: a wrong roll, a broken fetch.
  static Future<void> failure() => HapticFeedback.heavyImpact();
}
