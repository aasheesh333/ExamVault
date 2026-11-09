import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
import 'package:examvault/shared/widgets/ev_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout regressions found by running the real app, not by reading the code.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  group('EvChip', () {
    testWidgets('hugs its label instead of filling the row', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          Wrap(
            spacing: 7,
            children: [
              EvChip(label: 'SSC', selected: true, onTap: () {}),
              EvChip(label: 'UPSC', selected: false, onTap: () {}),
            ],
          ),
        ),
      );

      // The sheet is 393 wide minus 2*16 padding minus 2*16 inner padding.
      const runWidth = 393 - 32 - 32;

      final ssc = tester.getSize(find.byType(EvChip).first);
      expect(
        ssc.width,
        lessThan(runWidth / 2),
        reason: 'a 3-character chip must not take half the row',
      );

      // And the two chips must sit side by side, not stacked.
      final sscCentre = tester.getCenter(find.byType(EvChip).first);
      final upscCentre = tester.getCenter(find.byType(EvChip).last);
      expect(
        (sscCentre.dy - upscCentre.dy).abs(),
        lessThan(1),
        reason: 'chips in a Wrap must share a baseline',
      );
    });

    testWidgets('keeps a 44px tap target while drawing a 32px pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(EvChip(label: 'Railways', selected: false, onTap: () {})),
      );

      final size = tester.getSize(find.byType(EvChip));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('EvSectionHeader', () {
    testWidgets('does not clip its trailing action', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 361,
            child: EvSectionHeader(
              label: 'My admit cards',
              padding: EdgeInsets.zero,
              trailing: EvTextAction(label: '3 saved', onPressed: () {}),
            ),
          ),
        ),
      );

      // A fixed 20px header clipped the ~30px action in half.
      expect(tester.takeException(), isNull);
      final header = tester.getSize(find.byType(EvSectionHeader));
      expect(header.height, greaterThanOrEqualTo(30));

      final action = tester.getSize(find.byType(EvTextAction));
      expect(action.height, greaterThanOrEqualTo(30));
    });
  });
}
