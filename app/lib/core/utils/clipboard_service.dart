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

  /// The exact text [_pendingSensitiveClear] is allowed to remove.
  ///
  /// The clipboard is shared with every app on the phone. A minute after we
  /// put a password on it, it may hold a message the user copied in WhatsApp —
  /// and that copy is not ours to destroy. The timer therefore blanks the
  /// clipboard only while it still holds this value.
  static String? _pendingSensitiveValue;

  /// Bumped by every [copy]; a wipe only acts for the generation that armed it.
  ///
  /// Guards the window between the wipe reading the clipboard and writing to
  /// it: a copy made in that window supersedes the wipe.
  static int _generation = 0;

  /// Watches the app's lifecycle while a wipe is armed.
  static AppLifecycleListener? _lifecycle;

  /// True while a sensitive value is waiting to be wiped from the clipboard.
  @visibleForTesting
  static bool get hasPendingSensitiveClear =>
      _pendingSensitiveClear?.isActive ?? false;

  /// Cancels any pending wipe and stops watching the lifecycle.
  ///
  /// The service is process-wide, so a timer armed by one test would otherwise
  /// fire inside the next one.
  @visibleForTesting
  static void reset() {
    _pendingSensitiveClear?.cancel();
    _pendingSensitiveClear = null;
    _pendingSensitiveValue = null;
    _generation++;
    _stopWatchingLifecycle();
  }

  static Future<void> copy(
    BuildContext context, {
    required String value,
    required String label,
    bool haptic = true,
    bool sensitive = false,
  }) async {
    // Checked before anything else: the awaits below can outlive the caller's
    // element, and both the toast and ScaffoldMessenger.of would throw on a
    // defunct context. A tap that ends after navigation must stay silent, not
    // crash the app.
    if (!context.mounted) return;

    if (value.trim().isEmpty) {
      _toast(context, 'Nothing to copy', isError: true);
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on Object {
      // A write can be refused (locked device, restricted profile, an OEM
      // clipboard manager). Unguarded, the throw escaped an `async onPressed`:
      // no toast, no haptic, nothing — the silent failure this class exists to
      // prevent. Say it out loud and arm nothing for this value: a wipe for a
      // secret that never landed would blank whatever is on the clipboard now.
      //
      // An older pending wipe is deliberately left alone. Its secret is still
      // on the clipboard — this write is what failed — so it must still be
      // removed on schedule; the read in [_wipeIfStillOurs] keeps it from
      // touching anything else.
      if (context.mounted) {
        _toast(
          context,
          'Could not copy — long-press the field instead',
          isError: true,
        );
      }
      return;
    }

    // The new value owns the clipboard now; a wipe armed for an older secret
    // must not fire against it. This only covers copies made through this
    // class — copies made in other apps are caught by the read in
    // [_wipeIfStillOurs].
    _cancelPendingClear();
    _generation++;
    if (sensitive) {
      _pendingSensitiveValue = value;
      final armedFor = _generation;
      _pendingSensitiveClear = Timer(
        sensitiveClearDelay,
        () => _wipeIfStillOurs(armedFor),
      );
      _watchLifecycle();
    }

    if (haptic) {
      try {
        // Light impact is the iOS-native "value captured" feeling; on Android
        // it maps to a 10 ms tick that is inaudible and does not wake the
        // vibrator.
        await HapticFeedback.lightImpact();
      } on Object {
        // Best effort. The value is already on the clipboard, so reporting
        // "could not copy" here would be a lie — and the toast, not the buzz,
        // is the confirmation the user acts on.
      }
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

  /// True while the app is still in front of the user.
  ///
  /// `null` is the pre-first-event state (and the state under `flutter test`
  /// unless a test drives the lifecycle): treat it as foreground rather than
  /// stranding a secret because we never heard otherwise. `inactive` counts as
  /// foreground too — the notification shade or a system dialog leaves the app
  /// on screen and the timer is cancelled outright on hide/pause, so refusing
  /// to wipe while merely unfocused would silently drop the wipe.
  static bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  static void _watchLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      // A backgrounded app is not allowed to blank the clipboard: Android 10+
      // still permits background *writes*, so a timer left running would fire
      // while the user is pasting into another app.
      onPause: _cancelPendingClear,
      onHide: _cancelPendingClear,
      onDetach: _cancelPendingClear,
    );
  }

  static void _stopWatchingLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  static void _cancelPendingClear() {
    _pendingSensitiveClear?.cancel();
    _pendingSensitiveClear = null;
    _pendingSensitiveValue = null;
    _stopWatchingLifecycle();
  }

  /// Blanks the clipboard, but only if it still holds the secret [armedFor]
  /// put there.
  static Future<void> _wipeIfStillOurs(int armedFor) async {
    final secret = _pendingSensitiveValue;
    _pendingSensitiveClear = null;
    _pendingSensitiveValue = null;
    try {
      if (secret == null || armedFor != _generation) return;
      if (!_isForeground) return;

      String? current;
      try {
        current = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      } on Object {
        // The platform refused the read (locked device, restricted profile).
        // We cannot prove the clipboard still holds our secret, so leave it
        // alone: eating someone else's copy is worse than a secret that lives
        // until the user copies something else.
        return;
      }

      // Only an exact match proves the clipboard still holds the secret this
      // timer armed. `null` means no plain text is exposed — another app may
      // have put an image there, and `Clipboard.setData('')` would replace it,
      // destroying content that is not ours. `Clipboard.hasStrings()` cannot
      // rescue that case: it reports "no text" for an image and for an empty
      // clipboard alike, so a null read stays ambiguous and we do nothing. A
      // platform that refuses to read back its own text is the same answer for
      // the same reason: the user's own paste still works, and every other app
      // is subject to the same refusal.
      if (current != secret) return;

      // A copy made while we were reading supersedes this wipe.
      if (armedFor != _generation || !_isForeground) return;

      try {
        await Clipboard.setData(const ClipboardData(text: ''));
      } on Object {
        // The wipe is spent either way; there is nothing useful to tell the
        // user about a minute after the copy, and no timer left to retry.
      }
    } finally {
      _stopWatchingLifecycle();
    }
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
