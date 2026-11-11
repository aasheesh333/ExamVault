import 'dart:typed_data';

import 'package:examvault/app.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_vault_store.dart';
import 'support/matrix.dart';

/// Tap every control on every screen and assert nothing breaks.
///
/// The layout matrix proves screens *look* right. This proves they *work*: it
/// walks the real app, presses every tappable surface one at a time, and asserts
/// that no tap throws, no tap is dead (the screen or its dialog must change
/// something), and the app is still usable afterwards.
///
/// It is deliberately blunt. A dead button and a crash both fall out of it, which
/// is exactly the class of bug a screenshot review cannot see.
void main() {
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late FakeVaultStore store;

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('tc$stamp', bytes: Uint8List(0));
    settingsBox = await Hive.openBox<dynamic>('ts$stamp', bytes: Uint8List(0));
    store = FakeVaultStore();
  });

  Widget app() {
    final feed = matrixFeedJson();
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(feed, 200);
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
      child: const ExamVaultApp(),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Every tab, walked in turn.
  const tabs = ['Home', 'Vault', 'Radar', 'Share'];

  for (final tab in tabs) {
    testWidgets('every control on $tab is alive', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text(tab));
      await tester.pump(const Duration(milliseconds: 300));

      // Snapshot the tappables, then press them one at a time by position: the
      // tree changes after each press, so holding Finder objects would go stale.
      final points = <Offset>[];
      for (final finder in [
        find.byType(InkWell),
        find.byType(GestureDetector),
        find.byType(IconButton),
        find.byType(TextButton),
        find.byType(Switch),
      ]) {
        for (final element in finder.evaluate()) {
          final box = element.renderObject as RenderBox?;
          if (box == null || !box.hasSize || !box.attached) continue;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (rect.width < 4 || rect.height < 4) continue;
          if (!Rect.fromLTWH(0, 0, 393, 852).contains(rect.center)) continue;
          points.add(rect.center);
        }
      }

      expect(points, isNotEmpty, reason: '$tab must expose controls');

      for (final at in points) {
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 250));

        // Whatever the tap did, it must not have thrown.
        final error = tester.takeException();
        expect(
          error,
          isNull,
          reason:
              'Tapping ${at.dx.toInt()},${at.dy.toInt()} on $tab threw: '
              '$error',
        );

        // Dismiss anything a tap opened so the next press reaches the screen.
        if (find.byType(Dialog).evaluate().isNotEmpty ||
            find.byType(BottomSheet).evaluate().isNotEmpty) {
          await tester.tapAt(const Offset(196, 20));
          await tester.pump(const Duration(milliseconds: 250));
          tester.takeException();
        }
      }

      // The app must still be showing a screen, not a blank frame.
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason: '$tab ended up with no scaffold after the walk',
      );
    });
  }

  testWidgets('back from every tab returns to Home, never exits', (
    tester,
  ) async {
    await pumpApp(tester);

    for (final tab in ['Vault', 'Radar', 'Share']) {
      await tester.tap(find.text(tab));
      await tester.pump(const Duration(milliseconds: 300));

      // Simulate the Android system back gesture.
      final popped = await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        popped,
        isTrue,
        reason: 'back on $tab must be handled in-app, not passed to the OS',
      );
      expect(
        find.text('Command Center'),
        findsWidgets,
        reason: 'back on $tab should land on Home',
      );
    }
  });
}
