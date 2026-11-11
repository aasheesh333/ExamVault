import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/theme_tokens.dart';

/// One-tap copy with the full feedback stack: clipboard, haptic, toast.
///
/// The three are deliberately bundled in a single call so no call site can ship
/// "copy works but nothing tells you it worked" — the exact failure mode that
/// makes users re-tap five times and lose trust in a utility app.
abstract final class ClipboardService {
  /// How long a [copy] marked `sensitive` may sit on the system clipboard.
  @visibleForTesting
  static const sensitiveClearDelay = Duration(seconds: 60);

  /// The pending wipe for the last sensitive copy, if one is scheduled.
  static Timer? _pendingSensitiveClear;

  /// True while a sensitive value is waiting to be wiped from the clipboard.
  @visibleForTesting
  static bool get hasPendingSensitiveClear =>
      _pendingSensitiveClear?.isActive ?? false;

  static Future<void> copy(
    BuildContext context, {
    required String value,
    required String label,
    bool haptic = true,
    bool sensitive = false,
  }) async {
    if (value.trim().isEmpty) {
      _toast(context, 'Nothing to copy', isError: true);
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));

    // A copied DOB or portal password otherwise stays readable by every other
    // app on the phone indefinitely — wipe it after a minute. Any newer copy
    // takes ownership of the clipboard, so it cancels the pending wipe: the
    // timer must never clear what the user *just* copied.
    _pendingSensitiveClear?.cancel();
    _pendingSensitiveClear = sensitive
        ? Timer(sensitiveClearDelay, () {
            _pendingSensitiveClear = null;
            Clipboard.setData(const ClipboardData(text: ''));
          })
        : null;

    if (haptic) {
      // Light impact is the iOS-native "value captured" feeling; on Android it
      // maps to a 10 ms tick that is inaudible and does not wake the vibrator.
      await HapticFeedback.lightImpact();
    }
    if (!context.mounted) return;
    // The sensitive toast must promise the wipe: a secret copied "for a
    // second" that silently stays on the clipboard forever is worse than one
    // the user was told about and can paste quickly.
    _toast(
      context,
      sensitive
          ? 'Copied — clears from clipboard in a minute'
          : '$label copied',
    );
  }

  static void _toast(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final p = context.ev;
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: EvMotion.toast,
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? p.danger
              : (context.isDark ? p.surfaceElevated : const Color(0xFF0F172A)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvRadius.button),
            side: BorderSide(color: isError ? p.danger : p.borderStrong),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
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
