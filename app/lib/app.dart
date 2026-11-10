import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
      builder: (context, child) =>
          _TextScaleClamp(child: child ?? const SizedBox.shrink()),
      home: const RootShell(),
    );
  }
}

/// Keeps system text scaling inside the range the layout was designed for.
///
/// Below 0.9 the pass hierarchy collapses; above 1.35 the 31px roll number stops
/// fitting on one line. The widget only inserts a `MediaQuery` when the incoming
/// scaler is actually out of range, so the common case costs nothing and cannot
/// re-trigger a build.
class _TextScaleClamp extends StatelessWidget {
  const _TextScaleClamp({required this.child});

  final Widget child;

  static const _min = 0.9;
  static const _max = 1.35;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;

    // `scale(1)` is the scaler's factor at 1 logical px — stable and cheap.
    final factor = scaler.scale(16) / 16;
    if (factor >= _min && factor <= _max) return child;

    final clamped = factor.clamp(_min, _max);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(clamped)),
      child: child,
    );
  }
}

/// Boots the two bundled font families before the first frame so there is no
/// visible flash of a fallback face.
abstract final class FontLoader {
  static Future<void> preload() async {
    // Assets under `assets/google_fonts/` are discovered by google_fonts, so this
    // resolves locally and never performs a network request.
    GoogleFonts.plusJakartaSans();
    GoogleFonts.ibmPlexMono();
  }
}

/// The app is a phone-shaped utility. On tablets and foldables we centre the
/// canvas to 480 px rather than stretching a 393 px design across 900 px of
/// dead space — the pass cards would look absurd at that width.
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

/// Constrains the app to a phone-like canvas on large screens.
class PhoneCanvas extends StatelessWidget {
  const PhoneCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 520) return child;

    return ColoredBox(
      color: const Color(0xFF05070C),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(width: 420, child: child),
        ),
      ),
    );
  }
}
