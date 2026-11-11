import 'dart:typed_data';

import 'package:examvault/app.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/matrix.dart';

/// Navigation-level regressions found by the codebase audit.
///
/// Both of these are invisible to the state matrix: every frame renders cleanly,
/// nothing overflows, every tap target is 44px — the bugs are in what the app
/// *remembers* between screens.
void main() {
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('nc$stamp', bytes: Uint8List(0));
    settingsBox = await Hive.openBox<dynamic>('ns$stamp', bytes: Uint8List(0));
  });

  /// Mounts the real app; returns the container so providers can be inspected.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    List<dynamic> cards = const [],
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final feed = matrixFeedJson();
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(feed, 200);
      }
      return http.Response('', 404);
    });

    // The ProviderScope lives *in the tree*: unmounting in teardown disposes the
    // container and cancels the 60s feed-poll timer with it (the pattern the
    // tap-walk test already proved). An externally owned container survived
    // unmount and its poll timer tripped the framework's pending-timer check.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          httpCacheBoxProvider.overrideWithValue(cacheBox),
          settingsBoxProvider.overrideWithValue(settingsBox),
          admitCardRepositoryProvider.overrideWith(
            (ref) => AdmitCardRepository(
              store: MatrixVaultStore(cards: cards.cast()),
            ),
          ),
          cdnClientProvider.overrideWithValue(
            CdnClient(
              cache: cacheBox,
              client: mock,
              baseUrl: 'https://cdn.test',
            ),
          ),
        ],
        child: const ExamVaultApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });

    return ProviderScope.containerOf(
      tester.element(find.byType(ExamVaultApp)),
      listen: false,
    );
  }

  testWidgets('tab switch preserves each screen\'s state', (tester) async {
    await pumpApp(tester);

    // Type a roll number on the Radar tab.
    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('roll-field')), '2201098');
    await tester.pump(const Duration(milliseconds: 100));

    // Leave, then come back.
    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 400));

    // The screen must not have been rebuilt from scratch: the typed roll,
    // the scroll offset and every controller belong to the user now.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('roll-field')))
          .controller
          ?.text,
      '2201098',
      reason:
          'switching tabs destroyed the checker\'s state — the cross-fade '
          're-keys its children, unmounting both screens on every switch',
    );
  });

  testWidgets('vault "Check my result" clears a previously tapped radar exam', (
    tester,
  ) async {
    final card = matrixCard(id: 'card_a', roll: '2201098765');
    final container = await pumpApp(tester, cards: [card]);

    // Simulate the user having tapped a radar row for a *different* exam
    // earlier in the session.
    final tapped = LiveUpdate(
      examId: 'exam_other',
      examName: 'Some Other Exam Result',
      category: ExamCategory.upsc,
      status: UpdateStatus.resultOut,
      contextLine: 'test',
      publishedAt: DateTime.now(),
    );
    container.read(resultExamIdProvider.notifier).select(tapped);
    await tester.pump();

    // Open the vault and press the dock's primary action.
    await tester.tap(find.text('Vault'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Check my result'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(resultExamIdProvider),
      isNull,
      reason:
          'the checker prioritises a tapped exam over the chosen card, so '
          'the vault dock must clear it — otherwise this card\'s roll is '
          'searched against the other exam\'s index (a wrong verdict)',
    );
    expect(
      container.read(selectedCardIdProvider),
      'card_a',
      reason: 'the dock must still hand the checker this card',
    );
  });
}
