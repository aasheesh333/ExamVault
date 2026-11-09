import 'dart:convert';
import 'dart:io';

import 'package:examvault/app.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Empty-state contract.
///
/// Every one of these assertions failed before the fix: the app seeded three
/// fabricated admit cards, invented four radar rows, and defaulted the result
/// checker to the SSC CGL index. A production exam utility must show *nothing*
/// when it knows *nothing*.
void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_empty_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('c$stamp');
    settingsBox = await Hive.openBox<dynamic>('s$stamp');
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// Everything 404s — the worst realistic case (fresh install, result not out).
  Widget appWithNothing() {
    final mock = MockClient((_) async => http.Response('Not published', 404));
    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        cdnClientProvider.overrideWithValue(
          CdnClient(cache: cacheBox, client: mock, baseUrl: 'https://cdn.test'),
        ),
      ],
      child: const ExamVaultApp(),
    );
  }

  Widget appWithEmptyFeed() {
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
      return http.Response('none', 404);
    });
    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        cdnClientProvider.overrideWithValue(
          CdnClient(cache: cacheBox, client: mock, baseUrl: 'https://cdn.test'),
        ),
      ],
      child: const ExamVaultApp(),
    );
  }

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('fresh install shows no fabricated content', () {
    testWidgets('Command Center has zero saved cards', (tester) async {
      await pumpPhone(tester, appWithNothing());

      expect(find.text('Command Center'), findsOneWidget);

      // No seeded sample cards.
      expect(find.textContaining('SSC CGL Tier-1 2026'), findsNothing);
      expect(find.textContaining('RRB NTPC 2026'), findsNothing);
      expect(find.textContaining('IBPS PO Prelims 2026'), findsNothing);

      // And the count is honest.
      expect(find.textContaining('0 exams tracked'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Command Center offers a way to add the first card', (
      tester,
    ) async {
      await pumpPhone(tester, appWithNothing());

      expect(find.text('Add your first admit card'), findsOneWidget);
      expect(find.text('Add admit card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty radar says so instead of inventing four updates', (
      tester,
    ) async {
      await pumpPhone(tester, appWithEmptyFeed());

      expect(find.textContaining('Nothing live yet'), findsOneWidget);
      expect(find.textContaining('0 live updates'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('vault tab shows an explicit empty state', (tester) async {
      await pumpPhone(tester, appWithNothing());

      await tester.tap(find.text('Vault'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Your vault is empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('result checker refuses to guess which exam', (tester) async {
      await pumpPhone(tester, appWithNothing());

      await tester.tap(find.text('Radar'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Which result?'), findsOneWidget);
      expect(
        find.textContaining('Add an admit card first'),
        findsOneWidget,
        reason: 'the CTA must explain why it cannot run',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('share tab explains that there is nothing to share yet', (
      tester,
    ) async {
      await pumpPhone(tester, appWithNothing());

      await tester.tap(find.text('Share'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Nothing to share yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
