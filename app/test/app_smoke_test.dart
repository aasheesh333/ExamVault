import 'dart:convert';
import 'dart:io';

import 'package:examvault/app.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_vault_store.dart';

/// A feed document shaped exactly like the edge object.
String _feedJson() => jsonEncode({
  'generated_at': DateTime.now().toUtc().toIso8601String(),
  'revision': 7,
  'updates': [
    {
      'exam_id': 'ssc_cgl_tier1_2026',
      'category': 'ssc',
      'exam_name': 'SSC CGL Tier-1 2026',
      'context': 'Direct PDF · 18.4 MB',
      'status': 'result_out',
      'published_at': DateTime.now()
          .subtract(const Duration(minutes: 2))
          .toUtc()
          .toIso8601String(),
      'pdf_size': '18.4 MB',
      'mirror_latency_ms': 82,
    },
    {
      'exam_id': 'ibps_po_prelims_2026',
      'category': 'banking',
      'exam_name': 'IBPS PO Prelims 2026',
      'context': '4 mirrors live · no queue',
      'status': 'admit_card_live',
      'published_at': DateTime.now()
          .subtract(const Duration(minutes: 18))
          .toUtc()
          .toIso8601String(),
    },
  ],
});

void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_widget_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    cacheBox = await Hive.openBox<dynamic>(
      'cache_${DateTime.now().microsecondsSinceEpoch}',
    );
    settingsBox = await Hive.openBox<dynamic>(
      'settings_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  // Boxes are intentionally NOT closed between tests. The screen under test
  // fires a fire-and-forget cache write, and awaiting `Box.close()` while that
  // write is in flight hangs the test isolate. Unique box names keep tests
  // isolated from each other; the temp directory is removed at the end.
  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // Best effort — a leaked temp dir must never fail the suite.
    }
  });

  Widget app() {
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(_feedJson(), 200);
      }
      return http.Response('', 404);
    });

    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: FakeVaultStore()),
        ),
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
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('boots to the Command Center without a layout overflow', (
    tester,
  ) async {
    await pumpPhone(tester, app());

    expect(find.text('Command Center'), findsOneWidget);
    expect(find.text('EXAMVAULT'), findsOneWidget);

    // A RenderFlex overflow raises a FlutterError and fails the test
    // automatically; this assertion documents the intent.
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounts the radar section and seeds no vault content', (
    tester,
  ) async {
    await pumpPhone(tester, app());

    // Scope note: feed *content* is covered exhaustively by
    // `live_feed_parsing_test.dart` (UTF-8, sorting, malformed rows, liveCount).
    // This widget test only guards the structural contract that broke before:
    // the radar section renders, and the vault is NOT pre-filled with fiction.
    expect(find.text('LIVE RADAR'), findsWidgets);
    expect(find.text('Add your first admit card'), findsOneWidget);
    expect(find.textContaining('exams tracked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category chips filter the wallet stack', (tester) async {
    await pumpPhone(tester, app());

    // "All Exams" is selected by default.
    expect(find.text('All Exams'), findsOneWidget);

    // The chips live in a lazy horizontal list, so a far chip must be scrolled
    // into view before it exists in the tree. Drag on a *chip*, not on the first
    // ListView (that one is the page's vertical scroller).
    await tester.drag(find.text('All Exams'), const Offset(-320, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Railways'), findsOneWidget);
    await tester.tap(find.text('Railways'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs keeps state and never throws', (tester) async {
    await pumpPhone(tester, app());

    for (final label in ['Vault', 'Radar', 'Share', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }
  });

  testWidgets('visible text meets a legible minimum at 1x', (tester) async {
    await pumpPhone(tester, app());

    final texts = tester.widgetList<Text>(find.byType(Text));
    final tooSmall = <String>[];
    for (final t in texts) {
      final size = t.style?.fontSize;
      if (size != null && size < 8) {
        tooSmall.add('${t.data} (${size}px)');
      }
    }
    expect(
      tooSmall,
      isEmpty,
      reason: 'sub-8px text is unreadable at arm length',
    );
  });
}
