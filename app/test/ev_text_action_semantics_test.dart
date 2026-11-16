import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/shared/widgets/ev_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves `EvTextAction` is operable at the API the screen reader actually uses.
///
/// The widget used to wrap its `InkWell` in
/// `Semantics(button: true, excludeSemantics: true, label: …)` without an
/// `onTap`. `excludeSemantics` drops the child's `SemanticsAction.tap`, so the
/// node TalkBack focused announced "Retry, button" and exposed **zero actions**
/// — the double-tap did nothing. The a11y matrix now guards this mechanically
/// for every screen; this test pins the primitive itself, through the same
/// `SemanticsOwner.performAction` path a platform accessibility service drives.
void main() {
  Future<int Function()> pumpAction(
    WidgetTester tester, {
    VoidCallback? onPressed,
  }) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: EvTextAction(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: onPressed ?? () => taps++,
            ),
          ),
        ),
      ),
    );
    return () => taps;
  }

  testWidgets('the semantics node exposes a tap action', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await pumpAction(tester);

      final node = tester.semantics.find(find.byType(EvTextAction));
      final data = node.getSemanticsData();

      expect(data.label, 'Retry');
      expect(data.flagsCollection.isButton, isTrue);
      expect(
        data.hasAction(SemanticsAction.tap),
        isTrue,
        reason:
            'the button node must carry the InkWell tap itself: '
            'excludeSemantics removes the child action',
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('activating it through the semantics layer runs the callback', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final taps = await pumpAction(tester);

      // Exactly the path TalkBack uses: SemanticsOwner.performAction on the
      // node the accessibility service focused.
      tester.semantics.tap(find.semantics.byLabel('Retry'));
      await tester.pump();

      expect(taps(), 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('the action is announced once, not twice', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      final taps = await pumpAction(tester);

      // `excludeSemantics` is what keeps the label to a single node; removing it
      // to "get the action back" would duplicate the announcement instead.
      expect(find.semantics.byLabel('Retry'), findsOne);

      tester.semantics.tap(find.semantics.byLabel('Retry'));
      await tester.pump();

      expect(taps(), 1, reason: 'one activation must fire the handler once');
    } finally {
      handle.dispose();
    }
  });
}
