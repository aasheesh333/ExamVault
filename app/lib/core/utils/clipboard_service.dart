import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/theme_tokens.dart';

/// One-tap copy with the full feedback stack: clipboard, haptic, toast.
///
/// The three are deliberately bundled in a single call so no call site can ship
/// "copy works but nothing tells you it worked" — the exact failure mode that
/// makes users re-tap five times and lose trust in a utility app.
abstract final class ClipboardService {
  static Future<void> copy(
    BuildContext context, {
    required String value,
    required String label,
    bool haptic = true,
  }) async {
    if (value.trim().isEmpty) {
      _toast(context, 'Nothing to copy', isError: true);
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    if (haptic) {
      // Light impact is the iOS-native "value captured" feeling; on Android it
      // maps to a 10 ms tick that is inaudible and does not wake the vibrator.
      await HapticFeedback.lightImpact();
    }
    if (!context.mounted) return;
    _toast(context, '$label copied');
  }

  static void _toast(BuildContext context, String message, {bool isError = false}) {
    final p = context.ev;
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: EvMotion.toast,
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? p.danger : (context.isDark ? p.surfaceElevated : const Color(0xFF0F172A)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvRadius.button),
            side: BorderSide(
              color: isError ? p.danger : p.borderStrong,
            ),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                size: 16,
                color: isError ? Colors.white : p.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: context.type.label.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
