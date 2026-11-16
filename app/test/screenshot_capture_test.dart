import 'dart:io';
import 'dart:ui' as ui;

import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/features/shell/root_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// Renders the Play Store screenshots from the real widget tree.
///
/// WHY this is a widget test and not a device capture: there is no emulator or
/// physical phone in this environment, and a hand-built mockup would show a
/// product that does not exist. The screens below are the shipped widgets, laid
/// out by the real theme and the real bundled typefaces, rasterised at 3x.
///
/// It is **off by default**. A plain `flutter test` must not write files into
/// the repo or fail on a machine without the fonts, so every case is skipped
/// unless `EV_SCREENSHOTS=1` is set:
///
///     cd app && EV_SCREENSHOTS=1 flutter test test/screenshot_capture_test.dart
///
/// WHY an environment variable and not `@Tags(['screenshots'])`: the tag alone
/// still runs the file in a plain `flutter test` (tags filter *selection*, they
/// do not skip), and a tag used without a `dart_test.yaml` declaration prints a
/// warning on every run. The env var is the only gate that is both inert by
/// default and warning-free.
///
/// Output: `../design/exports/screenshots/NN-<tab>.png`, each exactly 1179x2556
/// (393x852 logical at devicePixelRatio 3 — the app's reference viewport, above
/// Play's 1080x2340 floor). See docs/PLAY_STORE.md.
void main() {
  final enabled = Platform.environment['EV_SCREENSHOTS'] == '1';

  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    if (!enabled) return;
    hiveDir = await Directory.systemTemp.createTemp('ev_screenshots');
    Hive.init(hiveDir.path);
    // Bundled fonts, loaded on the real event loop before any fake clock exists
    // (see the loadMatrixFonts contract in support/matrix.dart).
    await loadMatrixFonts();
    await _loadMaterialIcons();
  });

  setUp(() async {
    if (!enabled) return;
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    if (!enabled) return;
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  // 393x852 at 3x is 1179x2556 — the app's own reference viewport (matrixPoints[1])
  // and comfortably above Play's 1080x2340 floor. The narrower 360x780 was tried
  // first and produced exactly 1080x2340, but at that width the vault's floating
  // "Check my result" dock covered the checklist it exists to explain.
  const point = MatrixPoint(
    name: 'store',
    width: 393,
    height: 852,
    textScale: 1.0,
    dark: true,
  );

  // Content a real student would see on day one: three saved admit cards (so
  // the calendar has more than one row and the wallet stack shows its depth)
  // and a live feed. Nothing here is invented for the screenshot — the feed
  // JSON is the same fixture the matrix asserts against, and every card is
  // matrixCard().
  final cards = [
    matrixCard(
      id: 'store',
      examName: 'SSC CGL Tier-1 2026',
      category: ExamCategory.ssc,
      roll: '2201049821',
      daysFromNow: 12,
      verified: true,
      checklist: const {
        ChecklistItem.admitCardPdf,
        ChecklistItem.passportPhotos,
      },
    ),
    matrixCard(
      id: 'store2',
      examName: 'IBPS PO Prelims 2026',
      category: ExamCategory.banking,
      conductingBody: 'Institute of Banking Personnel Selection',
      examCode: 'PO · PRELIMS',
      roll: '2201000002',
      registrationId: 'IBPS-PO-26-118842',
      // No centre card on the card the Vault screenshot lands on: the pass,
      // the countdown and the checklist then fit above the floating dock, so
      // the picture shows three sections cleanly instead of a fourth bleeding
      // through the dock's fade. (A card without centre details is a real
      // state — see the matrix's `sparseFields` case.)
      centerAddress: '',
      centerCode: 'DL-04-1187',
      gate: '',
      reportBy: '',
      daysFromNow: 4,
      checklist: const {ChecklistItem.admitCardPdf},
    ),
    matrixCard(
      id: 'store3',
      examName: 'RRB NTPC 2026',
      category: ExamCategory.railways,
      conductingBody: 'Railway Recruitment Board',
      examCode: 'CBT-1',
      roll: '2201000003',
      registrationId: 'RRB-NTPC-26-770211',
      centerAddress: 'Govt. Boys Senior Secondary School, Rohini',
      centerCode: 'DL-07-2210',
      daysFromNow: 27,
      checklist: const {},
    ),
  ];

  /// Every shipped tab, in tab-bar order.
  const tabs = <(String, String)>[
    ('01-home', 'Home'),
    ('02-vault', 'Vault'),
    ('03-dates', 'Dates'),
    ('04-radar', 'Radar'),
    ('05-share', 'Share'),
  ];

  for (final (file, label) in tabs) {
    testWidgets(
      'captures $label at 1179x2556',
      (tester) async {
        final boundaryKey = GlobalKey();
        await pumpMatrix(
          tester,
          RepaintBoundary(key: boundaryKey, child: const RootShell()),
          point,
          env: env,
          cards: cards,
          fullFeed: true,
          feedRows: 8,
        );

        // The MockClient's response only completes on the real event loop (the
        // same limitation search_test.dart documents), so without this hop the
        // radar renders NO FEED in the picture.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        if (label != 'Home') {
          await tester.tap(
            find.descendant(
              of: find.byType(EvTabBar),
              matching: find.text(label),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        expect(boundary.debugNeedsPaint, isFalse);

        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3.0);
          // Pinned, not "roughly big enough": Play rejects a screenshot below
          // 1080px on the short edge, and a silent viewport change (a future
          // matrix edit) must fail here rather than ship an undersized asset.
          expect(image.width, (point.width * 3).round());
          expect(image.height, (point.height * 3).round());
          expect(image.width, greaterThanOrEqualTo(1080));
          expect(image.height, greaterThanOrEqualTo(2340));
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });

        final out = File('../design/exports/screenshots/$file.png');
        // Guard the documented `cd app` precondition: run from anywhere else and
        // this path resolves *outside* the repo, silently writing the screenshots
        // where nobody looks.
        if (!Directory('../design').existsSync()) {
          fail(
            'Run this from app/ (cd app && EV_SCREENSHOTS=1 flutter test '
            'test/screenshot_capture_test.dart) — ../design does not exist from '
            '${Directory.current.path}.',
          );
        }
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes!);
        // ignore: avoid_print
        print('wrote ${out.path} (${bytes.length} bytes)');

        await disposeMatrix(tester);
      },
      skip: !enabled,
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}

/// Loads Flutter's icon typeface so `Icon`s render as glyphs, not tofu.
///
/// `flutter test` ships no Material Icons font (the app resolves it from the
/// engine at runtime, and the matrix suites never assert on icon glyphs, so the
/// default square-glyph fallback was invisible to them). A screenshot full of
/// empty boxes is worse than no screenshot, so the font is read straight out of
/// the SDK's artefact cache — `FLUTTER_ROOT` is set by the test runner.
///
/// Best effort on purpose: if the font is missing (a trimmed SDK), the capture
/// still runs and the tofu boxes are visible in the output, rather than the
/// pipeline failing with a path error.
Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
      .load();
}
