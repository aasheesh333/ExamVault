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

  /// When true, `Clipboard.setData` fails the way a locked device does.
  late bool refuseWrites;

  setUp(() {
    writes = <String?>[];
    clipboardText = null;
    clipboardHoldsNonText = false;
    refuseWrites = false;
    ClipboardService.reset();

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
          if (clipboardHoldsNonText) return null;
          final text = clipboardText;
          if (text == null) return null;
          return <String, Object?>{'text': text};
        case 'Clipboard.hasStrings':
          // The real platform answers "no text" for an image and for an empty
          // clipboard alike — which is why a null read stays ambiguous.
          return <String, Object?>{
            'value': !clipboardHoldsNonText && clipboardText != null,
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

    // The user leaves for WhatsApp and copies a flight number. Android lets
    // our backgrounded timer still *write* the clipboard, so an unconditional
    // wipe would blank what they are about to paste.
    clipboardText = 'AI-302, seat 14C';

    await tester.pump(
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

    await tester.pump(
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

    await tester.pump(
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
      await tester.pump(
        ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(writes, ['portal-password']);
    },
  );

  testWidgets('going to the background cancels the pending wipe', (
    tester,
  ) async {
    await pumpCopyButton(tester);
    expect(ClipboardService.hasPendingSensitiveClear, isTrue);

    sendToBackground(tester);

    expect(
      ClipboardService.hasPendingSensitiveClear,
      isFalse,
      reason: 'a backgrounded app may not blank the clipboard unattended',
    );

    await tester.pump(
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(writes, ['portal-password']);
    expect(clipboardText, 'portal-password');

    returnToForeground(tester);
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
    await tester.pump(
      ClipboardService.sensitiveClearDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(writes, ['portal-password', 'portal-password', '']);
    expect(clipboardText, '');
  });
}
