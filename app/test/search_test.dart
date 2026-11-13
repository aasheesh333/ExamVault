import 'dart:io';

import 'package:examvault/features/command_center/command_center_screen.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// The search path on Home — previously a blind spot.
///
/// The layout matrix renders every screen but types into nothing, so the whole
/// search interaction was untested: the "shown of total" fraction in the radar
/// header, the no-match copy (which must never collapse back into "Nothing
/// live right now"), the clear button's effect on the query provider, and the
/// focus ring the field's own comments claim exists.
void main() {
  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_search');
    Hive.init(hiveDir.path);
    // Real fonts, real advances — loaded once outside the widget-test clock.
    await loadMatrixFonts();
  });

  setUp(() async {
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  /// 393x852, dark, 1.0x — the reference phone.
  final point = matrixPoints[1];

  Future<void> mountHome(WidgetTester tester) async {
    await pumpMatrix(tester, const CommandCenterScreen(), point, env: env);
    // The MockClient's StreamedResponse does not complete on the fake clock
    // (the same limitation result_day_test documents for the roll index), so
    // the canned feed only lands on the real event loop. One short runAsync
    // hop plus a frame paints it; without this the radar renders NO FEED.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The search field's outer box: the only Container on Home pinned to a
  /// tight 48px height with a decoration.
  final searchBox = find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.constraints?.minHeight == 48 &&
        w.constraints?.maxHeight == 48 &&
        w.decoration is BoxDecoration,
  );

  Color borderColor(WidgetTester tester) {
    final box = tester.widget<Container>(searchBox);
    final decoration = box.decoration! as BoxDecoration;
    return (decoration.border! as Border).top.color;
  }

  group('radar search', () {
    testWidgets('a query narrows the rows and the header counts honestly', (
      tester,
    ) async {
      await mountHome(tester);

      // Baseline: the 4-row matrix feed, no count shown while idle. The rows
      // are counted as built, not as a fixed 4: the radar is a lazy SliverList
      // and the row grew a 44px alert bell, so how many fit at 393x852 is a
      // viewport fact, not a product fact. The filtered count below is what
      // this test is about.
      final baseline = tester.widgetList(find.byType(LiveRadarTile)).length;
      expect(baseline, greaterThanOrEqualTo(1));
      expect(find.text('1 of 4'), findsNothing);

      await tester.enterText(find.byType(TextField), 'hindi');
      await tester.pump();

      // Exactly one matrix row mentions Hindi (the Combined Hindi Translators
      // notice). The denominator is the category-filtered active set — with
      // "All Exams" that is all four rows. It used to be the *unfiltered*
      // feed total, which read "1 of 60" on a real feed while only a handful
      // of rows were ever searchable.
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.byType(LiveRadarTile), findsOneWidget);
      expectClean(tester);
    });

    testWidgets('a query matching nothing says so — never "nothing live"', (
      tester,
    ) async {
      await mountHome(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();

      expect(find.text('0 of 4'), findsOneWidget);
      expect(find.textContaining('No radar result matches'), findsOneWidget);
      // The empty-feed copy would be a lie: the feed has four live rows, the
      // query simply matched none of them.
      expect(find.textContaining('Nothing live right now'), findsNothing);
      expect(find.byType(LiveRadarTile), findsNothing);
      expectClean(tester);
    });

    testWidgets('clearing the search empties the query and restores the rows', (
      tester,
    ) async {
      await mountHome(tester);

      await tester.enterText(find.byType(TextField), 'hindi');
      await tester.pump();
      expect(find.byType(LiveRadarTile), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.text('Command Center')),
      );
      expect(container.read(searchQueryProvider), isEmpty);
      final restored = tester.widgetList(find.byType(LiveRadarTile)).length;
      expect(restored, greaterThan(1), reason: 'all rows come back');
      // The fraction is a searching-only affordance; the header goes back to
      // the feed status.
      expect(find.text('1 of 4'), findsNothing);
      expect(find.text('0 of 4'), findsNothing);
      expectClean(tester);
    });

    testWidgets('the search box border reads focus', (tester) async {
      await mountHome(tester);

      final blurred = borderColor(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final focused = borderColor(tester);

      // The focus listener existed precisely so this ring would paint — and
      // nothing ever asserted that it does.
      expect(
        focused,
        isNot(blurred),
        reason: 'focusing the field must change its border colour',
      );

      await tester.enterText(find.byType(TextField), 'hindi');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close_rounded)); // clears + unfocuses
      await tester.pump();

      expect(borderColor(tester), blurred);
      expectClean(tester);
    });
  });
}
