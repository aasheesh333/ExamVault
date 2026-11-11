import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/about/about_sheet.dart';
import 'package:examvault/features/command_center/widgets/alerts_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
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

  Widget host() => ProviderScope(
    overrides: [
      settingsBoxProvider.overrideWithValue(settingsBox),
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
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Column(
            children: [
              TextButton(
                onPressed: () => showAboutSheet(context),
                child: const Text('open about'),
              ),
              TextButton(
                onPressed: () => showAlertsSheet(context, ref),
                child: const Text('open alerts'),
              ),
            ],
          ),
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

      await tester.scrollUntilVisible(
        find.text('Read the privacy policy'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
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
}

class _StaticLiveFeed extends LiveFeedNotifier {
  _StaticLiveFeed(this.snapshot);

  final LiveFeedSnapshot snapshot;

  @override
  Future<LiveFeedSnapshot> build() async => snapshot;
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
