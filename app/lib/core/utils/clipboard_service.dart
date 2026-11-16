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

  /// The armed timer for the last sensitive copy, if one is running.
  ///
  /// Null while the wipe is suspended in the background — see
  /// [_suspendSensitiveClear].
  static Timer? _pendingSensitiveClear;

  /// The exact text [_pendingSensitiveClear] is allowed to remove.
  ///
  /// The clipboard is shared with every app on the phone. A minute after we
  /// put a password on it, it may hold a message the user copied in WhatsApp —
  /// and that copy is not ours to destroy. The timer therefore blanks the
  /// clipboard only while it still holds this value.
  static String? _pendingSensitiveValue;

  /// When the wipe owed for [_pendingSensitiveValue] is due.
  ///
  /// Measured from the original copy, never from a resume: backgrounding the
  /// app for five minutes must not buy the secret five more minutes on the
  /// clipboard. Kept across a pause because the wipe is suspended there, not
  /// abandoned.
  static DateTime? _wipeDueAt;

  /// The clock the deadline is measured against.
  ///
  /// A seam only because `tester.pump` advances timers without advancing
  /// `DateTime.now()`; production never replaces it.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Bumped by every [copy]; a wipe only acts for the generation that armed it.
  ///
  /// Guards the window between the wipe reading the clipboard and writing to
  /// it: a copy made in that window supersedes the wipe.
  static int _generation = 0;

  /// Watches the app's lifecycle while a wipe is armed or owed.
  static AppLifecycleListener? _lifecycle;

  /// True while a sensitive value is still owed a wipe.
  ///
  /// Also true while the wipe is suspended in the background: the secret has
  /// not been forgotten, it just cannot be cleared until the app is in front of
  /// the user again.
  @visibleForTesting
  static bool get hasPendingSensitiveClear => _pendingSensitiveValue != null;

  /// True while the wipe is actually armed to fire on its own.
  ///
  /// False in the background, where the timer is suspended so it cannot blank
  /// the clipboard while the user is pasting into another app.
  @visibleForTesting
  static bool get isSensitiveClearArmed =>
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
    _wipeDueAt = null;
    _generation++;
    now = DateTime.now;
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
      final dueAt = now().add(sensitiveClearDelay);
      _wipeDueAt = dueAt;
      _armSensitiveClear(dueAt);
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
  /// on screen, while the wipe is suspended outright on hide/pause. This is the
  /// fire-time backstop in case a resume event never arrives.
  static bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  static void _watchLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      // A backgrounded app is not allowed to blank the clipboard: Android 10+
      // still permits background *writes*, so a timer left armed would fire
      // while the user is pasting into another app. Suspending keeps the secret
      // and its deadline; resuming re-arms the wipe.
      onPause: _suspendSensitiveClear,
      onHide: _suspendSensitiveClear,
      onDetach: _suspendSensitiveClear,
      onShow: _resumeSensitiveClear,
      onResume: _resumeSensitiveClear,
    );
  }

  static void _stopWatchingLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Disarms the timer without forgetting the wipe.
  ///
  /// The secret and [_wipeDueAt] survive, so a resume can re-arm the wipe at its
  /// original deadline. Cancelling rather than letting the timer fire is the
  /// point: a backgrounded app may write the clipboard on Android 10+, and the
  /// user must never have it blanked while they are pasting elsewhere.
  static void _suspendSensitiveClear() {
    if (_pendingSensitiveValue == null) return;
    _pendingSensitiveClear?.cancel();
    _pendingSensitiveClear = null;
  }

  /// Re-arms a wipe that a pause suspended, at its original deadline.
  ///
  /// A deadline that already passed fires immediately (clamped to zero), which
  /// is what makes "copy, switch to the browser, paste, come back" end with the
  /// secret cleared instead of living on the clipboard forever.
  static void _resumeSensitiveClear() {
    final dueAt = _wipeDueAt;
    if (_pendingSensitiveValue == null || dueAt == null) return;
    if (_pendingSensitiveClear?.isActive ?? false) return;
    _armSensitiveClear(dueAt);
  }

  /// Arms (or re-arms) the timer that runs the wipe at [dueAt].
  static void _armSensitiveClear(DateTime dueAt) {
    final remaining = dueAt.difference(now());
    final armedFor = _generation;
    _pendingSensitiveClear = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _wipeIfStillOurs(armedFor),
    );
    _watchLifecycle();
  }

  static void _cancelPendingClear() {
    _pendingSensitiveClear?.cancel();
    _pendingSensitiveClear = null;
    _pendingSensitiveValue = null;
    _wipeDueAt = null;
    _stopWatchingLifecycle();
  }

  /// Blanks the clipboard, but only if it still holds the secret [armedFor]
  /// put there.
  static Future<void> _wipeIfStillOurs(int armedFor) async {
    final secret = _pendingSensitiveValue;
    if (secret == null || armedFor != _generation) return;
    if (!_isForeground) {
      // The timer should never have been armed here — the pause suspends it —
      // but if a resume event never arrives, this is the backstop: never write
      // from the background, and keep the wipe owed for a later resume.
      _suspendSensitiveClear();
      return;
    }
    _pendingSensitiveClear = null;
    _pendingSensitiveValue = null;
    _wipeDueAt = null;
    try {
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
      // Ownership-aware teardown: a sensitive copy that landed while this wipe
      // was awaiting the read owns a fresh timer and listener, and disposing
      // them from here would leave that wipe unable to suspend or re-arm.
      if (_pendingSensitiveValue == null && _pendingSensitiveClear == null) {
        _stopWatchingLifecycle();
      }
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
