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
/// Output: `../design/exports/screenshots/NN-<tab>.png`, each exactly 1410x2808
/// (470x936 logical at devicePixelRatio 3). See docs/PLAY_STORE.md.
///
/// ## Why this viewport, in full
///
/// Play imposes **two** constraints on a phone screenshot, and the app's 393x852
/// reference viewport (`matrixPoints[1]`) satisfies only one:
///
///  * pixel floor — 1080x2340. 393x852 at 3x is 1179x2556, comfortably above.
///  * aspect ceiling — **2:1** height/width. 1179x2556 is 2.17:1 and is rejected
///    at upload, floor or no floor.
///
/// The ceiling therefore caps height at 2x the width, and the screens here are
/// full-screen layouts with two pieces of *fixed* chrome: the floating tab bar,
/// and on Vault a floating action dock, on Share a fixed CTA. At 393dp the cap is
/// 786dp — and at that height both of those screens put a floating control over
/// the last row of their scroll view, so no scroll offset can frame them without
/// cutting something (a scroll that clears the dock also pushes the screen's own
/// title bar out of frame, which reads as a broken render).
///
/// So the width is what moves: 470x936 at 3x is 1410x2808 = 1.99:1, inside the
/// ceiling, and at that size all five screens fit at rest — title bar, content
/// and tab bar all intact, no scrolling, no clipped row. 470dp is a real Android
/// width (foldables and small tablets report it; phones report 320-448dp), so the
/// layout is one the responsive code genuinely produces — nothing is faked or
/// rearranged for the picture.
///
/// Both bounds are asserted below, so a future viewport edit cannot silently
/// re-break the upload.
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

  // 470x936 at 3x is 1410x2808. See the file docstring for why this is not the
  // app's 393x852 reference: Play's 2:1 aspect ceiling, and what it does to the
  // two screens with fixed floating chrome.
  const point = MatrixPoint(
    name: 'store',
    width: 470,
    height: 936,
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
      // No centre card on the card the Vault screenshot lands on: `_PassPage`
      // omits `_CenterCard` when address, gate and reportBy are all empty, so
      // the pass, countdown and checklist then fit above the floating dock and
      // the picture shows three sections cleanly instead of a fourth bleeding
      // through the dock's fade. Reachable — `vault_form_sheet.dart` validates
      // only exam name and roll — and layout-tested at every matrix point by
      // `state_matrix_test.dart`'s `noCentreDetails` case.
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
  ///
  /// Deliberately no scroll offsets: every one of these is captured at rest, so
  /// the picture is the screen as it opens. An earlier revision scrolled Vault
  /// and Share to clear their floating controls and produced two broken images —
  /// Share opened on a bare red band with its title bar gone. Framing is the
  /// viewport's job (see the file docstring), not a magic offset's.
  const tabs = <(String, String)>[
    ('01-home', 'Home'),
    ('02-vault', 'Vault'),
    ('03-dates', 'Dates'),
    ('04-radar', 'Radar'),
    ('05-share', 'Share'),
  ];

  for (final (file, label) in tabs) {
    testWidgets(
      'captures $label at 1410x2808',
      (tester) async {
        // Guard the documented `cd app` precondition *first*: from any other
        // directory `../design` resolves outside the repo, so the screenshots
        // would be written where nobody looks. Checking here fails in a
        // millisecond instead of after a full pump-and-rasterise.
        if (!Directory('../design').existsSync()) {
          fail(
            'Run this from app/ (cd app && EV_SCREENSHOTS=1 flutter test '
            'test/screenshot_capture_test.dart) — ../design does not exist from '
            '${Directory.current.path}.',
          );
        }

        final boundaryKey = GlobalKey();
        await pumpMatrix(
          tester,
          RepaintBoundary(key: boundaryKey, child: const RootShell()),
          point,
          env: env,
          cards: cards,
          fullFeed: true,
          // One row, not two: the radar row grew a full-width status line (the
          // pill at its token size with the age flush right) when Task 19 fixed
          // its 8.25px label, so two rows now reach under the floating tab bar
          // and the second one is clipped by it. Framing is the fixture's job —
          // the assertions below still pin the header and the tab bar — and one
          // complete row reads as a live radar block instead of a cut-off one.
          feedRows: 1,
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

        // Dimensions and aspect ratio cannot see a framing defect: an earlier
        // revision passed every size check while its share capture opened on a
        // bare red band with the title bar scrolled out of frame. So assert the
        // frame structurally too — the tab bar and this screen's own top
        // chrome must be laid out inside the viewport, and the content must not
        // be pushed above it.
        _expectFramed(tester, point, label);

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
          // Play's other constraint, and the one that actually bites: a phone
          // screenshot taller than 2:1 is rejected at upload. 1179x2556 (the
          // 852dp reference at 3x) is 2.17 and would be rejected for exactly
          // this, while passing the pixel floor above.
          expect(
            image.height / image.width,
            lessThanOrEqualTo(2.0),
            reason: 'Play Store screenshots must be at most 2:1 (h/w)',
          );
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });

        final out = File('../design/exports/screenshots/$file.png');
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

/// The anchor text each screen puts in its top chrome.
///
/// Used by [_expectFramed]: if the picture's first few hundred pixels are not
/// this screen's own header, the frame is wrong no matter what the dimensions
/// say.
const _topAnchor = <String, String>{
  'Home': 'EXAMVAULT',
  'Vault': 'Saved Pass',
  'Dates': 'Exam Calendar',
  'Radar': 'Result Radar',
  'Share': 'Share Card',
};

/// Asserts the screen is framed: its header and the tab bar are on-screen.
///
/// A screenshot can be exactly 1410x2808 and still be worthless — the round-2
/// defect was a capture whose nav bar had been scrolled out of the viewport,
/// leaving a bare colour band where the title belonged. Size assertions cannot
/// see that, so this checks the layout directly:
///
///  * the screen's own top anchor is laid out inside the viewport rect, and
///  * the floating tab bar is too, and its bottom edge is at the viewport's.
void _expectFramed(WidgetTester tester, MatrixPoint point, String label) {
  final screen = Rect.fromLTWH(0, 0, point.width, point.height);

  final anchor = _topAnchor[label]!;
  final finder = find.text(anchor);
  expect(finder, findsOneWidget, reason: '$label must show "$anchor"');
  final header = tester.getRect(finder);
  expect(
    header.top >= screen.top - 1 && header.bottom <= screen.height / 3,
    isTrue,
    reason:
        '$label: "$anchor" must sit in the top third of the frame, '
        'not at $header',
  );

  final bar = find.byType(EvTabBar);
  expect(bar, findsOneWidget, reason: '$label must render the tab bar');
  final barRect = tester.getRect(bar);
  expect(
    barRect.top >= screen.top && barRect.bottom <= screen.bottom + 1,
    isTrue,
    reason:
        '$label: the tab bar must be fully inside the viewport, not at '
        '$barRect',
  );
  expect(
    barRect.bottom,
    greaterThan(screen.height * 0.8),
    reason:
        '$label: the tab bar must sit at the bottom of the frame, not at '
        '$barRect',
  );
}
