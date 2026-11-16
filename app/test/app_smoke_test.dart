import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:examvault/app.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
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

  // ---------------------------------------------------------------------------
  // Bell badge lifecycle
  // ---------------------------------------------------------------------------

  /// Six actionable rows — exactly the statuses the badge counts — published
  /// minutes ago: new relative to the epoch-default seen stamp, but old
  /// enough that any markSeen performed during a test would suppress them.
  String sixRowFeedJson() {
    final now = DateTime.now();
    return jsonEncode({
      'generated_at': now.toUtc().toIso8601String(),
      'revision': 8,
      'updates': [
        for (var i = 0; i < 6; i++)
          {
            'exam_id': 'ssc_notice_$i',
            'category': 'ssc',
            'exam_name': 'SSC CGL Tier-1 2026 notice $i',
            'context': 'Direct PDF · 18.4 MB',
            'status': 'result_out',
            'published_at': now
                .subtract(Duration(minutes: 2 + i * 2))
                .toUtc()
                .toIso8601String(),
          },
      ],
    });
  }

  /// The same six rows as an entity feed, all published at [published].
  LiveFeed sixRowFeed(DateTime published) => LiveFeed(
    generatedAt: published,
    revision: 9,
    updates: [
      for (var i = 0; i < 6; i++)
        LiveUpdate(
          examId: 'ssc_notice_$i',
          category: ExamCategory.ssc,
          examName: 'SSC CGL Tier-1 2026 notice $i',
          contextLine: 'Direct PDF · 18.4 MB',
          status: UpdateStatus.resultOut,
          publishedAt: published.add(Duration(seconds: i)),
          expiresAt: published.add(const Duration(days: 2)),
        ),
    ],
  );

  Widget appWithFeed(String feedJson) {
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(feedJson, 200);
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

  Widget appWithGatedFeed(Completer<LiveFeedSnapshot> gate) {
    final mock = MockClient((_) async => http.Response('', 404));
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
        liveFeedProvider.overrideWith(() => _GatedLiveFeed(gate)),
      ],
      child: const ExamVaultApp(),
    );
  }

  testWidgets('the bell badges actionable rows and clears once read', (
    tester,
  ) async {
    await pumpPhone(tester, appWithFeed(sixRowFeedJson()));
    // The MockClient's feed response only completes on the real event loop
    // (the fake-clock limitation result_day_test documents); without this hop
    // the badge would never see its six rows.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));

    final bell = find.byTooltip('Notifications');
    expect(
      find.descendant(of: bell, matching: find.text('6')),
      findsOneWidget,
      reason: 'six actionable rows must badge the bell',
    );

    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(find.text('6 updates need a look'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Reading a loaded inbox clears the badge and stamps the read time.
    expect(find.descendant(of: bell, matching: find.text('6')), findsNothing);
    final seen = settingsBox.get('alerts_seen_at');
    expect(
      seen,
      isA<String>(),
      reason: 'reading the inbox must record alerts_seen_at',
    );
    expect(DateTime.tryParse(seen as String), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the bell while the feed loads suppresses nothing', (
    tester,
  ) async {
    // Published long before anything the user can do in this test: if opening
    // the bell stamped them seen while the feed was still loading — the old
    // unconditional markSeen — they could never badge again.
    final published = DateTime.now().subtract(const Duration(minutes: 10));
    final gate = Completer<LiveFeedSnapshot>();

    await pumpPhone(tester, appWithGatedFeed(gate));

    final bell = find.byTooltip('Notifications');
    expect(find.descendant(of: bell, matching: find.text('6')), findsNothing);

    await tester.tap(bell);
    // Bounded pumps, not pumpAndSettle: the loading state now renders an
    // indeterminate CircularProgressIndicator, and an animation that never
    // ends never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The loading feed says it is checking. It used to render as an empty
    // inbox — the misleading copy that triggered the unconditional markSeen.
    expect(find.text('Checking for updates…'), findsOneWidget);
    expect(find.text('Nothing needs your attention.'), findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(
      settingsBox.get('alerts_seen_at'),
      isNull,
      reason: 'a sheet that never rendered loaded alerts must not mark seen',
    );

    // The feed lands. The six alerts published *before* the bell was opened
    // must badge — proof the early open suppressed nothing.
    gate.complete(
      LiveFeedSnapshot(
        feed: sixRowFeed(published),
        source: FeedSource.network,
        fetchedAt: DateTime.now(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.descendant(of: bell, matching: find.text('6')),
      findsOneWidget,
      reason: 'the badge must appear once the loaded feed lands',
    );
    expect(tester.takeException(), isNull);
  });
}

/// A feed notifier whose load is gated by the test.
///
/// The literal "invalidate + hanging HTTP client" recipe cannot hold
/// `liveFeedProvider` in loading: `LiveFeedNotifier.build` deliberately
/// answers from the repository cache *without awaiting* the network, so the
/// provider resolves within a microtask even while the fetch hangs. The
/// loading state is therefore injected directly — the same reason the matrix
/// harness injects vault loading/error states instead of simulating them
/// with hanging storage reads.
class _GatedLiveFeed extends LiveFeedNotifier {
  _GatedLiveFeed(this._gate);

  final Completer<LiveFeedSnapshot> _gate;

  @override
  Future<LiveFeedSnapshot> build() => _gate.future;
}
