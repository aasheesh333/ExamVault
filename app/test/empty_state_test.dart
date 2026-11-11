import 'dart:convert';
import 'dart:io';

import 'package:examvault/app.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/models/live_feed_dto.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
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
  late _EmptyStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_empty_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('c$stamp');
    settingsBox = await Hive.openBox<dynamic>('s$stamp');
    store = _EmptyStore();
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

      // The exact wording may change; what must not change is that the radar
      // states it is empty instead of inventing rows.
      expect(find.textContaining('Nothing live'), findsOneWidget);
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
        find.textContaining('We will not guess which exam'),
        findsOneWidget,
        reason: 'the CTA must explain why it cannot run',
      );
      // It must also say where to go. "Tap a result on the Radar tab" was wrong:
      // this is the Radar tab, and the live list is on Home.
      expect(find.text('See live results'), findsOneWidget);
      expect(
        find.textContaining('on the Radar tab'),
        findsNothing,
        reason: 'never point at the screen the user is already on',
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

  group('a dead edge falls back to the cached feed', () {
    /// Four rows exactly as the repository would have serialised them on the
    /// last good fetch — one of them already retired by the publisher.
    LiveFeed cachedFeed() {
      final now = DateTime.now();
      return LiveFeed(
        generatedAt: now.subtract(const Duration(minutes: 6)),
        revision: 3,
        updates: [
          LiveUpdate(
            examId: 'ssc_cgl_2026',
            category: ExamCategory.ssc,
            examName: 'SSC CGL result',
            contextLine: 'Direct PDF',
            status: UpdateStatus.resultOut,
            publishedAt: now.subtract(const Duration(hours: 2)),
          ),
          LiveUpdate(
            examId: 'rrb_ntpc_2026',
            category: ExamCategory.railways,
            examName: 'RRB NTPC CBT-1',
            contextLine: 'Notice board',
            status: UpdateStatus.admitCardLive,
            publishedAt: now.subtract(const Duration(hours: 5)),
          ),
          LiveUpdate(
            examId: 'ibps_po_2026',
            category: ExamCategory.banking,
            examName: 'IBPS PO prelims',
            contextLine: 'Official PDF',
            status: UpdateStatus.formClosing,
            publishedAt: now.subtract(const Duration(hours: 9)),
          ),
          // Retired on the publisher's side: it sits in the cache document but
          // must never reach the list — a stale "RESULT OUT" is misinformation.
          LiveUpdate(
            examId: 'upsc_retired',
            category: ExamCategory.upsc,
            examName: 'Retired UPSC notice',
            contextLine: 'Withdrawn by the commission',
            status: UpdateStatus.resultOut,
            publishedAt: now.subtract(const Duration(days: 40)),
            expiresAt: now.subtract(const Duration(days: 10)),
          ),
        ],
      );
    }

    /// The edge is down: every attempt, retries included, answers 503.
    Widget appWithDeadEdge() {
      final mock = MockClient((req) async {
        if (req.url.path.contains('live_feed')) {
          return http.Response('Service Unavailable', 503);
        }
        return http.Response('none', 404);
      });
      return ProviderScope(
        overrides: [
          httpCacheBoxProvider.overrideWithValue(cacheBox),
          settingsBoxProvider.overrideWithValue(settingsBox),
          admitCardRepositoryProvider.overrideWith(
            (ref) => AdmitCardRepository(store: store),
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
      );
    }

    testWidgets('cached rows render, labelled CACHED, expired row dropped', (
      tester,
    ) async {
      // Seed the repository-level cache exactly the way the last successful
      // refresh left it. Real file I/O, so it runs on the real clock before
      // the widget mounts.
      await tester.runAsync(() async {
        await cacheBox.put(
          LiveFeedStore.key,
          LiveFeedStore.toJson(cachedFeed()),
        );
      });

      await pumpPhone(tester, appWithDeadEdge());

      // The first paint comes from the synchronous Hive cache read; the failed
      // refresh arrives over the CDN's three-attempt retry chain, whose mock
      // responses only complete on the real event loop (the fake-clock
      // limitation result_day_test documents) and whose jittered backoff
      // delays only elapse on pumped time. Alternate the two until the chain
      // has fully landed — worst case ~1.2 s of jitter across two delays.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 900)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      // The header must own up to where the data came from...
      expect(find.textContaining('CACHED'), findsOneWidget);
      expect(find.text('NO FEED'), findsNothing);
      // ...and the failure itself must surface — the snapshot's error used to
      // be read by no widget, so a dead edge looked like a quiet one.
      expect(find.textContaining('Edge returned 503'), findsOneWidget);
      expect(find.textContaining('Nothing live right now'), findsNothing);

      // Scroll the radar fully into the lazy viewport before counting rows.
      await tester.drag(find.text('MY ADMIT CARDS'), const Offset(0, -160));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(LiveRadarTile), findsNWidgets(3));
      expect(find.text('SSC CGL result'), findsOneWidget);
      expect(find.text('RRB NTPC CBT-1'), findsOneWidget);
      expect(find.text('IBPS PO prelims'), findsOneWidget);
      // The retired row stays filtered even though it is in the cache document.
      expect(find.textContaining('Retired UPSC notice'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// An empty vault that resolves immediately.
///
/// The shipped `SecureVaultStore` talks to `flutter_secure_storage`, whose
/// platform channel never completes in a widget test — so the vault stayed in
/// `AsyncLoading` forever and the share tab rendered its loading branch instead of
/// its empty state. The behaviour under test here is the empty state, so the
/// storage primitive is the one thing worth faking. Production also bounds the
/// read (5 s) so a hung channel cannot strand the UI.
class _EmptyStore implements SecureVaultStore {
  @override
  Future<List<String>> readIndex() async => const [];

  @override
  Future<String?> readRaw(String id) async => null;

  @override
  Future<Map<String, String>> readAllRaw() async => const {};

  @override
  Future<void> writeIndex(List<String> ids) async {}

  @override
  Future<void> writeRaw(String id, String payload) async {}

  @override
  Future<void> deleteRaw(String id) async {}

  @override
  Future<void> wipe() async {}
}
