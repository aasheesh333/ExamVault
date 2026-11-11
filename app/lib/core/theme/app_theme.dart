import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme_tokens.dart';

/// Exposes the ExamVault design tokens to the widget tree.
///
/// `context.ev` gives the palette, `context.type` the type scale, `context.evSpacing`…
/// Keeping them behind an extension means a widget never hardcodes a hex value.
@immutable
class EvTheme extends ThemeExtension<EvTheme> {
  const EvTheme({required this.palette});

  final EvPalette palette;

  EvTextStyles get text => EvTextStyles(palette);

  @override
  EvTheme copyWith({EvPalette? palette}) =>
      EvTheme(palette: palette ?? this.palette);

  @override
  EvTheme lerp(ThemeExtension<EvTheme>? other, double t) {
    if (other is! EvTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension EvThemeX on BuildContext {
  EvPalette get ev => Theme.of(this).extension<EvTheme>()!.palette;
  EvTextStyles get type => Theme.of(this).extension<EvTheme>()!.text;
  bool get isDark => ev.isDark;

  /// A 1px hairline that stays visible on both surface colours.
  Color get hairline => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : const Color(0xFF0F172A).withValues(alpha: 0.07);

  Color get scrim => isDark
      ? Colors.black.withValues(alpha: 0.62)
      : const Color(0xFF0F172A).withValues(alpha: 0.34);
}

abstract final class AppTheme {
  static ThemeData dark() => _build(EvPalette.dark);
  static ThemeData light() => _build(EvPalette.light);

  static ThemeData _build(EvPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: Colors.white,
      primaryContainer: p.accentDeep,
      onPrimaryContainer: Colors.white,
      secondary: p.accentBright,
      onSecondary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceElevated,
      onSurfaceVariant: p.textSecondary,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.bg,
      inversePrimary: p.accentDeep,
    );

    final base = p.isDark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme.apply(
        fontFamily: EvFont.ui,
        fontFamilyFallback: EvFont.fallbackUi,
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: p.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
        titleTextStyle: EvTextStyles(p).navTitle,
        iconTheme: IconThemeData(color: p.textPrimary, size: 20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Off, deliberately: every sheet in this app draws its own rounded
        // surface (transparent `backgroundColor` + an inner Container with its
        // own grabber). The theme-level handle then floated on the dimmed scrim
        // *above* the sheet — a stray pill 48px over a second handle inside.
        showDragHandle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? p.surfaceElevated : const Color(0xFF0F172A),
        contentTextStyle: EvTextStyles(p).label.copyWith(color: Colors.white),
        actionTextColor: p.accentBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EvRadius.button),
          side: BorderSide(color: p.borderStrong),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        elevation: 12,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceSunken,
        circularTrackColor: p.surfaceSunken,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accentBright,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      switchTheme: _switchTheme(p),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSunken,
        hintStyle: EvTextStyles(p).microLabel.copyWith(
          letterSpacing: 0,
          fontSize: 11,
          // The full-alpha token, not `textTertiary.withValues(alpha: 0.75)`:
          // the translucent blend over surfaceSunken measured 3.05:1 in light
          // and 3.91:1 in dark — both under the 4.5:1 AA floor for 11px text.
          // At full alpha the same token measures 4.97:1 / 6.01:1.
          color: p.textTertiary,
        ),
        labelStyle: EvTextStyles(p).label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvRadius.button),
          borderSide: BorderSide(color: p.borderStrong, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvRadius.button),
          borderSide: BorderSide(color: p.borderStrong, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvRadius.button),
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EvRadius.button),
          borderSide: BorderSide(color: p.danger, width: 1.2),
        ),
      ),
      extensions: [EvTheme(palette: p)],
    );
  }

  /// The Share screen's privacy switch is the app's only Switch, and with no
  /// theme it rendered Material's defaults: an OFF track ~1.0:1 against the
  /// white card (functionally invisible) and the primary blue as ON — which
  /// reads as "accent chrome", not as a privacy state.
  ///
  /// Every state now carries a >= 3:1 boundary against the surface it sits on
  /// (WCAG 1.4.11 non-text contrast), measured:
  ///  * ON — light uses `successText` (#047857: 5.48:1 on white, white thumb
  ///    5.48:1). Deliberately *not* `success`: #10B981 is only 2.54:1 on a
  ///    white card. Dark keeps `success` (#10B981: 6.99:1 on #111827).
  ///  * OFF — a `borderStrong` track (a quiet well, 1.4-1.5:1) made visible by
  ///    a `textTertiary` outline (5.44:1 light / 5.83:1 dark against the
  ///    surface, >= 3.6:1 against its own track) and a `textSecondary` thumb
  ///    (7.58:1 / 6.99:1 against the surface).
  ///  * Disabled — exempt from 1.4.11, so both parts simply dim to signal
  ///    "not interactive" (the Share screen disables the switch until a roll
  ///    number exists).
  static SwitchThemeData _switchTheme(EvPalette p) {
    const selected = WidgetState.selected;
    const disabled = WidgetState.disabled;
    final onTrack = p.isDark ? p.success : p.successText;

    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(disabled)) {
          return p.textTertiary.withValues(alpha: 0.5);
        }
        return states.contains(selected) ? Colors.white : p.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(disabled)) {
          return p.borderStrong.withValues(alpha: 0.4);
        }
        return states.contains(selected) ? onTrack : p.borderStrong;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(disabled) || states.contains(selected)) {
          return Colors.transparent;
        }
        return p.textTertiary;
      }),
    );
  }
}
