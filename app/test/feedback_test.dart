import 'dart:convert';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/core/utils/clipboard_service.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/features/about/about_sheet.dart';
import 'package:examvault/features/vault/admit_card_detail_screen.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_vault_store.dart';

/// Feedback regressions: every tap that changes something outside the app
/// (the system clipboard, another app via a link) must *prove* it happened.
///
/// The vault is opened at 7:40 AM outside an exam centre — a copy that gives
/// no confirmation gets re-tapped five times, and a link that opens nothing
/// looks broken. Secrets get the extra posture: they may not linger on the
/// shared system clipboard.
void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late FakeVaultStore store;

  /// Everything sent over SystemChannels.platform: Clipboard.setData,
  /// HapticFeedback.* and friends, in call order.
  final platformCalls = <MethodCall>[];

  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_feedback');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('fb_cache_$stamp');
    settingsBox = await Hive.openBox<dynamic>('fb_settings_$stamp');
    store = FakeVaultStore();
    platformCalls.clear();

    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // Capture clipboard writes; answer every platform call benignly (this
    // channel also carries the haptics and overlay-style calls).
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });

    // Force every launch to fail. Without a mock the channel *never
    // completes* under flutter test — the same trap as flutter_secure_storage
    // (see test/support/fake_vault_store.dart).
    messenger.setMockMethodCallHandler(
      urlLauncherChannel,
      (call) async => false,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(urlLauncherChannel, null);
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// The text of every `Clipboard.setData` so far, in order.
  List<String?> clipboardWrites() => platformCalls
      .where((c) => c.method == 'Clipboard.setData')
      .map((c) => (c.arguments as Map)['text'] as String?)
      .toList();

  AdmitCard card({String id = 'chsl', String rollNumber = '2201098765'}) {
    final now = DateTime.now();
    return AdmitCard(
      id: id,
      examId: 'ssc_chsl_tier1_2026',
      category: ExamCategory.ssc,
      examName: 'SSC CHSL Tier-1 2026',
      conductingBody: 'Staff Selection Commission',
      examCode: 'CHSL · TIER-1',
      rollNumber: rollNumber,
      registrationId: 'SSC-CHSL-26-441122',
      dobOrPortalPassword: '11/05/1998',
      centerCode: 'DL-07-2210',
      centerAddress: 'Sector 9, Rohini, New Delhi',
      gate: 'Gate 2',
      reportBy: '08:00 AM',
      examDate: now.add(const Duration(days: 9)),
      shift: '10:00 AM – 11:00 AM',
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget harness(Widget home) {
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(
          jsonEncode({
            'generated_at': DateTime.now().toUtc().toIso8601String(),
            'revision': 1,
            'updates': <dynamic>[],
          }),
          200,
        );
      }
      return http.Response('', 404);
    });

    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: store),
        ),
        cdnClientProvider.overrideWithValue(
          CdnClient(cache: cacheBox, client: mock, baseUrl: 'https://cdn.test'),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );
  }

  Future<void> seed(AdmitCard value) async {
    await store.writeRaw(value.id, AdmitCardCodec.encode(value));
    final ids = await store.readIndex();
    if (!ids.contains(value.id)) {
      await store.writeIndex([...ids, value.id]);
    }
  }

  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('vault pass copy feedback', () {
    testWidgets('the roll row copies the roll and confirms on screen', (
      tester,
    ) async {
      phoneViewport(tester);
      await seed(card());
      await tester.pumpWidget(harness(const AdmitCardDetailScreen()));
      await tester.pumpAndSettle();

      // Disposed inline: a SemanticsHandle left open at teardown fails the
      // binding's end-of-test verifications (see vault_test).
      final semantics = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Copy Roll number'));
      await tester.pumpAndSettle();
      semantics.dispose();

      // What landed on the system clipboard is exactly the roll — the whole
      // reason the row exists.
      expect(clipboardWrites(), ['2201098765']);

      // And the confirmation is real: on screen, inside the viewport, and
      // hit-testable (a toast under the dock or under a modal is the same as
      // no toast at all).
      final snack = find.text('Roll number copied');
      expect(snack, findsOneWidget);
      expect(snack.hitTestable(), findsOneWidget);
      final rect = tester.getRect(snack);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(852));
    });

    testWidgets('the DOB field wipes itself off the clipboard after a minute', (
      tester,
    ) async {
      phoneViewport(tester);
      await seed(card());
      await tester.pumpWidget(harness(const AdmitCardDetailScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DOB / PASSWORD'));
      await tester.pumpAndSettle();

      expect(clipboardWrites(), ['11/05/1998']);
      expect(
        find.text('Copied — clears from clipboard in a minute'),
        findsOneWidget,
      );
      // The sensitive clear is armed…
      expect(ClipboardService.hasPendingSensitiveClear, isTrue);

      // …and only it fires: after a minute the shared clipboard holds an
      // empty string again, not the DOB waiting for the next app to read it.
      await tester.pump(const Duration(seconds: 61));
      expect(clipboardWrites(), ['11/05/1998', '']);
      expect(ClipboardService.hasPendingSensitiveClear, isFalse);
      await tester.pumpAndSettle();
    });
  });

  group('about sheet link failure', () {
    testWidgets('a dead commission link reports on top of the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const _AboutHost()));
      await tester.pump();
      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('IBPS'),
        300,
        scrollable: find.byType(Scrollable).last,
      );

      // The row must tell TalkBack it is a link — the bare InkWell exposed
      // no trait at all, so screen-reader users could not tell it was a
      // control, let alone where it leads.
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final node = tester.getSemantics(find.text('IBPS'));
      expect(node.flagsCollection.isLink, isTrue);
      expect(node.label, 'IBPS');
      semantics.dispose();

      await tester.tap(find.text('IBPS'));
      await tester.pumpAndSettle();

      final snack = find.textContaining('Could not open the link');
      expect(snack, findsOneWidget);

      // The failure feedback must land ON the sheet: through the root
      // messenger it painted behind the modal barrier and the 90%-tall
      // sheet, so the row looked dead. On the sheet's own surface it is
      // inside the sheet's viewport and hit-testable.
      expect(snack.hitTestable(), findsOneWidget);
      final snackRect = tester.getRect(snack);
      final sheetRect = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(
        snackRect.top,
        greaterThanOrEqualTo(sheetRect.top),
        reason: 'the toast belongs to the sheet, not the page behind it',
      );
      expect(snackRect.top, lessThan(sheetRect.bottom));
      expect(snackRect.bottom, lessThanOrEqualTo(sheetRect.bottom + 0.5));
    });
  });
}

class _AboutHost extends StatelessWidget {
  const _AboutHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showAboutSheet(context),
          child: const Text('open about'),
        ),
      ),
    );
  }
}
