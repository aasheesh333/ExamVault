import 'dart:typed_data';

import 'package:examvault/app.dart';
import 'package:examvault/core/theme/motion.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/features/result_checker/instant_result_checker_screen.dart';
import 'package:examvault/features/shell/root_shell.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_vault_store.dart';
import 'support/matrix.dart';

/// The reduced-motion contract, end to end.
///
/// WHY: `EvMotion` promises "every duration is zero when the OS asks for
/// reduced motion", but nothing ever tested the promise against the running
/// app. A regression here is invisible to every other suite: the layout matrix
/// pumps through animations, and the tap walk tolerates them. This file pins
/// the observable behaviour instead — with the platform's `disableAnimations`
/// accessibility flag on:
///
///  * `EvMotion.of` resolves to `Duration.zero` inside the live tree,
///  * a tab switch completes in ONE frame and the new tab is immediately
///    interactive (no opacity/IgnorePointer fade to wait out),
///  * both bottom sheets are open — route pushed, content mounted — after ONE
///    frame each, and
///  * when the interactions are done the app is idle: no transient frame
///    callbacks left, i.e. nothing is still animating behind the user's back.
///
/// Note on the framework: Flutter's own `ModalBottomSheetRoute` transition
/// (250 ms in / 200 ms out) does NOT consult `disableAnimations` — only the
/// app's EvMotion-driven animations do. So "one pump" here asserts the sheet
/// is *open* (mounted, content present, route pushed); the test then drains
/// the framework's fixed transition itself before asserting idleness.
void main() {
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late FakeVaultStore store;

  setUp(() async {
    // Same in-memory pattern as tap_walk_test.dart: no file I/O, no cross-test
    // queueing, nothing for the fake clock to starve.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('mc$stamp', bytes: Uint8List(0));
    settingsBox = await Hive.openBox<dynamic>('ms$stamp', bytes: Uint8List(0));
    store = FakeVaultStore();
  });

  Widget app() {
    final feed = matrixFeedJson();
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        // UTF-8 content-type like the real edge (see matrix.dart's pumpMatrix):
        // Response(String) defaults to latin1, which cannot carry Devanagari.
        return http.Response(
          feed,
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
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

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(EvTabBar), matching: find.text(label)),
    );
  }

  /// Pops the topmost route and drains the framework's fixed sheet transition
  /// (see the file header: the framework route does not honour the flag).
  Future<void> popAndDrain(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('reduced motion: every app animation collapses to one frame', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pumpApp(tester);

    // 1. The token layer, measured inside the live tree: MediaQuery must carry
    //    the flag all the way down to EvMotion.
    final shellContext = tester.element(find.byType(RootShell));
    expect(
      EvMotion.of(shellContext, EvMotion.paneIn),
      Duration.zero,
      reason: 'EvMotion must resolve to zero under disableAnimations',
    );
    expect(EvMotion.of(shellContext, EvMotion.overlayIn), Duration.zero);

    // 2. Tab switch: ONE pump, then Radar must already accept taps. Under the
    //    old 220 ms cross-fade this assertion is false — the outgoing tab still
    //    owns the frame — so this pins _TabSwitcher's zero-duration fast path.
    await tapTab(tester, 'Radar');
    await tester.pump(); // exactly one frame; deliberately no duration
    _expectRadarInteractive(tester);

    // 3. About sheet, opened from Home's top bar: ONE pump after the tap and
    //    the route must be up with its content mounted — no app-level staging
    //    in front of a reduce-motion user.
    await tapTab(tester, 'Home');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pump(); // one frame
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('About ExamVault'), findsOneWidget);
    await popAndDrain(tester);

    // 4. Vault form sheet, same one-pump contract. ('EXAM NAME' is the first
    //    field's label — _Field renders labels uppercased.)
    await tester.tap(find.text('Add'));
    await tester.pump(); // one frame
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('EXAM NAME'), findsOneWidget);
    await popAndDrain(tester);

    // 5. Idle: nothing may still be animating. A leaked ticker (an animation
    //    that ignored the flag, an undisposed controller) shows up here as a
    //    pending transient frame callback. The extra drain covers the ink
    //    splashes the taps started — those are framework-fixed durations too.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    SchedulerBinding.instance.debugAssertNoTransientCallbacks(
      'reduced-motion app must be idle after tab switches and both sheets',
    );
  });
}

/// The Radar tab is on stage and accepting taps: a hit test at the centre of
/// its roll-number field must land inside the checker screen's render subtree.
///
/// Offstage and IgnorePointer wrappers (what the cross-fade uses to hide and
/// disarm a tab) both remove render objects from the hit path, so this single
/// mechanical check proves "visible AND interactive" — the same walk-up-from-
/// the-hit direction as the matrix's fixed coverage check.
void _expectRadarInteractive(WidgetTester tester) {
  final radar = find.byType(InstantResultCheckerScreen);
  expect(radar, findsOneWidget);

  final field = find.descendant(of: radar, matching: find.byType(TextField));
  expect(field, findsWidgets, reason: 'Radar must expose its roll field');

  final result = HitTestResult();
  tester.binding.hitTestInView(
    result,
    tester.getCenter(field.first),
    tester.view.viewId,
  );

  final screenObject = tester.renderObject<RenderBox>(radar);
  final reached = result.path.any((entry) {
    final t = entry.target;
    if (identical(t, screenObject)) return true;
    if (t is! RenderObject) return false;
    for (RenderObject? n = t.parent; n != null; n = n.parent) {
      if (identical(n, screenObject)) return true;
    }
    return false;
  });
  expect(
    reached,
    isTrue,
    reason:
        'the Radar tab must accept taps after a single reduced-motion pump '
        '(the cross-fade must not still be running or ignoring pointers)',
  );
}
