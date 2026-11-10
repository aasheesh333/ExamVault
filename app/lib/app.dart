import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/root_shell.dart';
import 'providers/app_providers.dart';

class ExamVaultApp extends ConsumerWidget {
  const ExamVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'ExamVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Both palettes ship; the wallet pass stays deep navy either way, because it
      // is a physical object rather than a themed surface.
      themeMode: ref.watch(themePreferenceProvider).mode,
      scrollBehavior: const _EvScrollBehavior(),
      // Clamping is done in a dedicated widget: doing it inline in `builder`
      // allocates a fresh TextScaler on every rebuild, which makes MediaQueryData
      // compare unequal to its ancestor and spins the tree forever.
      builder: (context, child) => _TextScaleClamp(
        child: _SystemChrome(child: child ?? const SizedBox.shrink()),
      ),
      home: const RootShell(),
    );
  }
}

/// Keeps the status- and navigation-bar icons legible in both palettes.
///
/// There is no `AppBar` anywhere in the app (every screen draws its own header), so
/// nothing ever set an overlay style. With the light palette that left the clock
/// and battery white on a near-white background; on Android 15+ the bars are
/// edge-to-edge and cannot fall back to an opaque scrim.
class _SystemChrome extends StatelessWidget {
  const _SystemChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: context.ev.bg,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child,
    );
  }
}

/// Keeps system text scaling inside the range the layout was designed for.
///
/// The ceiling is 2.0 — Android's own maximum — rather than the 1.35 this used to
/// clamp to. Clamping to 1.35 silently discarded a setting the user had raised
/// *because* they could not read the text; the layout now has to cope instead, and
/// the widgets that could not (fixed-height pass rows, single-line exam names) were
/// fixed rather than hidden behind the cap.
class _TextScaleClamp extends StatelessWidget {
  const _TextScaleClamp({required this.child});

  final Widget child;

  static const _min = 0.9;
  static const _max = 2.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;

    // `scale(16)` is stable regardless of the nonlinear curve Android applies.
    final factor = scaler.scale(16) / 16;
    if (factor >= _min && factor <= _max) return child;

    final clamped = factor.clamp(_min, _max);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(clamped)),
      child: child,
    );
  }
}

/// The app is a phone-shaped utility. On tablets and foldables we centre the
/// canvas rather than stretching a 393 px design across 900 px of dead space.
class _EvScrollBehavior extends MaterialScrollBehavior {
  const _EvScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Stretch overscroll reads as "cheap" against a navy canvas; glow is quieter.
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: context.ev.accent,
      child: child,
    );
  }
}
