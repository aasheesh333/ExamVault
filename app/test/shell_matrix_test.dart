import 'dart:io';

import 'package:examvault/features/shell/root_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// The shell — not the bare screens — across the whole matrix.
///
/// WHY this file exists: `state_matrix_test.dart` mounts each screen alone, so
/// it has never seen the product as shipped: four screens kept alive under one
/// `IndexedStack`, a floating `extendBody` tab bar over the body, the radar
/// badge, the predictive-back `PopScope`. The floating bar is exactly the
/// "covered — taps land on the wrong widget" hazard `expectTapTargets` was
/// written for, and the tab labels are exactly the "HomeVaultRadarShare"
/// collision the FittedBox fix addressed. Neither was asserted anywhere.
///
/// The tab-bar contract is asserted geometrically, per matrix point:
///
///  * the four labels' rendered rects are pairwise non-intersecting — labels
///    must never bleed into their neighbour (the collision that once read as
///    one word), and
///  * each label lies inside its own tab button — a label escaping its pill
///    was the original bug; containment on the *rendered* rect also pins the
///    FittedBox scale-down, because `localToGlobal` includes the paint
///    transform the FittedBox applies.
void main() {
  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_shell_matrix');
    Hive.init(hiveDir.path);
    // Real bundled fonts, loaded outside the widget-test fake clock (see
    // loadMatrixFonts): the tab labels are FittedBox-scaled to their measured
    // width, so asserting collisions against the square test font would prove
    // nothing about the shipped typeface.
    await loadMatrixFonts();
  });

  // One in-memory box pair per test, same as state_matrix_test.dart: a
  // CdnClient write queued in one test must never be visible to the next.
  setUp(() async {
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    // Best effort, no env.close(): Hive's close() waits on compaction the
    // widget-test clock never advances (see state_matrix_test.dart).
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  for (final point in matrixPoints) {
    testWidgets(
      'RootShell / $point',
      (tester) async {
        await pumpMatrix(tester, const RootShell(), point, env: env);

        expectScreenSane(tester, point);
        _expectTabBarSane(tester, point);

        await disposeMatrix(tester);
      },
      // The hang cases never happen here, but the shell boots four screens and
      // the feed poll makes the default 30s timeout uncomfortably tight on a
      // loaded CI box — keep the same generous budget as the state matrix.
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

/// The geometric tab-bar contract described in the file header.
void _expectTabBarSane(WidgetTester tester, MatrixPoint point) {
  final bar = find.byType(EvTabBar);
  expect(bar, findsOneWidget, reason: 'the shell must render its tab bar');

  // The four tab buttons, in tab order: EvTabBar lays out one InkWell per tab
  // in a Row over EvTab.values, so tree order == visual order.
  final buttons = <Rect>[];
  for (final element
      in find.descendant(of: bar, matching: find.byType(InkWell)).evaluate()) {
    final box = element.renderObject! as RenderBox;
    buttons.add(box.localToGlobal(Offset.zero) & box.size);
  }
  expect(
    buttons.length,
    EvTab.values.length,
    reason: 'every tab must expose exactly one button',
  );

  // The rendered (paint-transformed) rect of each label.
  final labels = <String, Rect>{};
  for (final tab in EvTab.values) {
    final finder = find.descendant(of: bar, matching: find.text(tab.label));
    expect(
      finder,
      findsOneWidget,
      reason: 'tab ${tab.label} must show its label',
    );
    labels[tab.label] = tester.getRect(finder);
  }

  final names = EvTab.values.map((t) => t.label).toList();

  // Pairwise non-intersecting: touching edges are allowed (overlaps() is
  // strict), any shared area is the "HomeVaultRadarShare" regression.
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final a = labels[names[i]]!;
      final b = labels[names[j]]!;
      expect(
        a.overlaps(b),
        isFalse,
        reason:
            'tab labels "${names[i]}" ($a) and "${names[j]}" ($b) must not '
            'intersect at $point',
      );
    }
  }

  // Each label inside its own button. The rendered rect of a FittedBox-scaled
  // label can only be smaller than its layout rect, so containment here also
  // proves the scale-down is doing its job at 2.0x on 320px.
  for (var i = 0; i < names.length; i++) {
    expect(
      _containsRect(buttons[i], labels[names[i]]!),
      isTrue,
      reason:
          'tab label "${names[i]}" (${labels[names[i]]}) escaped its button '
          '(${buttons[i]}) at $point',
    );
  }
}

/// True when [inner] lies fully within [outer], edges included.
///
/// dart:ui's `Rect` only offers `contains(Offset)` and `overlaps`, so full
/// containment is four edge comparisons.
bool _containsRect(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.right <= outer.right &&
    inner.top >= outer.top &&
    inner.bottom <= outer.bottom;
