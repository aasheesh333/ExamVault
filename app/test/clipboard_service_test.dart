import 'dart:async';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/core/utils/clipboard_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The clipboard is shared with every app on the phone, so the sensitive wipe
/// may only remove the value it put there — and a copy that failed must never
/// look like it worked.
///
/// Both defects this file pins down were user-visible: a password copied here
/// blanked a message the user had just copied in WhatsApp a minute later, and
/// a refused clipboard write vanished into an `async onPressed` with no toast,
/// no haptic and no hint that the field was still un-copied.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Every `Clipboard.setData` text so far, in order.
  late List<String?> writes;

  /// What the platform clipboard currently holds (null = no text).
  late String? clipboardText;

  /// True when the clipboard holds something that is not plain text — a photo
  /// the user copied from the gallery, say. `getData(kTextPlain)` answers
  /// `null` for it, exactly as it does for an empty clipboard.
  late bool clipboardHoldsNonText;

  /// How many `Clipboard.getData` calls have been made.
  ///
  /// Lets a test prove a wipe actually consulted the clipboard, rather than
  /// passing because no wipe ran at all.
  late int reads;

  /// When true, `Clipboard.setData` fails the way a locked device does.
  late bool refuseWrites;

  /// Blocks `Clipboard.getData` until completed, when set.
  ///
  /// Holds a wipe inside its read so a second copy can land mid-flight — the
  /// window where a wipe must not tear down the newer copy's lifecycle
  /// listener.
  Completer<void>? readGate;

  /// The clock the service measures its wipe deadline against.
  ///
  /// `tester.pump` advances timers without advancing `DateTime.now()`, so the
  /// service's clock is overridden to this one and [advance] moves both
  /// together — otherwise a "re-arm at the original deadline" assertion would
  /// pass no matter which deadline the implementation used.
  late DateTime fakeNow;

  setUp(() {
    writes = <String?>[];
    reads = 0;
    clipboardText = null;
    clipboardHoldsNonText = false;
    refuseWrites = false;
    readGate = null;
    ClipboardService.reset();
    fakeNow = DateTime(2026, 11, 16, 9);
    ClipboardService.now = () => fakeNow;

    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final text = (call.arguments as Map)['text'] as String?;
          writes.add(text);
          if (refuseWrites) {
            throw PlatformException(
              code: 'clipboard_unavailable',
              message: 'clipboard is not available',
            );
          }
          clipboardText = text;
          clipboardHoldsNonText = false;
          return null;
        case 'Clipboard.getData':
          reads++;
          final gate = readGate;
          if (gate != null) await gate.future;
          if (clipboardHoldsNonText) return null;
          final text = clipboardText;
          if (text == null) return null;
          return <String, Object?>{'text': text};
        case 'Clipboard.hasStrings':
          // A real platform reports whether the clipboard holds *text*: false
          // for an image, and false for an empty clip too. Production does not
          // call this yet; the fixture must not teach a future caller wrong.
          return <String, Object?>{
            'value':
                !clipboardHoldsNonText && (clipboardText?.isNotEmpty ?? false),
          };
        default:
          // HapticFeedback.* and friends: benign no-ops.
          return null;
      }
    });
  });

  /// Pumps a screen with one button that copies [value] the way the vault does.
  Future<void> pumpCopyButton(
    WidgetTester tester, {
    String value = 'portal-password',
    bool sensitive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => ClipboardService.copy(
                  context,
                  value: value,
                  label: 'Roll number',
                  sensitive: sensitive,
                ),
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('copy'));
    await tester.pumpAndSettle();
  }

  /// Walks the real transition chain; [AppLifecycleListener] asserts on jumps.
  void sendToBackground(WidgetTester tester) {
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void returnToForeground(WidgetTester tester) {
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  /// Advances both the fake timer clock and the service's clock by [duration].
  Future<void> advance(WidgetTester tester, Duration duration) async {
    fakeNow = fakeNow.add(duration);
    await tester.pump(duration);
  }

  /// Walks the binding back to `resumed` from wherever a test left it.
  ///
  /// [AppLifecycleListener] asserts on jumps, so this steps one state at a
  /// time instead of assigning `resumed` directly.
  void restoreForeground() {
    final binding = WidgetsBinding.instance;
    var steps = 0;
    while (binding.lifecycleState != AppLifecycleState.resumed && steps++ < 4) {
      switch (binding.lifecycleState) {
        case AppLifecycleState.paused:
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        case AppLifecycleState.hidden:
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        case AppLifecycleState.inactive:
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        case AppLifecycleState.resumed:
        case AppLifecycleState.detached:
        case null:
          return;
      }
    }
  }

  tearDown(() {
    ClipboardService.reset();
    // A test that leaves the binding paused would make every later wipe in
    // this file look cancelled for the wrong reason.
    restoreForeground();
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a copy made in another app survives our wipe', (tester) async {
    await pumpCopyButton(tester);
    expect(writes, ['portal-password']);
    expect(ClipboardService.hasPendingSensitiveClear, isTrue);

    // Another app replaces the clipboard. The wipe fires on schedule but the
    // read-back no longer matches, so it leaves the new value alone. (The
    // background path is covered by the lifecycle tests below.)
    clipboardText = 'AI-302, seat 14C';

    await advance(
      tester,
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(writes, [
      'portal-password',
    ], reason: 'the wipe must not clear a value this timer does not own');
    expect(clipboardText, 'AI-302, seat 14C');
    expect(ClipboardService.hasPendingSensitiveClear, isFalse);
  });

  testWidgets('our own secret is wiped when the timer fires', (tester) async {
    await pumpCopyButton(tester);
    expect(writes, ['portal-password']);
    expect(ClipboardService.hasPendingSensitiveClear, isTrue);

    await advance(
      tester,
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(writes, ['portal-password', '']);
    expect(clipboardText, '');
    expect(ClipboardService.hasPendingSensitiveClear, isFalse);
  });

  testWidgets('a non-text clipboard is left alone', (tester) async {
    await pumpCopyButton(tester);
    expect(writes, ['portal-password']);

    // The user copied a photo from the gallery. `getData(kTextPlain)` answers
    // null for it, so the wipe cannot prove the clipboard still holds our
    // secret — and `setData('')` would replace the photo with empty text,
    // destroying content that is not ours.
    clipboardHoldsNonText = true;

    await advance(
      tester,
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(writes, [
      'portal-password',
    ], reason: 'a null read cannot prove ownership, so nothing may be written');
    expect(ClipboardService.hasPendingSensitiveClear, isFalse);
  });

  testWidgets(
    'a refused clipboard write reports the failure and arms nothing',
    (tester) async {
      refuseWrites = true;

      await pumpCopyButton(tester);

      expect(
        find.text('Could not copy — long-press the field instead'),
        findsOneWidget,
      );
      expect(
        find.text('Copied — clears from clipboard in a minute'),
        findsNothing,
        reason: 'a failed copy must not claim success',
      );
      expect(ClipboardService.hasPendingSensitiveClear, isFalse);

      // Nothing was armed, so the timer cannot fire later and blank whatever
      // the user copies in the meantime.
      await advance(
        tester,
        ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(writes, ['portal-password']);
    },
  );

  testWidgets('backgrounding suspends the wipe and resuming runs it', (
    tester,
  ) async {
    await pumpCopyButton(tester);
    expect(writes, ['portal-password']);
    expect(ClipboardService.hasPendingSensitiveClear, isTrue);

    sendToBackground(tester);

    expect(
      ClipboardService.isSensitiveClearArmed,
      isFalse,
      reason: 'a backgrounded app may not blank the clipboard unattended',
    );
    expect(
      ClipboardService.hasPendingSensitiveClear,
      isTrue,
      reason: 'the wipe is suspended, not abandoned',
    );

    // Past the deadline while still backgrounded: still nothing written.
    await advance(
      tester,
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 5),
    );
    await tester.pumpAndSettle();
    expect(writes, ['portal-password']);
    expect(clipboardText, 'portal-password');

    // Back in front of the user, the owed wipe runs at once — the toast
    // promised the secret would not stay on the clipboard, and it does not.
    returnToForeground(tester);
    await tester.pumpAndSettle();
    expect(writes, ['portal-password', '']);
    expect(clipboardText, '');
    expect(ClipboardService.hasPendingSensitiveClear, isFalse);
  });

  testWidgets('resuming re-arms at the original deadline', (tester) async {
    await pumpCopyButton(tester);

    sendToBackground(tester);
    await advance(tester, const Duration(seconds: 20));
    returnToForeground(tester);

    // 40 s are left of the original minute, not a fresh 60 s from the resume:
    // backgrounding must not extend a secret's life.
    await advance(tester, const Duration(seconds: 39));
    await tester.pumpAndSettle();
    expect(writes, [
      'portal-password',
    ], reason: 'the deadline is measured from the copy, not from the resume');

    await advance(tester, const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(writes, ['portal-password', '']);
    expect(clipboardText, '');
  });

  testWidgets('a foreign copy made while backgrounded survives the resume', (
    tester,
  ) async {
    await pumpCopyButton(tester);

    sendToBackground(tester);
    await advance(tester, const Duration(seconds: 10));

    // Another app owns the clipboard by the time the user comes back.
    clipboardText = 'AI-302, seat 14C';

    returnToForeground(tester);
    await advance(tester, ClipboardService.sensitiveClearDelay);
    await tester.pumpAndSettle();

    expect(
      reads,
      1,
      reason: 'the re-armed wipe must actually consult the clipboard',
    );
    expect(writes, [
      'portal-password',
    ], reason: 'the read-back guard still holds after a re-arm');
    expect(clipboardText, 'AI-302, seat 14C');
    expect(ClipboardService.hasPendingSensitiveClear, isFalse);
  });

  testWidgets('a copy landing mid-wipe keeps its own lifecycle listener', (
    tester,
  ) async {
    // Hold the first wipe inside `getData` so a second copy can land mid-flight.
    readGate = Completer<void>();
    await pumpCopyButton(tester);
    await advance(
      tester,
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    expect(reads, 1, reason: 'the first wipe is now awaiting the read');

    // The new copy owns a fresh timer and listener; the older wipe finishing
    // must not dispose them.
    await pumpCopyButton(tester, value: 'second-secret');
    readGate!.complete();
    await tester.pumpAndSettle();
    readGate = null;

    expect(
      ClipboardService.hasPendingSensitiveClear,
      isTrue,
      reason: 'the second secret is still owed its wipe',
    );

    // Had the old wipe torn down the new copy's listener, nothing would
    // suspend the second timer and it could fire while backgrounded.
    sendToBackground(tester);
    expect(
      ClipboardService.isSensitiveClearArmed,
      isFalse,
      reason: 'the new copy must still be suspendable',
    );
    expect(writes, [
      'portal-password',
      'second-secret',
    ], reason: 'the older wipe must not blank the newer copy');
  });

  testWidgets('a failed copy does not disarm the previous secret\'s wipe', (
    tester,
  ) async {
    await pumpCopyButton(tester);
    expect(ClipboardService.hasPendingSensitiveClear, isTrue);

    // A second copy is refused. The first secret is still on the clipboard —
    // the second write never landed — so its wipe must still be armed.
    refuseWrites = true;
    await pumpCopyButton(tester);
    expect(
      find.text('Could not copy — long-press the field instead'),
      findsOneWidget,
    );
    expect(ClipboardService.hasPendingSensitiveClear, isTrue);

    refuseWrites = false;
    await advance(
      tester,
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(writes, ['portal-password', 'portal-password', '']);
    expect(clipboardText, '');
  });
}
