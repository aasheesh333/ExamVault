import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/matrix.dart';

/// The harness must prove its own sharpest assertion works.
///
/// WHY: `expectTapTargets`'s "covered — taps land on the wrong widget" check was
/// logically inverted (it walked up from the target instead of up from the hit,
/// so every common ancestor satisfied it and the branch was unreachable). The
/// matrix ran green for months with a check that could not fire. A test of the
/// product cannot catch that; only a test of the *harness* can — a widget that
/// is deliberately, unambiguously covered must FAIL the assertion, and the same
/// widget uncovered must PASS.
void main() {
  // The default flutter_test surface; expectTapTargets only needs the point for
  // its screen rect.
  const point = MatrixPoint(
    name: 'selftest',
    width: 800,
    height: 600,
    textScale: 1.0,
    dark: false,
  );

  /// A 44x44 InkWell — legal size, on screen — with an optional opaque sibling
  /// painted over its centre inside a Stack. The cover is a `Listener`, not a
  /// `GestureDetector`, so the cover itself stays out of the sweep (Listener is
  /// not in the harness's interactive set) and the only finding that can come
  /// out is the covered InkWell.
  Widget subject({required bool covered}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InkWell(
                    onTap: () {},
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
                if (covered)
                  Positioned.fill(
                    child: Listener(
                      // Opaque: absorbs the hit at the centre instead of letting
                      // it fall through to the InkWell — exactly the "checklist
                      // row fired Check my result" bug shape.
                      behavior: HitTestBehavior.opaque,
                      child: const ColoredBox(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('expectTapTargets FAILS on a covered 44px InkWell', (
    tester,
  ) async {
    await tester.pumpWidget(subject(covered: true));

    Object? thrown;
    try {
      expectTapTargets(tester, point);
    } catch (e) {
      thrown = e;
    }

    // fail() inside the harness throws TestFailure; assert both that it fired
    // and *why* it fired, so a future unrelated failure cannot masquerade as
    // this proof.
    expect(
      thrown,
      isNotNull,
      reason:
          'a widget covered by an opaque sibling must be reported — if this '
          'passes, the coverage check is vacuous again',
    );
    expect('$thrown', contains('covered — taps land on the wrong widget'));
  });

  testWidgets('expectTapTargets passes on the same InkWell uncovered', (
    tester,
  ) async {
    await tester.pumpWidget(subject(covered: false));

    // Must not throw: same widget, same size, same position — only the opaque
    // sibling is gone, so a failure here would mean the check fires on
    // legitimately tappable widgets.
    expectTapTargets(tester, point);
  });
}
