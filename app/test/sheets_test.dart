import 'dart:async';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/about/about_sheet.dart';
import 'package:examvault/features/command_center/widgets/alerts_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
import 'package:examvault/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The two bottom sheets, at the worst size the app supports.
///
/// Both open at 72–92% of the viewport, so a phone 320px wide at 2.0x text is the
/// case where a scrolling header collides with content and where text used to
/// paint over the rounded top corners.
void main() {
  late Directory dir;
  late Box<dynamic> settingsBox;

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
  }) => ProviderScope(
    overrides: [
      settingsBoxProvider.overrideWithValue(settingsBox),
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
