// Design tokens for ExamVault.
//
// Single source of truth for colour, spacing, radius, elevation and type.
// Mirrors `design/tokens.json` in the repo root 1:1 — if a value changes here it
// must change in the Figma file too.
//
// Rules that the whole UI depends on:
//  * The 8pt grid. Every spacing constant is a multiple of 4, everything larger
//    than 12 is a multiple of 8.
//  * Minimum tap target 44x44 — visual size may be smaller, hit area may not.
//  * Body text never below 11px; micro-labels never below 8px.
//  * Status colour is *always* paired with a text label, never colour alone.

import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Colour
/// ---------------------------------------------------------------------------

/// Raw palette. Names describe the role, not the hue, so the same token can be
/// re-pointed per theme without touching call sites.
@immutable
class EvPalette {
  const EvPalette({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceElevated,
    required this.border,
    required this.borderStrong,
    required this.walletBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentBright,
    required this.accentDeep,
    required this.accentText,
    required this.success,
    required this.successText,
    required this.warning,
    required this.warningText,
    required this.danger,
    required this.dangerText,
    required this.walletTop,
    required this.walletMid,
    required this.walletBottom,
    required this.onWallet,
    required this.onWalletMuted,
    required this.onWalletFaint,
    required this.brightness,
  });

  final Color bg;
  final Color surface;
  final Color surfaceSunken;
  final Color surfaceElevated;
  final Color border;
  final Color borderStrong;
  final Color walletBorder;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accent;
  final Color accentBright;
  final Color accentDeep;
  final Color accentText;

  final Color success;
  final Color successText;
  final Color warning;
  final Color warningText;
  final Color danger;
  final Color dangerText;

  /// The three stops of the wallet-pass gradient.
  final Color walletTop;
  final Color walletMid;
  final Color walletBottom;

  /// Text drawn *on* a wallet pass. In both themes the pass stays deep navy, so
  /// these never invert — that is what keeps the 31px roll number at 13.96:1.
  final Color onWallet;
  final Color onWalletMuted;
  final Color onWalletFaint;

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  /// Deep Trust Navy — CRED-style. The shipped default.
  static const dark = EvPalette(
    bg: Color(0xFF0B0F19),
    surface: Color(0xFF111827),
    surfaceSunken: Color(0xFF0E1522),
    surfaceElevated: Color(0xFF0F1624),
    border: Color(0xFF1F2937),
    borderStrong: Color(0xFF263246),
    walletBorder: Color(0xFF28374F),
    textPrimary: Color(0xFFF9FAFB),
    textSecondary: Color(0xFF9CA3AF),
    textTertiary: Color(0xFF8695AB),
    accent: Color(0xFF3B82F6),
    accentBright: Color(0xFF60A5FA),
    accentDeep: Color(0xFF2563EB),
    accentText: Color(0xFF93C5FD),
    success: Color(0xFF10B981),
    successText: Color(0xFF6EE7B7),
    warning: Color(0xFFF59E0B),
    warningText: Color(0xFFFCD34D),
    danger: Color(0xFFEF4444),
    dangerText: Color(0xFFFCA5A5),
    walletTop: Color(0xFF1E2C46),
    walletMid: Color(0xFF172136),
    walletBottom: Color(0xFF121A29),
    onWallet: Color(0xFFF3F6FB),
    onWalletMuted: Color(0xFF9CA3AF),
    onWalletFaint: Color(0xFF7C8DA6),
    brightness: Brightness.dark,
  );

  /// Crisp Alabaster. Every text pair verified >= 4.5:1 on both page and card.
  static const light = EvPalette(
    bg: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1F5F9),
    surfaceElevated: Color(0xFFFBFCFE),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    walletBorder: Color(0xFFC7D8EA),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF5B6B80),
    accent: Color(0xFF3B82F6),
    accentBright: Color(0xFF60A5FA),
    accentDeep: Color(0xFF2563EB),
    accentText: Color(0xFF1D4ED8),
    success: Color(0xFF10B981),
    successText: Color(0xFF047857),
    warning: Color(0xFFF59E0B),
    warningText: Color(0xFFB45309),
    danger: Color(0xFFEF4444),
    dangerText: Color(0xFFB91C1C),
    // The pass is a physical object: it keeps its navy shell in light mode.
    walletTop: Color(0xFF1E2C46),
    walletMid: Color(0xFF172136),
    walletBottom: Color(0xFF121A29),
    onWallet: Color(0xFFF3F6FB),
    onWalletMuted: Color(0xFFB6C2D2),
    onWalletFaint: Color(0xFF8B9CB2),
    brightness: Brightness.light,
  );
}

