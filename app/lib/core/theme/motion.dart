import 'package:flutter/material.dart';

/// Motion tokens.
///
/// Before this file the app had three animations in total and the one big moment —
/// a result being found — was a 420 ms `easeOutBack` pop that overshot past 100 %
/// like a toy. Tabs snapped, screens teleported, and nothing acknowledged a tap.
///
/// The rules here, adapted from the Astryx design-system conventions:
///
///  * motion explains a change of state; it never decorates;
///  * exit is faster than enter (~⅔), so a dismissed thing feels dismissed;
///  * no overshoot on a trust-critical path — a result screen should not bounce;
///  * one celebratory moment per flow;
///  * every duration is zero when the OS asks for reduced motion.
abstract final class EvMotion {
  // ---------------------------------------------------------------- durations
  /// Press-in feedback (scale/overlay).
  static const press = Duration(milliseconds: 90);
  static const pressOut = Duration(milliseconds: 140);

  /// State changes inside a screen: chip select, checkbox, pill cross-fade.
  static const micro = Duration(milliseconds: 160);

  /// Inline content appearing: a result card, a spinner replacing a label.
  static const inline = Duration(milliseconds: 180);

  /// Switching tabs. Out is faster than in.
  static const paneOut = Duration(milliseconds: 200);
  static const paneIn = Duration(milliseconds: 220);

  /// Modal sheets and dialogs.
  static const overlayIn = Duration(milliseconds: 260);
  static const overlayOut = Duration(milliseconds: 180);

  /// The one celebration: the found-roll dialog.
  static const reveal = Duration(milliseconds: 240);

  /// Snackbars. The old 1.6 s was too short to read a sentence.
  static const toast = Duration(seconds: 3);

  /// Per-item stagger inside a reveal. Capped so it can never feel slow.
  static const stagger = Duration(milliseconds: 40);

  // ------------------------------------------------------------------ curves
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;

  // ----------------------------------------------------------------- reduce
  /// Resolves a duration against the platform's reduce-motion setting.
  ///
  /// Reading `MediaQuery.disableAnimationsOf` here rather than at each call site
  /// means the guarantee holds for anything added later — previously nothing in
  /// the app consulted the flag at all.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  /// A curve that degrades to linear when motion is reduced, so an animation whose
  /// duration is zero does not still try to overshoot on the final frame.
  static Curve curveOf(BuildContext context, Curve curve) =>
      MediaQuery.disableAnimationsOf(context) ? Curves.linear : curve;

  /// Stagger offset for the [index]-th child, or zero under reduced motion.
  static Duration staggerFor(BuildContext context, int index) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : stagger * index.clamp(0, 3);
}
