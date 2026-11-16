import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:examvault/app.dart';
import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/models/live_feed_dto.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

      // Before the edge answers, the radar says it is checking — it must not
      // claim the radar is empty (that was the P1-1 lie, and the sentinel is the
      // steady state for the whole first fetch).
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(find.textContaining('Nothing live'), findsNothing);

      // The canned 200 arrives on the real event loop; the claim under test is
      // about the *answered* state, so let it land.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

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

  /// One tappable focus stop per card.
  ///
  /// `EvCard` gained a labelled, actionable wrapper node in Task 2 while the
  /// inner `InkWell` kept emitting its own `focus, tap` node, so a screen reader
  /// read the summary label and then the raw content — both activating the same
  /// callback. `InkWell(excludeFromSemantics: ...)` drops only the InkWell's own
  /// tap action and leaves the child text nodes intact.
  group('EvCard semantics', () {
    testWidgets('a labelled tappable card exposes exactly one tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: EvCard(
                semanticLabel: 'Open notice details',
                onTap: () => taps++,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SSC CGL Tier-1 2026'),
                    Text('Result out \u00b7 ssc.gov.in'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final card = tester.getSemantics(
        find.bySemanticsLabel('Open notice details'),
      );
      expect(card.flagsCollection.isButton, isTrue);
      expect(
        card.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'the labelled node is the one the screen reader activates',
      );

      // The content node is still announced, but it must not offer a second,
      // identical tap action.
      final content = tester.getSemantics(find.text('SSC CGL Tier-1 2026'));
      expect(
        content.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
        reason: 'the inner InkWell must not duplicate the card action',
      );

      handle.dispose();
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
      await tester.drag(find.text('MY ADMIT CARDS'), const Offset(0, -420));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(LiveRadarTile), findsNWidgets(3));
      expect(find.text('SSC CGL result'), findsOneWidget);
      expect(find.text('RRB NTPC CBT-1'), findsOneWidget);
      expect(find.text('IBPS PO prelims'), findsOneWidget);
      // The retired row stays filtered even though it is in the cache document.
      expect(find.textContaining('Retired UPSC notice'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    /// A quiet day: the edge answered with a real document that says zero rows.
    /// That is an answer, not an absence — the cold start must say CACHED, not
    /// NO FEED, because the device is holding a document that already says the
    /// radar is quiet.
    testWidgets('an empty cached document reads CACHED, not NO FEED', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await cacheBox.put(
          LiveFeedStore.key,
          LiveFeedStore.toJson(
            LiveFeed(
              generatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
              revision: 7,
              updates: const [],
            ),
          ),
        );
      });

      await pumpPhone(tester, appWithDeadEdge());

      // Drain the retry chain's backoff timers (same reason as the test above):
      // a pending timer fails the test at teardown even when every assertion
      // passed.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 900)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('CACHED'), findsOneWidget);
      expect(find.text('NO FEED'), findsNothing);
      expect(find.text('CHECKING…'), findsNothing);
      // A stored document is an answer, so the hero is not waiting for one. It
      // may say "0 live updates" or, once the dead edge's failure lands, "radar
      // unreachable" — either way it is not still syncing.
      expect(find.textContaining('Syncing radar'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  /// The production cold-start shape: `LiveFeedNotifier.build` answers from
  /// `readCached() ?? emptySnapshot()` *synchronously* and refreshes with
  /// `unawaited(...)`, so the provider is `AsyncData(empty, source: none,
  /// error: null)` for the whole first fetch — up to ~25 s on a dead network,
  /// and guaranteed right after delete-all clears the cache.
  ///
  /// The alerts inbox was taught to say "Checking for updates…" in that window;
  /// Home still said `NO FEED`, "Nothing live right now. We check the edge every
  /// 60 seconds." and "0 live updates" — the same lie, one screen over. These
  /// mirror the inbox's cold-start tests.
  group('a first fetch that has not answered', () {
    Widget appAwaitingFirstAnswer(_FirstAnswerGate gate) => ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: store),
        ),
        liveFeedProvider.overrideWith(() => _AwaitingLiveFeed(gate)),
      ],
      child: const ExamVaultApp(),
    );

    testWidgets('Home says it is checking, not that the radar is empty', (
      tester,
    ) async {
      final gate = _FirstAnswerGate();
      await pumpPhone(tester, appAwaitingFirstAnswer(gate));

      // The radar header: no feed has been described yet.
      expect(find.text('CHECKING…'), findsOneWidget);
      expect(
        find.text('NO FEED'),
        findsNothing,
        reason: 'NO FEED asserts the radar is empty; nothing has answered yet',
      );
      // The empty-state card says what is happening, not what is not.
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(
        find.textContaining('Nothing live right now'),
        findsNothing,
        reason:
            'the "we check every 60 seconds" line is for an answered-empty '
            'feed, not for a fetch that is still in flight',
      );
      // The hero count has no answer to show.
      expect(find.textContaining('0 live updates'), findsNothing);
      expect(find.textContaining('Syncing radar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the answered-empty feed keeps the quiet copy and a real zero',
      (tester) async {
        final gate = _FirstAnswerGate();
        await pumpPhone(tester, appAwaitingFirstAnswer(gate));
        expect(find.text('CHECKING…'), findsOneWidget);

        // The edge answered: reached, and publishing nothing.
        gate.answerEmpty();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('CHECKING…'), findsNothing);
        expect(find.text('Checking for updates…'), findsNothing);
        expect(find.textContaining('Nothing live right now'), findsOneWidget);
        expect(find.textContaining('0 live updates'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

/// One pending first answer, shared by every rebuild of the double below.
class _FirstAnswerGate {
  final _pending = Completer<LiveFeedSnapshot>();

  Future<LiveFeedSnapshot> get future => _pending.future;

  /// A real answer: the edge was reached and published zero rows.
  void answerEmpty() => _pending.complete(
    LiveFeedSnapshot(
      feed: LiveFeed.empty,
      source: FeedSource.network,
      fetchedAt: DateTime.now(),
    ),
  );
}

/// Mirrors `LiveFeedNotifier.build()` — the shape production actually has.
///
/// `AsyncLoading` cannot reproduce it: the real notifier answers from the
/// repository synchronously and refreshes in the background, so the sentinel
/// (`source: none`, no error, no rows) is the *data* state for the whole first
/// fetch, not the loading state.
class _AwaitingLiveFeed extends LiveFeedNotifier {
  _AwaitingLiveFeed(this.gate);

  final _FirstAnswerGate gate;

  @override
  Future<LiveFeedSnapshot> build() async {
    unawaited(_pull());
    return LiveFeedSnapshot(
      feed: LiveFeed.empty,
      source: FeedSource.none,
      fetchedAt: DateTime.now(),
    );
  }

  Future<void> _pull() async {
    final snapshot = await gate.future;
    if (!ref.mounted) return;
    state = AsyncData(snapshot);
  }
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
