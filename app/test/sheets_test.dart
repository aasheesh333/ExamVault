import 'dart:async';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/data/services/push_service.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/about/about_sheet.dart';
import 'package:examvault/features/calendar/exam_calendar_screen.dart';
import 'package:examvault/features/command_center/command_center_screen.dart';
import 'package:examvault/features/command_center/widgets/alerts_sheet.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/features/command_center/widgets/wallet_pass_card.dart';
import 'package:examvault/features/result_checker/instant_result_checker_screen.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
import 'package:examvault/shared/widgets/ev_surfaces.dart';
import 'package:examvault/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_vault_store.dart';
import 'support/matrix.dart';

/// The two bottom sheets, at the worst size the app supports.
///
/// Both open at 72–92% of the viewport, so a phone 320px wide at 2.0x text is the
/// case where a scrolling header collides with content and where text used to
/// paint over the rounded top corners.
void main() {
  late Directory dir;
  late Box<dynamic> settingsBox;
  late Box<dynamic> cacheBox;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The bundled typefaces, so a 2.0x layout test measures the real advances
    // instead of the square-glyph test font.
    await (FontLoader('Plus Jakarta Sans')
          ..addFont(
            rootBundle.load('assets/google_fonts/PlusJakartaSans-Regular.ttf'),
          )
          ..addFont(
            rootBundle.load('assets/google_fonts/PlusJakartaSans-Medium.ttf'),
          )
          ..addFont(
            rootBundle.load('assets/google_fonts/PlusJakartaSans-SemiBold.ttf'),
          )
          ..addFont(
            rootBundle.load('assets/google_fonts/PlusJakartaSans-Bold.ttf'),
          ))
        .load();
    await (FontLoader('IBM Plex Mono')
          ..addFont(
            rootBundle.load('assets/google_fonts/IBMPlexMono-Regular.ttf'),
          )
          ..addFont(
            rootBundle.load('assets/google_fonts/IBMPlexMono-Medium.ttf'),
          )
          ..addFont(
            rootBundle.load('assets/google_fonts/IBMPlexMono-SemiBold.ttf'),
          ))
        .load();
    dir = await Directory.systemTemp.createTemp('ev_sheets_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    settingsBox = await Hive.openBox<dynamic>(
      'sheet_settings_${DateTime.now().microsecondsSinceEpoch}',
    );
    cacheBox = await Hive.openBox<dynamic>(
      'sheet_cache_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // Best effort — a leaked temp dir must never fail the suite.
    }
  });

  LiveFeed feed() {
    final now = DateTime.now();
    return LiveFeed(
      generatedAt: now,
      revision: 1,
      updates: [
        for (var i = 0; i < 6; i++)
          LiveUpdate(
            examId: 'exam_$i',
            category: ExamCategory.ssc,
            examName: 'SSC CGL Tier-1 2026 notice $i',
            contextLine: 'Direct PDF · 18.4 MB',
            status: UpdateStatus.resultOut,
            publishedAt: now.subtract(Duration(minutes: 2 + i)),
            expiresAt: now.add(const Duration(days: 2)),
          ),
      ],
      sources: const [
        SourceHealth(
          id: 'ssc',
          label: 'Staff Selection Commission',
          status: 'ok',
          rows: 18,
        ),
        SourceHealth(
          id: 'ibps',
          label: 'Institute of Banking Personnel Selection',
          status: 'unavailable',
          rows: 0,
        ),
      ],
    );
  }

  /// [feedOverride] replaces the healthy six-row notifier so a test can drive
  /// the sheet's other states (checking, failure, genuinely empty) through the
  /// real `liveFeedProvider` rather than a hand-built widget.
  ///
  /// [onRef] hands the test a live `WidgetRef` so it can invalidate the feed the
  /// way the radar's pull-to-refresh does.
  Widget host({
    LiveFeedNotifier Function()? feedOverride,
    ValueChanged<Future<bool>>? onAlertsResult,
    ValueChanged<WidgetRef>? onRef,
    PushService? push,
  }) => ProviderScope(
    overrides: [
      settingsBoxProvider.overrideWithValue(settingsBox),
      if (push != null) pushServiceProvider.overrideWithValue(push),
      liveFeedProvider.overrideWith(
        feedOverride ??
            () => _StaticLiveFeed(
              LiveFeedSnapshot(
                feed: feed(),
                source: FeedSource.network,
                fetchedAt: DateTime.now(),
              ),
            ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            // The real bell keeps this provider alive; without a listener an
            // invalidate would dispose it and drop the snapshot the error is
            // attached to.
            ref.watch(liveFeedProvider);
            onRef?.call(ref);
            return Column(
              children: [
                TextButton(
                  onPressed: () => showAboutSheet(context),
                  child: const Text('open about'),
                ),
                TextButton(
                  // The future matters to the markSeen contract: it resolves to
                  // whether a loaded, non-empty list actually reached the screen.
                  onPressed: () {
                    final pending = showAlertsSheet(context, ref);
                    onAlertsResult?.call(pending);
                  },
                  child: const Text('open alerts'),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// 320x568 logical pixels — the smallest phone the design targets — at the
  /// 2.0x ceiling the text-scale clamp now allows.
  void smallPhone(WidgetTester tester, {double textScale = 2.0}) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// 393x852 — the reference device the geometry defect was measured on.
  void defaultPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// The sheet's own surface must clip, or scrolled text paints over the page
  /// above the rounded corners.
  void expectClipped(WidgetTester tester) {
    expect(
      find.ancestor(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.clipBehavior == Clip.antiAlias,
        ),
      ),
      findsWidgets,
      reason: 'a sheet surface with rounded corners must clip its content',
    );
  }

  Future<void> openAbout(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.text('open about'));
    await tester.pumpAndSettle();
  }

  Future<void> openAlerts(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.text('open alerts'));
    await tester.pumpAndSettle();
  }

  group('About sheet at 320px and 2.0x', () {
    testWidgets('renders without overflow or clipped text', (tester) async {
      smallPhone(tester);
      await openAbout(tester);

      expect(find.text('About ExamVault'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectClipped(tester);
    });

    testWidgets('keeps the close button a 44px tap target', (tester) async {
      smallPhone(tester);
      await openAbout(tester);

      final close = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.close_rounded),
          matching: find.byType(InkWell),
        ),
      );
      expect(close.width, greaterThanOrEqualTo(44));
      expect(close.height, greaterThanOrEqualTo(44));
    });

    testWidgets('scrolls all the way to the disclaimer', (tester) async {
      smallPhone(tester);
      await openAbout(tester);

      await tester.scrollUntilVisible(
        find.textContaining('not affiliated'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      // scrollUntilVisible counts a row whose top edge merely intersects the
      // viewport as visible, which can leave its centre below the screen (the
      // sheet gained a "Your data" section). ensureVisible finishes the job.
      await tester.ensureVisible(find.textContaining('not affiliated'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('not affiliated').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Privacy policy sheet at 320px and 2.0x', () {
    testWidgets('scrolls to the last section', (tester) async {
      smallPhone(tester);
      await openAbout(tester);

      // Two steps, each fixing a real trap: the sheet's ListView is lazy, so a
      // row below the fold is not in the tree at all — scrollUntilVisible
      // scrolls it into existence. But it counts a row whose top edge merely
      // intersects the viewport as "visible", which can leave the row's CENTRE
      // one pixel below the screen (measured on 320x568 @2.0x) and the tap
      // misses. ensureVisible afterwards guarantees full visibility.
      await tester.scrollUntilVisible(
        find.text('Read the privacy policy'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Read the privacy policy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read the privacy policy'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectClipped(tester);

      await tester.scrollUntilVisible(
        find.textContaining('never hosts or redistributes a copy'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      // The policy grew with the picker and the delete-all disclosure, so the
      // last row can end up with only its top edge inside the viewport — which
      // scrollUntilVisible counts as visible. ensureVisible finishes the job, as
      // the About sheet's own last-row test already does.
      await tester.ensureVisible(
        find.textContaining('never hosts or redistributes a copy'),
      );
      await tester.pumpAndSettle();
      expect(
        find
            .textContaining('never hosts or redistributes a copy')
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('About theme picker', () {
    setUp(() async {
      // Start from dark so flipping to Light is an observable change.
      await settingsBox.put('theme', 'dark');
    });

    /// A theme-reactive host: unlike [host] (fixed dark for layout checks),
    /// this one derives `themeMode` from the provider the About chips write.
    Widget themeHost(Box<dynamic> box) => ProviderScope(
      overrides: [
        settingsBoxProvider.overrideWithValue(box),
        liveFeedProvider.overrideWith(
          () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: feed(),
              source: FeedSource.network,
              fetchedAt: DateTime.now(),
            ),
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final pref = ref.watch(themePreferenceProvider);
          return MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: pref.mode,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAboutSheet(context),
                  child: const Text('open about'),
                ),
              ),
            ),
          );
        },
      ),
    );

    Future<void> openAboutOn(WidgetTester tester, Widget hostWidget) async {
      await tester.pumpWidget(hostWidget);
      await tester.pump();
      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
    }

    List<String> selectedChips(WidgetTester tester) => tester
        .widgetList<EvChip>(find.byType(EvChip))
        .where((c) => c.selected)
        .map((c) => c.label)
        .toList();

    testWidgets('tapping Light flips the host theme and persists it', (
      tester,
    ) async {
      await openAboutOn(tester, themeHost(settingsBox));
      expect(
        Theme.of(tester.element(find.text('About ExamVault'))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      // The whole app follows the chip, and the choice survives a relaunch.
      expect(
        Theme.of(tester.element(find.text('About ExamVault'))).brightness,
        Brightness.light,
      );
      expect(settingsBox.get('theme'), 'light');
      expect(selectedChips(tester), ['Light']);
    });

    testWidgets('a failed write rolls the chips back to the persisted value', (
      tester,
    ) async {
      // A box whose writes fail (full disk, locked file) with 'light' as the
      // last persisted preference. Swapping providers mid-test rebuilds the
      // Riverpod container and tears down the open sheet route, so this test
      // starts on the broken box instead — the rollback is what is under test.
      final broken = _FailingSettingsBox({'theme': 'light'});
      await openAboutOn(tester, themeHost(broken));
      expect(selectedChips(tester), ['Light']);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // An optimistic chip must not keep claiming a preference that will be
      // gone on next launch.
      expect(selectedChips(tester), [
        'Light',
      ], reason: 'the chip must roll back to the persisted value');
      expect(broken.get('theme'), 'light');
    });
  });

  group('Alerts sheet at 320px', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('header never overlaps the first row at ${scale}x', (
        tester,
      ) async {
        smallPhone(tester, textScale: scale);
        await openAlerts(tester);

        expect(find.text('Alerts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectClipped(tester);

        final subtitle = tester.getRect(
          find.textContaining('updates need a look'),
        );
        final firstRow = tester.getRect(
          find.text('SSC CGL Tier-1 2026 notice 0'),
        );
        expect(
          firstRow.top,
          greaterThanOrEqualTo(subtitle.bottom),
          reason: 'the header must sit fully above the list, not on row 1',
        );
      });
    }

    testWidgets('header stays put while the list scrolls', (tester) async {
      smallPhone(tester);
      await openAlerts(tester);

      // The header must live outside the scrollable, or it rides up with rows.
      expect(
        find.ancestor(
          of: find.text('Alerts'),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );

      // First gesture grows the sheet to its max extent; after that the list
      // scrolls and the header must not move a pixel.
      await tester.dragFrom(const Offset(160, 300), const Offset(0, -300));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('Alerts'));

      await tester.dragFrom(const Offset(160, 300), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Alerts')), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a 44px close button', (tester) async {
      smallPhone(tester);
      await openAlerts(tester);

      final close = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.close_rounded),
          matching: find.byType(InkWell),
        ),
      );
      expect(close.width, greaterThanOrEqualTo(44));
      expect(close.height, greaterThanOrEqualTo(44));
    });
  });

  /// "Still asking", "the ask failed" and "the answer was nothing" are three
  /// different facts. The sheet used to render all of them as the third, so a
  /// cold start or a dead edge with nothing cached announced "Nothing needs
  /// your attention." on result day — the most alarming sentence this app can
  /// print.
  group('Alerts sheet states', () {
    /// The production failure shape, and the reason `hasError` alone is not
    /// enough: `LiveFeedNotifier.build` never rethrows, so a dead edge arrives
    /// as AsyncData whose snapshot carries `error` — not AsyncError.
    LiveFeedSnapshot failedSnapshot(String reason) => LiveFeedSnapshot(
      feed: LiveFeed.empty,
      source: FeedSource.none,
      fetchedAt: DateTime.now(),
      error: reason,
    );

    testWidgets('cold start says it is checking, not that nothing is there', (
      tester,
    ) async {
      smallPhone(tester);
      final gate = Completer<LiveFeedSnapshot>();
      await tester.pumpWidget(host(feedOverride: () => _GatedLiveFeed(gate)));
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      // Never pumpAndSettle here: an indeterminate spinner schedules frames
      // forever, so "settled" would mean a timeout.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.textContaining('Nothing needs your attention'),
        findsNothing,
        reason: 'a cold start must never claim an empty inbox',
      );
      expect(find.textContaining('updates need a look'), findsNothing);
      expect(find.text('Could not check for updates.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cold start never counts the inbox as read', (tester) async {
      smallPhone(tester);
      final gate = Completer<LiveFeedSnapshot>();
      Future<bool>? rendered;

      await tester.pumpWidget(
        host(
          feedOverride: () => _GatedLiveFeed(gate),
          onAlertsResult: (pending) => rendered = pending,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(await rendered, isFalse);
    });

    testWidgets('a provider failure says so, and Retry re-reads the feed', (
      tester,
    ) async {
      smallPhone(tester);
      final reads = _ReadCounter()..fail = true;

      await tester.pumpWidget(
        host(feedOverride: () => _CountingLiveFeed(reads, failedSnapshot('x'))),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      // The subtitle names the state; the card names the failure. They must not
      // be the same sentence twice in one 100px header + card.
      expect(find.text('Could not check for updates.'), findsOneWidget);
      expect(find.text('The check failed'), findsOneWidget);
      expect(find.textContaining('Nothing needs your attention'), findsNothing);
      // The provider's rejection carries no user-facing text, so the card says
      // the cause-neutral sentence rather than printing `error.toString()`.
      expect(
        find.textContaining('The live feed could not be read'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(reads.count, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(
        reads.count,
        2,
        reason: 'Retry must invalidate liveFeedProvider, not just repaint',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dead edge with nothing cached is an error, not empty', (
      tester,
    ) async {
      smallPhone(tester);
      // The repository's literal message (`live_feed_repository.dart:138`),
      // instruction and all: it is the text production actually shows.
      const repositoryMessage =
          'The live feed could not be read. Pull to retry.';
      final reads = _ReadCounter();

      await tester.pumpWidget(
        host(
          feedOverride: () =>
              _CountingLiveFeed(reads, failedSnapshot(repositoryMessage)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Could not check for updates.'), findsOneWidget);
      expect(find.text('The check failed'), findsOneWidget);
      // The diagnostic half is kept verbatim: it is the only text that knows
      // *why* the check failed.
      expect(
        find.text('The live feed could not be read.'),
        findsOneWidget,
        reason: 'the repository diagnostic must survive unedited',
      );
      // …but its "Pull to retry." instruction describes the radar's gesture, not
      // this sheet's: there is nothing to pull in a modal, so it must not reach
      // the reader.
      expect(find.textContaining('Pull to retry'), findsNothing);
      expect(find.text('Tap Retry to check again.'), findsOneWidget);
      expect(
        find.textContaining('Nothing needs your attention'),
        findsNothing,
        reason: 'a dead edge with no cache must never read as a quiet inbox',
      );
      expect(reads.count, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(reads.count, 2);
      expect(tester.takeException(), isNull);
    });

    // The split is on the gesture verb, not on one hardcoded sentence: the
    // repository must be free to reword its instruction without silently
    // telling a modal reader to pull.
    for (final instruction in [
      'Pull to retry.',
      'Pull down to refresh.',
      'Swipe down to retry.',
      'Drag down to try again.',
    ]) {
      testWidgets('"$instruction" never reaches a modal reader', (
        tester,
      ) async {
        smallPhone(tester);

        await tester.pumpWidget(
          host(
            feedOverride: () => _StaticLiveFeed(
              failedSnapshot('The live feed could not be read. $instruction'),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('open alerts'));
        await tester.pumpAndSettle();

        expect(find.text('The live feed could not be read.'), findsOneWidget);
        expect(
          find.textContaining(RegExp(r'Pull|Swipe|Drag')),
          findsNothing,
          reason: 'a modal has nothing to pull',
        );
        expect(find.text('Tap Retry to check again.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a non-gesture second sentence is kept as diagnostic detail', (
      tester,
    ) async {
      smallPhone(tester);

      await tester.pumpWidget(
        host(
          feedOverride: () => _StaticLiveFeed(
            failedSnapshot(
              'The live feed could not be read. The edge sent an error page.',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      // Only gesture instructions are dropped. Any other detail the repository
      // attaches is diagnostic and must survive verbatim.
      expect(
        find.text(
          'The live feed could not be read. The edge sent an error page.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a message that is only a gesture instruction shows no '
        'diagnostic', (tester) async {
      smallPhone(tester);

      await tester.pumpWidget(
        host(
          feedOverride: () => _StaticLiveFeed(failedSnapshot('Pull to retry.')),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      // Nothing left to show once the instruction is gone — and the card must
      // not render an empty paragraph or the word "Pull".
      expect(find.text('The check failed'), findsOneWidget);
      expect(find.text('Tap Retry to check again.'), findsOneWidget);
      expect(find.textContaining(RegExp(r'Pull|Swipe|Drag')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cached rows survive a failed refresh', (tester) async {
      smallPhone(tester);
      const reason = 'Could not reach the live feed. Check your connection.';
      Future<bool>? rendered;

      await tester.pumpWidget(
        host(
          feedOverride: () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: feed(),
              source: FeedSource.cache,
              fetchedAt: DateTime.now(),
              error: reason,
            ),
          ),
          onAlertsResult: (pending) => rendered = pending,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      // A usable list outranks the failure: the rows stay, and the failure is
      // reported above them instead of replacing them. At 320@2.0x the card
      // pushes row 1 past the fold, and the sheet's ListView is lazy, so scroll
      // it into existence before asserting.
      expect(find.text('6 updates need a look'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('SSC CGL Tier-1 2026 notice 0'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('SSC CGL Tier-1 2026 notice 0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(
        await rendered,
        isTrue,
        reason: 'a loaded list that reached the screen must count as read',
      );
    });

    testWidgets('a cached empty document plus a rejected refresh is a failure', (
      tester,
    ) async {
      smallPhone(tester);
      final reads = _ReadCounter();
      WidgetRef? containerRef;

      await tester.pumpWidget(
        host(
          feedOverride: () => _CountingLiveFeed(
            reads,
            LiveFeedSnapshot(
              feed: LiveFeed.empty,
              // A stored document that says zero rows — a *real* answer, so the
              // calm copy is honest here. The `none` sentinel is covered below.
              source: FeedSource.cache,
              fetchedAt: DateTime.now(),
            ),
          ),
          onRef: (ref) => containerRef = ref,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing needs your attention.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // What the radar's pull-to-refresh does. Riverpod keeps the previous
      // snapshot inside the error state, so `hasValue` stays true and `hasError`
      // alone (`&& !hasValue`) would miss the failure entirely.
      reads.fail = true;
      containerRef!.invalidate(liveFeedProvider);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Could not check for updates.'), findsOneWidget);
      expect(find.text('The check failed'), findsOneWidget);
      expect(
        find.text('Nothing needs your attention.'),
        findsNothing,
        reason: 'a retained empty snapshot must not hide a failed refresh',
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rejection over the unanswered sentinel is a failure, not a '
        'spinner', (tester) async {
      smallPhone(tester);
      final reads = _ReadCounter();
      WidgetRef? containerRef;

      await tester.pumpWidget(
        host(
          feedOverride: () => _CountingLiveFeed(
            reads,
            LiveFeedSnapshot(
              feed: LiveFeed.empty,
              source: FeedSource.none,
              fetchedAt: DateTime.now(),
            ),
          ),
          onRef: (ref) => containerRef = ref,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The sentinel alone means "still asking"…
      expect(find.text('Checking for updates…'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      reads.fail = true;
      containerRef!.invalidate(liveFeedProvider);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      // …but a rejection outranks it. Without the `!hasError` guard the retained
      // sentinel would keep the sheet on a spinner forever instead of offering
      // Retry.
      expect(find.text('The check failed'), findsOneWidget);
      expect(find.text('Checking for updates…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a genuinely empty feed keeps the calm copy', (tester) async {
      smallPhone(tester);

      await tester.pumpWidget(
        host(
          feedOverride: () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: LiveFeed.empty,
              // The edge answered and published zero rows. This is the only
              // shape that may claim the inbox is empty; `none` means nobody
              // has answered yet.
              source: FeedSource.network,
              fetchedAt: DateTime.now(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing needs your attention.'), findsOneWidget);
      expect(
        find.textContaining('When a commission publishes a result'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Could not check for updates.'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the exam name outranks the widest pill at 320px @ 2.0x', (
      tester,
    ) async {
      smallPhone(tester);
      final now = DateTime.now();
      // "ADMIT CARD LIVE" is the widest status label in the set. As a non-flex
      // Row child it took ~230 of the row's ~248 usable px at this size and
      // collapsed the exam name to a sliver.
      final widePill = LiveFeed(
        generatedAt: now,
        revision: 1,
        updates: [
          LiveUpdate(
            examId: 'exam_admit',
            category: ExamCategory.ssc,
            examName: 'SSC CGL Tier-1 2026 admit card',
            contextLine: 'Direct PDF · 18.4 MB',
            status: UpdateStatus.admitCardLive,
            publishedAt: now.subtract(const Duration(minutes: 2)),
            expiresAt: now.add(const Duration(days: 2)),
          ),
        ],
      );

      await tester.pumpWidget(
        host(
          feedOverride: () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: widePill,
              source: FeedSource.network,
              fetchedAt: now,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the row must not overflow at 320px @ 2.0x',
      );

      final name = tester.getRect(find.text('SSC CGL Tier-1 2026 admit card'));
      final pill = tester.getRect(find.byType(EvStatusPill));
      expect(
        name.width,
        greaterThan(pill.width),
        reason: 'the exam name is the row subject and must win the width',
      );
      expect(
        pill.right,
        lessThanOrEqualTo(320),
        reason: 'the pill must stay inside the sheet',
      );
    });
  });

  /// The shapes `LiveFeedNotifier.build()` actually produces.
  ///
  /// The doubles above cannot produce them: `_GatedLiveFeed` holds
  /// `AsyncLoading` forever and `_CountingLiveFeed` hands back a snapshot that
  /// already carries `error`. Production does neither. It answers from
  /// `readCached() ?? emptySnapshot()` **synchronously** and refreshes in the
  /// background, so on a fresh install the provider is
  /// `AsyncData(empty, source: none, error: null)` for the whole first fetch —
  /// never `AsyncLoading`. That is why `checking` keyed on
  /// `!hasValue && isLoading` was dead code in production: a cold start on a
  /// dead edge fell through to the empty state and printed the exact sentence
  /// this task exists to delete.
  group('Alerts sheet against production notifier shapes', () {
    /// The sentinel `LiveFeedRepository.emptySnapshot()` returns: nothing has
    /// ever answered. `FeedSource.none` is produced nowhere else.
    LiveFeedSnapshot unanswered() => LiveFeedSnapshot(
      feed: LiveFeed.empty,
      source: FeedSource.none,
      fetchedAt: DateTime.now(),
    );

    Future<void> openSheet(WidgetTester tester, _RefreshGate gate) async {
      await tester.pumpWidget(
        host(feedOverride: () => _ProdLikeLiveFeed(gate: gate)),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      // Bounded pumps: the checking state's spinner never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('step 1: no cache + pending refresh is checking, not empty', (
      tester,
    ) async {
      smallPhone(tester);
      final gate = _RefreshGate();
      await openSheet(tester, gate);

      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Nothing needs your attention.'),
        findsNothing,
        reason:
            'the provider answers with an empty snapshot while the first fetch '
            'is in flight — claiming an empty inbox there is the defect',
      );
      expect(
        find.textContaining('When a commission publishes a result'),
        findsNothing,
      );
      expect(gate.started, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('step 2: the refresh answers with rows and the list appears', (
      tester,
    ) async {
      smallPhone(tester);
      final gate = _RefreshGate();
      await openSheet(tester, gate);
      expect(find.text('Checking for updates…'), findsOneWidget);

      gate.answer(
        LiveFeedSnapshot(
          feed: feed(),
          source: FeedSource.network,
          fetchedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SSC CGL Tier-1 2026 notice 0'), findsOneWidget);
      expect(find.text('6 updates need a look'), findsOneWidget);
      expect(find.text('Checking for updates…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('step 3: the refresh answers empty and the calm copy appears', (
      tester,
    ) async {
      smallPhone(tester);
      final gate = _RefreshGate();
      await openSheet(tester, gate);
      expect(find.text('Checking for updates…'), findsOneWidget);

      // A real answer: the edge was reached and published zero rows. Only this
      // shape — not the `none` sentinel — may claim the inbox is empty.
      gate.answer(
        LiveFeedSnapshot(
          feed: LiveFeed.empty,
          source: FeedSource.network,
          fetchedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing needs your attention.'), findsOneWidget);
      expect(
        find.textContaining('When a commission publishes a result'),
        findsOneWidget,
      );
      expect(find.text('Checking for updates…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('step 4: the refresh fails and the failure card appears', (
      tester,
    ) async {
      smallPhone(tester);
      final gate = _RefreshGate();
      await openSheet(tester, gate);

      // Exactly what `LiveFeedRepository.refresh` returns on a dead edge with
      // nothing cached: the empty snapshot, with `error` attached.
      gate.answer(unanswered().copyWith(error: 'Request timed out'));
      await tester.pumpAndSettle();

      expect(find.text('The check failed'), findsOneWidget);
      expect(find.text('Request timed out'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('Nothing needs your attention.'),
        findsNothing,
        reason: 'a failed check must never read as a quiet inbox',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('step 5: Retry returns to checking, not to the calm copy', (
      tester,
    ) async {
      smallPhone(tester);
      final gate = _RefreshGate();
      await openSheet(tester, gate);

      gate.answer(unanswered().copyWith(error: 'Request timed out'));
      await tester.pumpAndSettle();
      expect(find.text('The check failed'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The rebuild answers `emptySnapshot()` again — the retry is in flight,
      // so the sheet must say so. Showing the calm copy here was a new lie this
      // task introduced by adding a Retry that invalidates the provider.
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(
        find.text('Nothing needs your attention.'),
        findsNothing,
        reason: 'an in-flight retry must not read as a quiet inbox',
      );
      expect(find.text('The check failed'), findsNothing);
      expect(gate.started, 2);

      // And the retry can succeed.
      gate.answer(
        LiveFeedSnapshot(
          feed: feed(),
          source: FeedSource.network,
          fetchedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('6 updates need a look'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  /// Provenance. The doc comment promised "the time each was last checked" while
  /// `SourceHealth.checkedAt` was parsed and read by nothing, so a stale cache's
  /// health was presented as current — the one thing the panel exists to prevent.
  group('About sheet source provenance', () {
    /// The real document's shape: `checked_at` per source, one source without.
    LiveFeed feedWithChecks({DateTime? sscChecked, DateTime? upscChecked}) =>
        LiveFeed(
          generatedAt: DateTime.now(),
          revision: 1,
          updates: const [],
          sources: [
            SourceHealth(
              id: 'ssc',
              label: 'Staff Selection Commission',
              status: 'ok',
              rows: 17,
              homepage: 'https://ssc.gov.in/',
              checkedAt: sscChecked,
            ),
            SourceHealth(
              id: 'upsc',
              label: 'Union Public Service Commission',
              status: 'ok',
              rows: 7,
              homepage: 'https://www.upsc.gov.in/',
              checkedAt: upscChecked,
            ),
          ],
        );

    Future<void> openWith(WidgetTester tester, LiveFeed f) async {
      await tester.pumpWidget(
        host(
          feedOverride: () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: f,
              source: FeedSource.network,
              fetchedAt: DateTime.now(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
    }

    test('the age label is exact against a fixed clock', () {
      final now = DateTime(2026, 11, 16, 12);
      expect(
        sourceCheckedLabel(now.subtract(const Duration(hours: 4)), now),
        'checked 4h ago',
      );
      expect(
        sourceCheckedLabel(now.subtract(const Duration(minutes: 30)), now),
        'checked 30m ago',
      );
      expect(
        sourceCheckedLabel(now.subtract(const Duration(seconds: 20)), now),
        'checked just now',
      );
      // Beyond a day the relative label stops being useful: the date is.
      expect(
        sourceCheckedLabel(now.subtract(const Duration(hours: 30)), now),
        'checked 15 Nov 2026',
      );
      // Clock skew is not a check that happened: nothing is said about time,
      // rather than a date for a check in the future.
      expect(
        sourceCheckedLabel(now.add(const Duration(hours: 3)), now),
        isNull,
      );
      expect(sourceCheckedLabel(now.add(const Duration(days: 2)), now), isNull);
    });

    testWidgets(
      'a source row with a future checked_at says nothing about time',
      (tester) async {
        smallPhone(tester, textScale: 1.0);
        await openWith(
          tester,
          feedWithChecks(
            sscChecked: DateTime.now().add(const Duration(days: 2)),
          ),
        );

        expect(find.text('17 items'), findsOneWidget);
        expect(
          find.textContaining('checked'),
          findsNothing,
          reason: 'a stamp in the future must not render as a completed check',
        );
      },
    );

    test('the homepage wins over the fallback, per commission id', () {
      final byId = {
        'ssc': const SourceHealth(
          id: 'ssc',
          label: 'SSC',
          status: 'ok',
          rows: 17,
          homepage: 'https://ssc.gov.in/new-home',
        ),
        // A source that supplies no homepage must fall back, not resolve null.
        'upsc': const SourceHealth(
          id: 'upsc',
          label: 'UPSC',
          status: 'ok',
          rows: 7,
        ),
      };

      expect(
        commissionUrlFor('ssc', byId, 'https://ssc.gov.in/'),
        'https://ssc.gov.in/new-home',
      );
      expect(
        commissionUrlFor('upsc', byId, 'https://www.upsc.gov.in/'),
        'https://www.upsc.gov.in/',
      );
      // A feed with no health block at all (older documents) keeps the
      // hand-written URL.
      expect(
        commissionUrlFor('tnpsc', const {}, 'https://www.tnpsc.gov.in/'),
        'https://www.tnpsc.gov.in/',
      );
    });

    testWidgets('a source row shows its observed age next to the row count', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      final now = DateTime.now();
      await openWith(
        tester,
        feedWithChecks(sscChecked: now.subtract(const Duration(hours: 4))),
      );

      expect(
        find.text('17 items \u00b7 checked 4h ago'),
        findsOneWidget,
        reason: 'the count alone presents a stale check as current',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the age line fits at 320px @ 2.0x without ellipsising', (
      tester,
    ) async {
      smallPhone(tester);
      final now = DateTime.now();
      await openWith(
        tester,
        feedWithChecks(sscChecked: now.subtract(const Duration(hours: 4))),
      );

      // The row is below the fold at this size and the sheet's ListView is lazy.
      await tester.scrollUntilVisible(
        find.text('17 items \u00b7 checked 4h ago'),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('17 items \u00b7 checked 4h ago'),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'the age is the fact this panel exists to show — never clipped',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a source with no checked_at says nothing about time', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      await openWith(tester, feedWithChecks());

      expect(find.text('17 items'), findsOneWidget);
      expect(
        find.textContaining('checked'),
        findsNothing,
        reason: 'never invent a check time the feed does not carry',
      );
    });

    testWidgets('the commission link uses the feed homepage when present', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);

      // The URL that actually reaches the launcher, not merely "some InkWell
      // has a callback": the pre-fix code hardcoded the same hand-written URL,
      // so anything weaker would pass with the feed ignored.
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        // Fail the launch so nothing leaves the test, and so the sheet's own
        // failure toast (which prints the same URL) is what renders.
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final now = DateTime.now();
      await openWith(
        tester,
        LiveFeed(
          generatedAt: now,
          revision: 1,
          updates: const [],
          sources: [
            SourceHealth(
              id: 'ssc',
              label: 'SSC',
              status: 'ok',
              rows: 17,
              // A moved site: the feed is the source of truth, the label is not.
              homepage: 'https://ssc.gov.in/new-home',
            ),
          ],
        ),
      );

      await tester.scrollUntilVisible(
        find.textContaining('SSC \u2014 Staff Selection'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(
        find.textContaining('SSC \u2014 Staff Selection'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('SSC \u2014 Staff Selection'));
      await tester.pumpAndSettle();

      expect(launched, [
        'https://ssc.gov.in/new-home',
      ], reason: 'the feed homepage must win over the hand-written fallback');
      expect(
        find.textContaining('https://ssc.gov.in/new-home'),
        findsOneWidget,
        reason: 'the failure toast names the URL that was actually tried',
      );
      expect(tester.takeException(), isNull);
    });
  });

  /// The About sheet was wrapped in ScaffoldMessenger + Scaffold as the modal
  /// route's *direct* child, so the Scaffold filled the route and the
  /// shrink-wrapped surface sat at the top edge (measured (1,1)-(392,766) at
  /// 393x852). It must be bottom-anchored like every other sheet.
  group('About sheet geometry', () {
    testWidgets('sits on the bottom edge, not the top', (tester) async {
      defaultPhone(tester);
      await openAbout(tester);

      // The decorated surface reaches the bottom edge; the sheet's own box sits
      // inside its 1px border. Measured after the fix: surface (0,85)-(393,852),
      // sheet (1,86)-(392,851). Before it was (1,1)-(392,766) — top-anchored.
      final surface = tester.getRect(
        find
            .ancestor(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(surface.bottom, closeTo(852, 0.5));
      expect(surface.top, closeTo(85, 1));

      final rect = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(
        rect.bottom,
        closeTo(852, 1),
        reason: 'the sheet must end at the screen edge, not 10% above it',
      );
      expect(
        rect.top,
        greaterThan(60),
        reason:
            'a sheet starting at the top edge means the route child was '
            'not shrink-wrapped (the barrier above it is then unreachable)',
      );
      // 0.9 of the screen, minus the 1px border on each side of the surface.
      expect(
        rect.top,
        closeTo(852 * 0.1, 3),
        reason: 'the surface must still open at its designed 90% extent',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the barrier above the sheet still dismisses it', (
      tester,
    ) async {
      defaultPhone(tester);
      await openAbout(tester);
      final rect = tester.getRect(find.byType(DraggableScrollableSheet));

      // The strip above the sheet is the barrier: tapping it closes the sheet.
      // When the surface sat at the top there was no such strip.
      await tester.tapAt(Offset(196, rect.top / 2));
      await tester.pumpAndSettle();

      expect(find.text('About ExamVault'), findsNothing);
    });
  });

  /// Section headings had `maxLines: 1` whenever there was no trailing widget,
  /// so "WHERE THE DATA COMES FROM" and "WHY WE NEVER HOST THE PDF" ellipsised
  /// mid-phrase at 320px @ 2.0x.
  group('Section headings at 320px @ 2.0x', () {
    for (final label in [
      'WHERE THE DATA COMES FROM',
      'WHY WE NEVER HOST THE PDF',
      'YOUR DATA',
    ]) {
      testWidgets('"$label" wraps instead of ellipsising', (tester) async {
        smallPhone(tester);
        await openAbout(tester);
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).last,
        );

        final text = tester.widget<Text>(find.text(label));
        expect(
          text.maxLines,
          2,
          reason:
              'a heading without a trailing action '
              'still has to wrap at large text',
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"$label" is still ellipsised at 320 @2.0x',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  /// A fast double tap used to stack a second sheet, because the modal barrier
  /// appears a frame after the open call. The bell got a synchronous guard for
  /// exactly this; About and the detail sheet had none.
  group('About opens once per double tap', () {
    testWidgets('two taps in the same frame open one sheet', (tester) async {
      final env = await MatrixEnv.open();
      addTearDown(env.close);
      await pumpMatrix(
        tester,
        const CommandCenterScreen(),
        matrixPoints.firstWhere((p) => p.name == 'default'),
        env: env,
      );

      final about = find.byIcon(Icons.info_outline_rounded);
      expect(about, findsOneWidget);

      // Invoking the button's callback twice without awaiting models the only
      // window a synchronous guard can close: two taps delivered before the
      // modal barrier exists. (Two `tester.tap` calls cannot reach the button —
      // the test binding builds the barrier for the first tap before the second
      // hit test runs, so that shape passes with or without a guard.)
      final button = tester.widget<InkWell>(
        find.ancestor(of: about, matching: find.byType(InkWell)).first,
      );
      button.onTap!();
      button.onTap!();
      await tester.pumpAndSettle();

      expect(
        find.text('About ExamVault'),
        findsOneWidget,
        reason: 'a second tap must not push a second About sheet',
      );
      await disposeMatrix(tester);
    });

    test(
      'the guard ignores a second call until the first sheet closes',
      () async {
        final guard = SheetOpenGuard();
        var opened = 0;
        final first = Completer<int>();
        final a = guard.run<int>(() {
          opened++;
          return first.future;
        });
        // The second call happens while the first sheet is still open.
        expect(
          await guard.run<int>(() async {
            opened++;
            return 2;
          }),
          isNull,
        );
        expect(opened, 1);
        expect(guard.isOpen, isTrue);

        first.complete(1);
        expect(await a, 1);
        expect(guard.isOpen, isFalse);

        // And the guard releases even when opening throws.
        await expectLater(
          guard.run<int>(() async => throw StateError('boom')),
          throwsStateError,
        );
        expect(guard.isOpen, isFalse);
        expect(
          await guard.run<int>(() async {
            opened++;
            return 3;
          }),
          3,
        );
        expect(opened, 2);
      },
    );
  });

  /// The detail sheet is reachable from two screens, and both stacked it on a
  /// fast double tap: the calendar's row card and the checker's "Notice
  /// details" action. The brief's shared guard was only applied to About.
  group('Exam detail sheet opens once per double tap', () {
    LiveUpdate datedUpdate() {
      final now = DateTime.now();
      return LiveUpdate(
        examId: 'exam_a',
        category: ExamCategory.ssc,
        examName: 'SSC CGL 2026',
        contextLine: 'Official notice',
        status: UpdateStatus.awaited,
        publishedAt: now.subtract(const Duration(days: 1)),
        examDate: now.add(const Duration(days: 9)),
      );
    }

    AdmitCard datedCard() => AdmitCard(
      id: 'card_a',
      examId: 'exam_a',
      category: ExamCategory.ssc,
      examName: 'SSC CGL 2026',
      conductingBody: 'Staff Selection Commission',
      examCode: 'CGL',
      rollNumber: '2201098765',
      registrationId: '',
      dobOrPortalPassword: '',
      centerCode: '',
      centerAddress: '',
      gate: '',
      reportBy: '',
      examDate: DateTime.now().add(const Duration(days: 9)),
      shift: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    ProviderContainer container({LiveUpdate? selected}) {
      final c = ProviderContainer(
        overrides: [
          settingsBoxProvider.overrideWithValue(settingsBox),
          liveFeedProvider.overrideWith(
            () => _StaticLiveFeed(
              LiveFeedSnapshot(
                feed: LiveFeed(
                  generatedAt: DateTime.now(),
                  revision: 1,
                  updates: [datedUpdate()],
                ),
                source: FeedSource.network,
                fetchedAt: DateTime.now(),
              ),
            ),
          ),
          admitCardsProvider.overrideWith(() => _StaticCards([datedCard()])),
        ],
      );
      addTearDown(c.dispose);
      if (selected != null) {
        c.read(resultExamIdProvider.notifier).select(selected);
      }
      return c;
    }

    /// Two taps delivered before the modal barrier exists — the only window a
    /// synchronous guard can close. `tester.tap` twice cannot reach the trigger:
    /// the binding builds the first tap's barrier before the second hit test.
    Future<void> doubleTap(WidgetTester tester, VoidCallback? onTap) async {
      expect(onTap, isNotNull);
      onTap!();
      onTap();
      await tester.pumpAndSettle();
    }

    testWidgets('the calendar row opens one sheet', (tester) async {
      final c = container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ExamCalendarScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.text('SSC CGL 2026');
      expect(row, findsWidgets);
      final ink = tester.widget<InkWell>(
        find.ancestor(of: row.first, matching: find.byType(InkWell)).first,
      );
      await doubleTap(tester, ink.onTap);

      expect(
        find.byType(DraggableScrollableSheet),
        findsOneWidget,
        reason: 'a second tap must not stack a second detail sheet',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the checker\'s "Notice details" opens one sheet', (
      tester,
    ) async {
      final update = datedUpdate();
      final c = container(selected: update);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const InstantResultCheckerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final action = find.byWidgetPredicate(
        (w) => w is EvTextAction && w.label == 'Notice details',
      );
      expect(action, findsOneWidget);
      await doubleTap(tester, tester.widget<EvTextAction>(action).onPressed);

      expect(
        find.byType(DraggableScrollableSheet),
        findsOneWidget,
        reason: 'a second tap must not stack a second detail sheet',
      );
      expect(tester.takeException(), isNull);
    });
  });

  /// The vault form has five call sites, so the guard lives inside
  /// `showVaultFormSheet` rather than at each one: two twelve-field credential
  /// forms, each with its own discard guard, is a defect from any caller.
  group('Vault form opens once per double tap', () {
    testWidgets('two taps in the same frame open one form', (tester) async {
      final env = await MatrixEnv.open();
      addTearDown(env.close);
      await pumpMatrix(
        tester,
        const CommandCenterScreen(),
        matrixPoints.firstWhere((p) => p.name == 'default'),
        env: env,
      );

      final add = find.byWidgetPredicate(
        (w) => w is EvTextAction && w.label == 'Add',
      );
      expect(add, findsOneWidget);
      final onPressed = tester.widget<EvTextAction>(add).onPressed;

      onPressed!();
      onPressed();
      await tester.pumpAndSettle();

      // Exactly one form: each form renders one "Save to vault" primary button
      // and one of each labelled field.
      expect(
        find.byWidgetPredicate(
          (w) => w is EvPrimaryButton && w.label == 'Save to vault',
        ),
        findsOneWidget,
        reason: 'a second tap must not stack a second credential form',
      );
      expect(find.byType(TextFormField), findsWidgets);
      expect(tester.takeException(), isNull);
      await disposeMatrix(tester);
    });
  });

  /// "Delete all data" was documented in two `wipe()` doc comments with no
  /// caller and no UI.
  group('Delete all data', () {
    late FakeVaultStore store;
    late _SpyPush push;

    // In-memory boxes for this group. The file-backed pair opened in the outer
    // setUp cannot be written from inside `testWidgets`: Hive's disk I/O
    // completes on the real event loop, which the fake test clock never drains,
    // so the wipe's `delete()` calls would hang the sheet on "Deleting…".
    setUp(() async {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      settingsBox = await Hive.openBox<dynamic>(
        'wipe_s$stamp',
        bytes: Uint8List(0),
      );
      cacheBox = await Hive.openBox<dynamic>(
        'wipe_c$stamp',
        bytes: Uint8List(0),
      );
      store = FakeVaultStore(
        seed: {
          '__index': 'card_a',
          'card_a': AdmitCardCodec.encode(
            AdmitCard(
              id: 'card_a',
              examId: 'ssc_cgl_2026',
              category: ExamCategory.ssc,
              examName: 'SSC CGL Tier-1 2026',
              conductingBody: 'Staff Selection Commission',
              examCode: 'CGL',
              rollNumber: '2201098765',
              registrationId: 'SSC-CHSL-26-441122',
              dobOrPortalPassword: '11/05/1998',
              centerCode: 'DL-07-2210',
              centerAddress: 'Sector 9, Rohini',
              gate: 'Gate 2',
              reportBy: '08:00 AM',
              examDate: DateTime(2026, 12, 1),
              shift: '10:00 AM',
              createdAt: DateTime(2026, 11, 1),
              updatedAt: DateTime(2026, 11, 1),
            ),
          ),
        },
      );
      push = _SpyPush();
    });

    Widget dataHost() => ProviderScope(
      overrides: [
        settingsBoxProvider.overrideWithValue(settingsBox),
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: store),
        ),
        cdnClientProvider.overrideWithValue(
          CdnClient(
            cache: cacheBox,
            client: MockClient((_) async => http.Response('', 404)),
            baseUrl: 'https://cdn.test',
          ),
        ),
        pushServiceProvider.overrideWithValue(push),
        liveFeedProvider.overrideWith(
          () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: LiveFeed(
                generatedAt: DateTime.now(),
                revision: 1,
                updates: const [],
                sources: const [
                  SourceHealth(
                    id: 'ssc',
                    label: 'Staff Selection Commission',
                    status: 'ok',
                    rows: 17,
                  ),
                ],
              ),
              source: FeedSource.network,
              fetchedAt: DateTime.now(),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final cards = ref.watch(admitCardsProvider);
              return Column(
                children: [
                  Text('cards: ${cards.value?.length ?? -1}'),
                  Text(
                    'categories: '
                    '${ref.watch(followedCategoriesProvider).length}',
                  ),
                  TextButton(
                    onPressed: () => showAboutSheet(context),
                    child: const Text('open about'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    Future<void> seedEverything() async {
      await settingsBox.put('theme', 'light');
      await settingsBox.put('exam_alerts', ['exam_1']);
      await settingsBox.put('alerts_seen_at', '2026-11-15T10:00:00Z');
      await settingsBox.put('followed_categories', ['ssc']);
      await cacheBox.put('feed', {'revision': 1, 'updates': <dynamic>[]});
      await cacheBox.put('https://cdn.test/v1/x.gz', {
        'b': Uint8List(2),
        't': DateTime.now().millisecondsSinceEpoch,
      });
    }

    testWidgets('wipes vault, settings, cache and push topics', (tester) async {
      await seedEverything();
      await tester.pumpWidget(dataHost());
      await tester.pumpAndSettle();
      expect(find.text('cards: 1'), findsOneWidget);

      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      // The confirmation states exactly what happens, including that it cannot
      // be undone.
      expect(find.text('Delete all data?'), findsOneWidget);
      expect(
        find.textContaining(
          'This removes every admit card and every setting on this device. It '
          'cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Vault.
      expect(store.raw, isEmpty);
      // Settings.
      for (final key in settingsKeys) {
        expect(settingsBox.get(key), isNull, reason: '$key survived the wipe');
      }
      // Cached feed + HTTP cache.
      expect(cacheBox.isEmpty, isTrue, reason: 'the HTTP cache survived');
      // Push subscriptions — a deleted setting in every sense the user cares
      // about: leaving them live keeps pinging them about data they deleted.
      expect(push.unsubscribed, 1);
      expect(
        push.initialised,
        1,
        reason:
            'unsubscribeAll is a no-op while the provider is still disabled, so '
            'a wipe inside boot\'s init window must await it first',
      );
      expect(
        push.clearedExamIds,
        {'exam_1'},
        reason:
            'the per-exam bells must be named before the settings that hold '
            'them are gone, or OneSignal keeps those tags forever',
      );
      // …and the categories are re-synced to the post-wipe default, because the
      // picker now reads as all five. Five selected chips over zero topics is
      // the same "UI claims a subscription the backend does not have" lie.
      expect(push.topics, ExamCategory.values.toSet());
      // And the UI emptied without a restart.
      expect(find.text('cards: 0'), findsOneWidget);
      expect(
        find.text('Your admit cards and settings were deleted.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    /// The picker reads as the fresh-install default once `followed_categories`
    /// is deleted, so the backend has to be re-synced in the same session.
    /// Otherwise About shows five selected categories over a device with zero
    /// subscriptions until the next launch — the lie this task removes.
    testWidgets('the picker and the backend agree after the wipe', (
      tester,
    ) async {
      await seedEverything();
      await tester.pumpWidget(dataHost());
      await tester.pumpAndSettle();
      // Seeded to SSC only, so the reset to five is observable.
      expect(find.text('categories: 1'), findsOneWidget);

      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('categories: 5'), findsOneWidget);
      expect(
        push.topics,
        ExamCategory.values.toSet(),
        reason: 'the backend must be re-synced to what the picker now shows',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing push unsubscribe still completes the wipe', (
      tester,
    ) async {
      await seedEverything();
      push.throwOnUnsubscribe = true;
      await tester.pumpWidget(dataHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // The local data is what the user asked to remove, and it is gone.
      expect(store.raw, isEmpty);
      expect(settingsBox.get('theme'), isNull);
      expect(find.text('cards: 0'), findsOneWidget);
      expect(
        find.text('Your admit cards and settings were deleted.'),
        findsOneWidget,
        reason: 'a push failure must not report the wipe as unsuccessful',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Keep my data leaves everything in place', (tester) async {
      await seedEverything();
      await tester.pumpWidget(dataHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my data'));
      await tester.pumpAndSettle();

      expect(store.raw, isNotEmpty);
      expect(settingsBox.get('theme'), 'light');
      expect(find.text('cards: 1'), findsOneWidget);
      expect(push.unsubscribed, 0);
    });

    /// A hung network unsubscribe must not eat the widget's whole budget and
    /// then report failure for a local wipe that fully succeeded.
    testWidgets('a hanging push unsubscribe does not fail the wipe', (
      tester,
    ) async {
      await seedEverything();
      push.hangOnUnsubscribe = true;
      await tester.pumpWidget(dataHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));

      // The push step's own 2 s ceiling, well inside the 15 s the button holds.
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(push.unsubscribed, 1);
      expect(store.raw, isEmpty);
      expect(find.text('cards: 0'), findsOneWidget);
      expect(
        find.text('Your admit cards and settings were deleted.'),
        findsOneWidget,
        reason: 'a hung push call is not a failed wipe',
      );
      expect(
        find.text('Could not delete everything. Try again.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    /// The dialog at the mandated floor: measured 320x568 @2.0x, both actions
    /// hit-testable inside the viewport. This locks in that measurement.
    testWidgets('the confirm dialog fits and is usable at 320x568 @2.0x', (
      tester,
    ) async {
      smallPhone(tester);
      await seedEverything();
      await tester.pumpWidget(dataHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      expect(find.text('Delete all data?'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final keep = tester.getRect(find.text('Keep my data'));
      final delete = tester.getRect(find.text('Delete'));
      expect(find.text('Keep my data').hitTestable(), findsOneWidget);
      expect(find.text('Delete').hitTestable(), findsOneWidget);
      // Both actions inside the 320x568 viewport, not clipped off its bottom.
      for (final rect in [keep, delete]) {
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(568));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      // The body still reads in full: `scrollable: true` must not truncate it.
      expect(find.textContaining('It cannot be undone.'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 14 — the signals that existed but could not be read.
  // ---------------------------------------------------------------------------

  /// The radar's badge counts rows published since the inbox was last opened,
  /// and the tab bar shows a dot — but the list itself drew no boundary, so a
  /// student returning after a week saw 40 rows in publication order with no
  /// way to tell which 6 the dot was counting.
  ///
  /// The line marks *recency* (everything above arrived since the last visit),
  /// not the badge's status filter. See `radarNewBoundary` for why the two are
  /// deliberately not the same number; the mixed-status test below pins the
  /// relationship instead of pretending they are equal.
  group('Radar new/earlier boundary', () {
    /// Newest first, like the real feed: `LiveFeedDto.decode` sorts descending,
    /// so the unseen rows are a block at the top and the boundary is below it.
    List<LiveUpdate> rows(int count) {
      final now = DateTime.now();
      return [
        for (var i = 0; i < count; i++)
          LiveUpdate(
            examId: 'exam_$i',
            category: ExamCategory.ssc,
            examName: 'Radar row $i',
            contextLine: 'Official notice',
            status: UpdateStatus.resultOut,
            publishedAt: now.subtract(Duration(hours: i)),
          ),
      ];
    }

    Widget radarHost(List<LiveUpdate> updates) => ProviderScope(
      overrides: [
        settingsBoxProvider.overrideWithValue(settingsBox),
        liveFeedProvider.overrideWith(
          () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: LiveFeed(
                generatedAt: DateTime.now(),
                revision: 1,
                updates: updates,
              ),
              source: FeedSource.network,
              fetchedAt: DateTime.now(),
            ),
          ),
        ),
        admitCardsProvider.overrideWith(() => _StaticCards(const [])),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const CommandCenterScreen(),
      ),
    );

    /// Tall enough that the whole radar is laid out: a position assertion needs
    /// the rows on screen, not sitting in a sliver's cache.
    Future<void> mountRadar(
      WidgetTester tester,
      List<LiveUpdate> updates,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(radarHost(updates));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.text('Command Center')));

    test('the boundary is the first row at or before the seen instant', () {
      final feed = rows(6);
      final seen = DateTime.now().subtract(
        const Duration(hours: 3, minutes: 30),
      );
      // Rows 0-3 were published after the visit; row 4 is the first one seen,
      // so the divider belongs immediately above it.
      expect(radarNewBoundary(feed, seen), 4);
    });

    test('no boundary when every row has been seen', () {
      final feed = rows(6);
      expect(
        radarNewBoundary(feed, DateTime.now().add(const Duration(minutes: 1))),
        -1,
      );
    });

    test('no boundary on a fresh install (epoch seen instant)', () {
      expect(
        radarNewBoundary(rows(6), DateTime.fromMillisecondsSinceEpoch(0)),
        -1,
      );
    });

    test('no boundary when every row is new', () {
      // A visit a month ago: nothing in the feed predates it, so a line at the
      // bottom of the list would introduce nothing.
      expect(
        radarNewBoundary(
          rows(6),
          DateTime.now().subtract(const Duration(days: 30)),
        ),
        -1,
      );
    });

    testWidgets('the boundary sits between the last unseen and first seen row', (
      tester,
    ) async {
      // A Hive write completes on the real event loop, which the widget test's
      // fake clock never advances; `runAsync` is the only way to await one.
      await tester.runAsync(
        () => settingsBox.put(
          alertsSeenSettingKey,
          DateTime.now()
              .subtract(const Duration(hours: 3, minutes: 30))
              .toIso8601String(),
        ),
      );
      await mountRadar(tester, rows(6));

      // The visible word names the block the line introduces: everything below
      // it predates the last visit. "NEW" here would have read as "the new part
      // starts below this line", which is the opposite of the truth.
      expect(find.text('EARLIER'), findsOneWidget);
      final divider = tester.getRect(find.text('EARLIER'));

      // Four rows arrived since the visit and all six are `resultOut`, so in
      // *this* fixture the rows above the line and the badge agree. The
      // mixed-status test below shows where that equality stops holding.
      final above = tester
          .widgetList(find.byType(LiveRadarTile))
          .where(
            (tile) => tester.getRect(find.byWidget(tile)).bottom <= divider.top,
          )
          .length;
      expect(above, 4);
      expect(containerOf(tester).read(liveRadarBadgeProvider), 4);

      // The row above stays above, the row below stays below.
      expect(
        tester.getRect(find.text('Radar row 3')).bottom,
        lessThan(divider.top),
      );
      expect(
        tester.getRect(find.text('Radar row 4')).top,
        greaterThan(divider.bottom),
      );
      expectClean(tester);
    });

    testWidgets('no divider when everything has been seen', (tester) async {
      await tester.runAsync(
        () => settingsBox.put(
          alertsSeenSettingKey,
          DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
        ),
      );
      await mountRadar(tester, rows(6));

      expect(find.text('EARLIER'), findsNothing);
      expect(containerOf(tester).read(liveRadarBadgeProvider), 0);
    });

    testWidgets('no divider on a fresh install', (tester) async {
      // No `alerts_seen_at` in the box: AlertsSeenNotifier falls back to the
      // epoch and every row is new, so a line would mark the entire list.
      await mountRadar(tester, rows(6));

      expect(find.text('EARLIER'), findsNothing);
      expect(
        containerOf(tester).read(liveRadarBadgeProvider),
        6,
        reason:
            'the rows really are new; the line is suppressed because a line '
            'above the first row says nothing',
      );
    });

    testWidgets('no divider when every row arrived since the last visit', (
      tester,
    ) async {
      await tester.runAsync(
        () => settingsBox.put(
          alertsSeenSettingKey,
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
        ),
      );
      await mountRadar(tester, rows(6));

      expect(find.text('EARLIER'), findsNothing);
    });

    /// The line counts every arrival; the badge counts only the statuses that
    /// are worth a notification. Those are different questions, and this test
    /// pins the difference rather than asserting an equality that only holds
    /// when every row happens to be `resultOut`.
    testWidgets('a mixed-status feed keeps the line at the arrival boundary', (
      tester,
    ) async {
      final now = DateTime.now();
      // Newest first. Two rows arrived after the visit; only the `resultOut`
      // one is something the badge counts.
      final mixed = [
        LiveUpdate(
          examId: 'exam_new_vacancy',
          category: ExamCategory.ssc,
          examName: 'New vacancy row',
          contextLine: 'Official notice',
          status: UpdateStatus.notification,
          publishedAt: now.subtract(const Duration(hours: 1)),
        ),
        LiveUpdate(
          examId: 'exam_new_result',
          category: ExamCategory.ssc,
          examName: 'New result row',
          contextLine: 'Official notice',
          status: UpdateStatus.resultOut,
          publishedAt: now.subtract(const Duration(hours: 2)),
        ),
        LiveUpdate(
          examId: 'exam_seen_result',
          category: ExamCategory.ssc,
          examName: 'Seen result row',
          contextLine: 'Official notice',
          status: UpdateStatus.resultOut,
          publishedAt: now.subtract(const Duration(hours: 20)),
        ),
      ];
      await tester.runAsync(
        () => settingsBox.put(
          alertsSeenSettingKey,
          now.subtract(const Duration(hours: 10)).toIso8601String(),
        ),
      );
      await mountRadar(tester, mixed);

      final divider = tester.getRect(find.text('EARLIER'));

      // The line sits below *both* new rows — the notification one too. Cutting
      // it by status would have to place it between the two new rows, leaving
      // the `notification` row under a line labelled EARLIER even though it
      // arrived after the last visit. That is the failure this design avoids.
      expect(
        tester.getRect(find.text('New vacancy row')).bottom,
        lessThan(divider.top),
      );
      expect(
        tester.getRect(find.text('New result row')).bottom,
        lessThan(divider.top),
      );
      expect(
        tester.getRect(find.text('Seen result row')).top,
        greaterThan(divider.bottom),
      );

      // ...and the badge counts only the actionable arrival: one, not two.
      expect(containerOf(tester).read(liveRadarBadgeProvider), 1);
      expectClean(tester);
    });

    /// The extreme of the same gap: an arrival the badge ignores entirely. The
    /// line still draws, because "this arrived since you last looked" is true
    /// and useful even when nothing needs the student's attention. The dot
    /// stays silent, which is also true.
    testWidgets('an arrival the badge ignores still gets a boundary', (
      tester,
    ) async {
      final now = DateTime.now();
      final mixed = [
        LiveUpdate(
          examId: 'exam_new_vacancy',
          category: ExamCategory.ssc,
          examName: 'New vacancy row',
          contextLine: 'Official notice',
          status: UpdateStatus.notification,
          publishedAt: now.subtract(const Duration(hours: 1)),
        ),
        LiveUpdate(
          examId: 'exam_seen_result',
          category: ExamCategory.ssc,
          examName: 'Seen result row',
          contextLine: 'Official notice',
          status: UpdateStatus.resultOut,
          publishedAt: now.subtract(const Duration(hours: 20)),
        ),
      ];
      await tester.runAsync(
        () => settingsBox.put(
          alertsSeenSettingKey,
          now.subtract(const Duration(hours: 10)).toIso8601String(),
        ),
      );
      await mountRadar(tester, mixed);

      expect(find.text('EARLIER'), findsOneWidget);
      expect(containerOf(tester).read(liveRadarBadgeProvider), 0);
      expectClean(tester);
    });
  });

  /// The radar header printed "3 of 34" while a search ran, but the vault
  /// header printed only the unfiltered "N saved": with a query matching one of
  /// five cards it claimed five while the list showed one, and no empty state
  /// appeared because the list was not empty.
  group('Vault header while a filter narrows it', () {
    AdmitCard card(
      String id,
      String examName,
      String examCode, {
      ExamCategory category = ExamCategory.ssc,
    }) => AdmitCard(
      id: id,
      examId: 'exam_$id',
      category: category,
      examName: examName,
      conductingBody: 'Staff Selection Commission',
      examCode: examCode,
      rollNumber: '2201098765',
      registrationId: '',
      dobOrPortalPassword: '',
      centerCode: '',
      centerAddress: '',
      gate: '',
      reportBy: '',
      examDate: DateTime.now().add(const Duration(days: 9)),
      shift: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final cards = [
      card('c0', 'SSC CGL Tier-1 2026', 'CGL-T1'),
      card('c1', 'SSC CGL Tier-2 2026', 'CGL-T2'),
      card('c2', 'SSC CHSL 2026', 'CHSL'),
      card('c3', 'IBPS PO 2026', 'PO', category: ExamCategory.banking),
      card('c4', 'RRB NTPC 2026', 'NTPC', category: ExamCategory.railways),
    ];

    Widget vaultHost() => ProviderScope(
      overrides: [
        settingsBoxProvider.overrideWithValue(settingsBox),
        liveFeedProvider.overrideWith(
          () => _StaticLiveFeed(
            LiveFeedSnapshot(
              feed: LiveFeed.empty,
              source: FeedSource.none,
              fetchedAt: DateTime.now(),
            ),
          ),
        ),
        admitCardsProvider.overrideWith(() => _StaticCards(cards)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const CommandCenterScreen(),
      ),
    );

    Future<void> mountHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(vaultHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.text('Command Center')));

    testWidgets('a query prints the filtered fraction, not the vault size', (
      tester,
    ) async {
      await mountHome(tester);
      expect(find.text('5 saved'), findsOneWidget);

      containerOf(tester).read(searchQueryProvider.notifier).set('cgl');
      await tester.pump();

      expect(find.text('2 of 5'), findsOneWidget);
      expect(
        find.text('5 saved'),
        findsNothing,
        reason: 'the header must not claim a vault the list is not showing',
      );
      // The fraction is honest: two cards, two rendered passes.
      expect(find.byType(WalletPassCard), findsNWidgets(2));
      expectClean(tester);
    });

    testWidgets('a category chip prints the filtered fraction too', (
      tester,
    ) async {
      await mountHome(tester);

      containerOf(
        tester,
      ).read(categoryFilterProvider.notifier).select(ExamCategory.banking);
      await tester.pump();

      expect(find.text('1 of 5'), findsOneWidget);
      expect(find.byType(WalletPassCard), findsOneWidget);
      expectClean(tester);
    });

    testWidgets('with nothing filtered the wording is unchanged', (
      tester,
    ) async {
      await mountHome(tester);

      expect(find.text('5 saved'), findsOneWidget);
      expect(find.textContaining(' of 5'), findsNothing);
      // The Add action beside the count is untouched.
      expect(find.text('Add'), findsOneWidget);
    });
  });

  /// The layout floor: the new boundary line and the new group headings at the
  /// smallest supported phone with the largest supported text.
  group('Task 14 at 320x568 @ 2.0x', () {
    testWidgets('the radar boundary does not overflow', (tester) async {
      final env = (await tester.runAsync(MatrixEnv.open))!;
      // The matrix feed is published 1h, 8h, 15h and 22h ago, so a visit 10
      // hours ago leaves rows 0-1 new and the line immediately above row 2.
      await tester.runAsync(
        () => env.settingsBox.put(
          alertsSeenSettingKey,
          DateTime.now().subtract(const Duration(hours: 10)).toIso8601String(),
        ),
      );
      await pumpMatrix(
        tester,
        const CommandCenterScreen(),
        matrixPoints[5],
        env: env,
      );
      // The mock feed only lands on the real event loop (see search_test).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
        find.text('EARLIER'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('EARLIER'), findsOneWidget);
      expectClean(tester, because: 'the radar boundary at 320x568 @ 2.0x');
    });

    testWidgets('the grouped Dates list does not overflow', (tester) async {
      final env = await tester.runAsync(MatrixEnv.open);
      await pumpMatrix(
        tester,
        const ExamCalendarScreen(),
        matrixPoints[5],
        env: env!,
        cards: [
          matrixCard(daysFromNow: 2),
          matrixCard(
            id: 'b',
            daysFromNow: 10,
            examName: 'UPSC Civil Services (Preliminary) Examination 2027',
            category: ExamCategory.upsc,
          ),
          matrixCard(
            id: 'c',
            daysFromNow: 40,
            examName: 'RRB NTPC CBT-2 2026',
            category: ExamCategory.railways,
          ),
        ],
      );

      expect(find.text('NEXT 7 DAYS'), findsOneWidget);
      expectClean(tester, because: 'the grouped Dates list at 320x568 @ 2.0x');

      // The last heading is two screens down at this size; it must render as
      // cleanly as the first.
      await tester.scrollUntilVisible(
        find.text('LATER'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('LATER'), findsOneWidget);
      expectClean(tester, because: 'the last group at 320x568 @ 2.0x');
    });
  });

  /// The About sheet told the user the push token was used "for the categories
  /// you follow" while `_bootPush` subscribed every device to all five. These
  /// pin the control that makes the sentence true, and its two honest absences:
  /// a build that cannot deliver, and a student who turned everything off.
  group('About notification categories', () {
    // In-memory box for this group: the file-backed pair opened in the outer
    // setUp cannot be written from inside `testWidgets` — Hive's disk I/O
    // completes on the real event loop, which the fake test clock never drains,
    // so the chip's `put` would hang and the re-sync would never run.
    setUp(() async {
      settingsBox = await Hive.openBox<dynamic>(
        'notif_s${DateTime.now().microsecondsSinceEpoch}',
        bytes: Uint8List(0),
      );
    });

    Future<void> openWith(WidgetTester tester, PushService push) async {
      await tester.pumpWidget(host(push: push));
      await tester.pump();
      await tester.tap(find.text('open about'));
      await tester.pumpAndSettle();
    }

    /// The section sits below "What we store" and the sheet's ListView is lazy.
    Future<void> scrollToSection(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('NOTIFICATIONS'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('NOTIFICATIONS'));
      await tester.pumpAndSettle();
    }

    List<EvChip> categoryChips(WidgetTester tester) => tester
        .widgetList<EvChip>(find.byType(EvChip))
        .where((c) => ExamCategory.values.any((e) => e.label == c.label))
        .toList();

    testWidgets('one chip per category, all selected by default', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      await openWith(tester, _SpyPush(canDeliverValue: true));
      await scrollToSection(tester);

      final chips = categoryChips(tester);
      expect(
        chips.map((c) => c.label),
        ExamCategory.values.map((e) => e.label),
        reason: 'every category the backend can deliver needs a switch',
      );
      expect(
        chips.every((c) => c.selected),
        isTrue,
        reason:
            'an absent key means the user never chose — all five, as before',
      );
      // The one-line explanation of what the token is for.
      expect(
        find.textContaining('push token is subscribed only to the categories'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden, with the reason, when push cannot deliver', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      // The default double reports `canDeliver == false`, which is what a web
      // build or a build without push credentials reports.
      await openWith(tester, _SpyPush());

      await tester.scrollUntilVisible(
        find.textContaining('cannot deliver push notifications'),
        300,
        scrollable: find.byType(Scrollable).last,
      );

      expect(
        find.text('NOTIFICATIONS'),
        findsNothing,
        reason: 'a switch that cannot deliver anything would be a lie',
      );
      expect(categoryChips(tester), isEmpty);
      expect(
        find.textContaining('cannot deliver push notifications'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out at 320x568 @ 2.0x with push enabled', (tester) async {
      // The section only exists in a build that can deliver, so the 2.0x floor
      // has to be exercised with the chips present — the default host hides it.
      smallPhone(tester);
      await openWith(tester, _SpyPush(canDeliverValue: true));
      await scrollToSection(tester);
      await tester.ensureVisible(find.text('Railways'));
      await tester.pumpAndSettle();

      expect(find.text('Railways').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty set says out loud that no alerts will arrive', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      await settingsBox.put('followed_categories', <String>[]);
      await openWith(tester, _SpyPush(canDeliverValue: true));
      await scrollToSection(tester);

      expect(
        find.text('No categories — you will not get category alerts.'),
        findsOneWidget,
        reason: 'five unselected chips alone do not say "you will get nothing"',
      );
      expect(categoryChips(tester).every((c) => !c.selected), isTrue);
      expect(tester.takeException(), isNull);
    });

    /// The in-app policy told every reader to "Pick those categories in About →
    /// Notifications" — including builds where that section is hidden.
    testWidgets('the policy only points at the picker when it exists', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);

      Future<void> openPolicy(PushService push) async {
        await openWith(tester, push);
        await tester.scrollUntilVisible(
          find.text('Read the privacy policy'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(find.text('Read the privacy policy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Read the privacy policy'));
        await tester.pumpAndSettle();
      }

      await openPolicy(_SpyPush());
      await tester.scrollUntilVisible(
        find.textContaining('no category picker here'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Pick those categories'), findsNothing);

      await openPolicy(_SpyPush(canDeliverValue: true));
      await tester.scrollUntilVisible(
        find.textContaining('Pick those categories'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('no category picker here'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two taps in the same frame open one policy sheet', (
      tester,
    ) async {
      // The modal barrier appears a frame after showModalBottomSheet is called,
      // so two taps delivered before it exists stacked two policy sheets — the
      // same defect the About button, the delete dialog and the vault form were
      // fixed for, and this was the one sheet still without a guard.
      smallPhone(tester, textScale: 1.0);
      await openWith(tester, _SpyPush(canDeliverValue: true));
      await tester.scrollUntilVisible(
        find.text('Read the privacy policy'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Read the privacy policy'));
      await tester.pumpAndSettle();

      // Invoking the row's callback twice without awaiting models the only
      // window a synchronous guard can close: two taps delivered before the
      // modal barrier exists. (Two `tester.tap` calls cannot reach the row — the
      // binding builds the barrier for the first tap before the second hit test
      // runs, so that shape passes with or without a guard.)
      final row = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Read the privacy policy'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      row.onTap!();
      row.onTap!();
      await tester.pumpAndSettle();

      expect(
        find.text('No account, no profile'),
        findsOneWidget,
        reason: 'two stacked policy sheets would render this section twice',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a tap persists the choice and re-syncs push with the new set',
      (tester) async {
        smallPhone(tester, textScale: 1.0);
        final push = _SpyPush(canDeliverValue: true);
        await openWith(tester, push);
        await scrollToSection(tester);
        await tester.ensureVisible(find.text('Railways'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Railways'));
        await tester.pumpAndSettle();

        expect(
          settingsBox.get('followed_categories'),
          // Exact list, not `isNot(contains(...))`: the negative form is also
          // satisfied by a missing key, i.e. by a write that never happened.
          ['ssc', 'upsc', 'banking', 'state_psc'],
          reason: 'the toggle must reach the settings box, not just the chip',
        );
        expect(
          push.topics,
          {
            ExamCategory.ssc,
            ExamCategory.upsc,
            ExamCategory.banking,
            ExamCategory.statePsc,
          },
          reason:
              'push must be reconciled against the persisted set immediately',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

/// A `PushService` that records `unsubscribeAll()` without touching a backend.
///
/// `unsubscribeAll` is the one call delete-all makes into push; a fake that
/// counted it is the whole assertion, and the throwing variant proves the wipe
/// does not depend on the network.
class _SpyPush extends PushService {
  _SpyPush({this.canDeliverValue = false});

  /// Whether this double pretends a push can arrive. The About picker is
  /// hidden when it cannot; the delete-all tests leave it false.
  final bool canDeliverValue;

  int unsubscribed = 0;
  bool throwOnUnsubscribe = false;

  /// How many times the wipe asked for the provider to be ready. A wipe that
  /// does not initialise first can find `PushProvider.disabled` and drop
  /// nothing at all, so this is part of the contract.
  int initialised = 0;

  @override
  Future<PushProvider> initialise() async {
    initialised++;
    return PushProvider.fcm;
  }

  /// Models a network call that never returns. `deleteAll` must bound it itself
  /// rather than consuming the caller's whole budget.
  bool hangOnUnsubscribe = false;

  /// The last set handed to `syncTopics`, so a chip tap and the post-wipe
  /// re-sync can be proved to reconcile push rather than merely repaint.
  Set<ExamCategory>? topics;

  /// The per-exam bell ids `unsubscribeAll` was told to clear. On OneSignal the
  /// ids are the only way to reach those tags, so the caller must pass them.
  Set<String>? clearedExamIds;

  @override
  bool get canDeliver => canDeliverValue;

  @override
  Future<void> syncTopics(Set<ExamCategory> categories) async {
    topics = categories;
  }

  @override
  Future<void> unsubscribeAll({Set<String> examIds = const {}}) async {
    unsubscribed++;
    clearedExamIds = examIds;
    if (hangOnUnsubscribe) return Completer<void>().future;
    if (throwOnUnsubscribe) throw StateError('push backend unavailable');
  }
}

/// A vault notifier with a fixed card list.
class _StaticCards extends AdmitCardsNotifier {
  _StaticCards(this.cards);

  final List<AdmitCard> cards;

  @override
  Future<List<AdmitCard>> build() async => cards;
}

class _StaticLiveFeed extends LiveFeedNotifier {
  _StaticLiveFeed(this.snapshot);

  final LiveFeedSnapshot snapshot;

  @override
  Future<LiveFeedSnapshot> build() async => snapshot;
}

/// A background refresh whose completion the test drives, one call at a time.
class _RefreshGate {
  final List<Completer<LiveFeedSnapshot>> _pending = [];

  /// How many refreshes have been started. `build()` starts one per rebuild, so
  /// this is also the count of provider reads.
  int started = 0;

  Future<LiveFeedSnapshot> next() {
    final completer = Completer<LiveFeedSnapshot>();
    _pending.add(completer);
    started++;
    return completer.future;
  }

  void answer(LiveFeedSnapshot snapshot) =>
      _pending.removeAt(0).complete(snapshot);
}

/// Mirrors `LiveFeedNotifier.build()` exactly — the shape no other double here
/// reproduces.
///
/// Production answers from the cache (or the `FeedSource.none` sentinel) on the
/// first frame and refreshes with `unawaited(...)`, so the provider is
/// `AsyncData` for the entire first fetch. A double that injects
/// `AsyncLoading` cannot see that window, and that blind spot is how a cold
/// start on a dead edge shipped as "Nothing needs your attention.".
class _ProdLikeLiveFeed extends LiveFeedNotifier {
  _ProdLikeLiveFeed({required this.gate});

  final _RefreshGate gate;

  @override
  Future<LiveFeedSnapshot> build() async {
    unawaited(_refreshInto());
    return LiveFeedSnapshot(
      feed: LiveFeed.empty,
      source: FeedSource.none,
      fetchedAt: DateTime.now(),
    );
  }

  Future<void> _refreshInto() async {
    final snapshot = await gate.next();
    if (!ref.mounted) return;
    state = AsyncData(snapshot);
  }
}

/// A feed notifier whose load never completes until the test says so.
///
/// The literal "hanging HTTP client" recipe cannot hold `liveFeedProvider` in
/// loading: `LiveFeedNotifier.build` answers from the repository cache without
/// awaiting the network, so the provider resolves within a microtask even while
/// the fetch hangs. The loading state is injected directly instead.
class _GatedLiveFeed extends LiveFeedNotifier {
  _GatedLiveFeed(this.gate);

  final Completer<LiveFeedSnapshot> gate;

  @override
  Future<LiveFeedSnapshot> build() => gate.future;
}

/// Counts how many times the provider was built, so a test can prove that
/// Retry really invalidated it instead of merely repainting the same state.
class _ReadCounter {
  int count = 0;

  /// When set, the next build fails. Mutable on purpose: `invalidate` re-runs
  /// `build()` on the *same* notifier instance, so a final field could not flip.
  bool fail = false;
}

class _CountingLiveFeed extends LiveFeedNotifier {
  _CountingLiveFeed(this.reads, this.snapshot);

  final _ReadCounter reads;
  final LiveFeedSnapshot snapshot;

  @override
  Future<LiveFeedSnapshot> build() async {
    reads.count++;
    if (reads.fail) throw StateError('the feed store is unavailable');
    return snapshot;
  }
}

/// A settings box whose every write fails; reads answer from a fixed snapshot
/// of what "the last successful launch" persisted.
class _FailingSettingsBox implements Box<dynamic> {
  _FailingSettingsBox(this._persisted);

  final Map<dynamic, dynamic> _persisted;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _persisted[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) =>
      Future<void>.error(StateError('settings write failed'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not exercised by this test',
  );
}
