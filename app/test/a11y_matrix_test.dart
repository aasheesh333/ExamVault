import 'dart:io';

import 'package:examvault/features/command_center/command_center_screen.dart';
import 'package:examvault/features/result_checker/instant_result_checker_screen.dart';
import 'package:examvault/features/share_card/whatsapp_share_card_screen.dart';
import 'package:examvault/features/vault/admit_card_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// The accessibility matrix.
///
/// The state matrix proves every screen *lays out* at every device/scale/theme
/// point; this one proves every screen is *usable without looking at it*. For
/// each screen × {default, scaled200small, light} it asserts, mechanically:
///
///  * `labeledTapTargetGuideline` — every tappable semantics node has a name,
///    so TalkBack never announces a bare "Button".
///  * `iOSTapTargetGuideline` — every tappable node is at least 44x44.
///    Deliberately the 44dp guideline, not `androidTapTargetGuideline` (48dp):
///    this app's own accessibility floor is `EvSize.minTapTarget = 44` and
///    every control in the design system is built to it, so the 48dp variant
///    fails by design on the whole system (measured: chips, icon buttons,
///    secondary buttons and header text actions all sit at exactly 44).
///    Reaching 48 would be a visual redesign of every control, not an a11y
///    fix; 44 also satisfies WCAG 2.5.5.
///  * a walk of the semantics tree for the two bugs this codebase kept
///    shipping by hand and fixing widget by widget:
///      - the double-read: a node whose label exactly equals its parent's
///        (the "Notifications, Notifications" signature), and
///      - a button node with an empty accessible name.
void main() {
  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_a11y');
    Hive.init(hiveDir.path);
    // Warm the shared font guard from the REAL async zone, as matrix.dart
    // prescribes ("Suites should also call this once from setUpAll") and as
    // every sibling suite does. Letting the first load happen inside a
    // testWidgets fake clock instead completed the module-level guard future
    // in that zone — and every later cell then deadlocked awaiting it at
    // "PM: fonts start" until the wall-clock timeout fired.
    await loadMatrixFonts();
  });

  // One in-memory box pair per test, mirroring the state matrix: Hive's
  // file-backed close() waits on compaction that never runs on the widget-test
  // clock, so boxes are memory-only and never closed (see MatrixEnv).
  setUp(() async {
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  final screens = <String, Widget Function()>{
    'Home': CommandCenterScreen.new,
    'Vault': AdmitCardDetailScreen.new,
    'Radar': InstantResultCheckerScreen.new,
    'Share': WhatsappShareCardScreen.new,
  };

  // The three matrix points that matter for a11y: the reference device, the
  // worst-case combination (smallest screen at the 2.0x scale clamp endpoint),
  // and the light palette (whose shipped colours differ from dark's).
  const pointNames = {'default', 'scaled200small', 'light'};
  final points = matrixPoints.where((p) => pointNames.contains(p.name));

  for (final screen in screens.entries) {
    for (final point in points) {
      testWidgets('a11y — ${screen.key} / $point', (tester) async {
        // Semantics must be enabled *before* the tree is built: the
        // guideline matchers walk `semanticsOwner.rootSemanticsNode`, which
        // is null while the semantics binding is off.
        //
        // The handle is disposed in a `finally` inside the body, NOT via
        // `addTearDown`: the framework's end-of-test verification runs
        // before any tearDown callback, so a handle parked in tearDown
        // tripped "A SemanticsHandle was active at the end of the test" —
        // and the leaked handle then wedged every following cell into a
        // wall-clock timeout.
        final handle = tester.ensureSemantics();
        try {
          await pumpMatrix(
            tester,
            screen.value(),
            point,
            env: env,
            cards: [matrixCard()],
          );

          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

          expectNoDoubleRead(tester, point);

          await disposeMatrix(tester);
        } finally {
          handle.dispose();
        }
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
  }
}

/// Walks the live semantics tree for the double-read signature and for
/// unnamed buttons. Fails with every finding at once, so one run names the
/// whole problem instead of the first instance.
void expectNoDoubleRead(WidgetTester tester, MatrixPoint point) {
  final problems = <String>[];

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root == null) {
      problems.add('semantics tree is missing — was ensureSemantics() called?');
      continue;
    }
    _walk(root, null, problems);
  }

  if (problems.isNotEmpty) {
    fail('Semantics defects at $point:\n  ${problems.join('\n  ')}');
  }
}

void _walk(SemanticsNode node, SemanticsNode? parent, List<String> problems) {
  // Merged children are folded into their parent's node before the platform
  // ever sees them: they cannot double-read on their own, and their name is
  // the parent's job. Judging them separately reports the merged label twice.
  if (!node.isMergedIntoParent && !node.isInvisible) {
    final data = node.getSemanticsData();
    final label = data.label.trim();

    if (parent != null && label.isNotEmpty) {
      final parentLabel = parent.getSemanticsData().label.trim();
      if (label == parentLabel) {
        problems.add(
          'double-read: node ${node.id} ("$label") repeats its parent '
          '${parent.id}\'s label verbatim — TalkBack reads it twice',
        );
      }
    }

    if (data.flagsCollection.isButton &&
        label.isEmpty &&
        data.value.trim().isEmpty &&
        data.tooltip.trim().isEmpty) {
      problems.add(
        'unnamed button: node ${node.id} at ${node.rect} has the button flag '
        'but no label, value or tooltip',
      );
    }
  }

  node.visitChildren((child) {
    _walk(child, node, problems);
    return true;
  });
}