/// ---------------------------------------------------------------------------
/// Spacing / radius / sizes
/// ---------------------------------------------------------------------------
abstract final class EvSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x7 = 32;
  static const double x8 = 40;

  /// Horizontal page gutter. Never change per-screen.
  static const double gutter = 16;

  /// Gap between major sections.
  static const double section = 20;
}

abstract final class EvRadius {
  static const double pass = 20;
  static const double card = 18;
  static const double inner = 16;
  static const double button = 14;
  static const double tile = 11;
  static const double pill = 999;
  static const double badge = 6;
}

abstract final class EvSize {
  static const double frameWidth = 393;
  static const double frameHeight = 852;

  static const double primaryButton = 52;
  static const double secondaryButton = 44;
  static const double chip = 32;
  static const double statusPill = 22;
  static const double copyPill = 32;

  static const double iconButton = 36;
  static const double navBar = 40;

  static const double tabBar = 58;
  static const double tabBarInset = 16;
  static const double tabBarBottom = 24;

  static const double walletCard = 176;
  static const double walletStack = 268;

  /// Accessibility floor. Anything tappable is wrapped to at least this.
  static const double minTapTarget = 44;
}

abstract final class EvMotion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const toast = Duration(milliseconds: 1600);

  static const curve = Curves.easeOutCubic;
}

/// ---------------------------------------------------------------------------
/// Type scale
/// ---------------------------------------------------------------------------
/// Families are resolved through `google_fonts`, but every file is bundled in
/// `assets/google_fonts/` so `GoogleFonts` never performs a network fetch.
abstract final class EvFont {
  static const ui = 'Plus Jakarta Sans';
  static const mono = 'IBM Plex Mono';

  static const fallbackUi = <String>['Roboto', 'Helvetica', 'Arial'];
  static const fallbackMono = <String>['Roboto Mono', 'Courier New', 'monospace'];
}

/// Semantic text styles. Use these, never a raw TextStyle in a widget.
@immutable
class EvTextStyles {
  const EvTextStyles(this.p);

  final EvPalette p;

  TextStyle get hero => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 26.5,
        height: 1.13,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: p.textPrimary,
      );

  TextStyle get screenTitle => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: p.textPrimary,
      );

  TextStyle get navTitle => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 13.5,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      );

  TextStyle get cardTitle => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 17,
        height: 1.24,
        fontWeight: FontWeight.w700,
        color: p.textPrimary,
      );

  TextStyle get sectionTitle => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 14,
        height: 1.28,
        fontWeight: FontWeight.w700,
        color: p.textPrimary,
      );

  TextStyle get tileTitle => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      );

  TextStyle get body => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 12,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: p.textSecondary,
      );

  TextStyle get bodyMuted => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 11,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: p.textTertiary,
      );

  TextStyle get label => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.textSecondary,
      );

  TextStyle get button => TextStyle(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: Colors.white,
      );

  // -- monospace: identifiers, dates, counters ------------------------------

  TextStyle get rollHero => TextStyle(
        fontFamily: EvFont.mono,
        fontFamilyFallback: EvFont.fallbackMono,
        fontSize: 31,
        height: 1.1,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.6,
        color: p.onWallet,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get rollCard => TextStyle(
        fontFamily: EvFont.mono,
        fontFamilyFallback: EvFont.fallbackMono,
        fontSize: 23,
        height: 1.12,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
        color: p.onWallet,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get fieldValue => TextStyle(
        fontFamily: EvFont.mono,
        fontFamilyFallback: EvFont.fallbackMono,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: p.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Uppercase micro label. Always render with `TextStyle` + uppercase text —
  /// never `textTransform`, which Flutter does not have.
  TextStyle get microLabel => TextStyle(
        fontFamily: EvFont.mono,
        fontFamilyFallback: EvFont.fallbackMono,
        fontSize: 9,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.25,
        color: p.textTertiary,
      );

  TextStyle get monoMeta => TextStyle(
        fontFamily: EvFont.mono,
        fontFamilyFallback: EvFont.fallbackMono,
        fontSize: 10,
        height: 1.3,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.55,
        color: p.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get statusPill => TextStyle(
        fontFamily: EvFont.mono,
        fontFamilyFallback: EvFont.fallbackMono,
        fontSize: 8.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Text that sits on the navy wallet pass.
  TextStyle onWallet(TextStyle base) =>
      base.copyWith(color: p.onWallet, fontFamilyFallback: EvFont.fallbackUi);
}
