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
        showDragHandle: true,
        dragHandleColor: p.borderStrong,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSunken,
        hintStyle: EvTextStyles(p).microLabel.copyWith(
          letterSpacing: 0,
          fontSize: 11,
          color: p.textTertiary.withValues(alpha: 0.75),
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
}
