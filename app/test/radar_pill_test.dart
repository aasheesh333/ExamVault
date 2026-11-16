import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/core/theme/theme_tokens.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/command_center/widgets/alerts_sheet.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_surfaces.dart';
import 'package:examvault/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The status pill must never paint below the 11px type floor — at any scale,
/// including the one every user has.
///
/// The defect this file locks down: `LiveRadarTile` and `alerts_sheet.dart`'s
/// `_AlertRow` each gave the pill a narrow right-hand column and wrapped it in
/// `FittedBox(fit: BoxFit.scaleDown)`. That column is ~100px at 320dp while the
/// pill's intrinsic width is 134px at 1.0x and 233px at 2.0x, so the box bridged
/// the gap by shrinking the text: **8.25px on the radar and 7.75px in the alerts
/// sheet at the default 1.0x text size** (and 9.49px / 8.91px at 2.0x before
/// Task 16 stacked the large-text path). The column was the cause and the scale
/// was the symptom, so both widgets now give the pill a full-width line of its
/// own — 256px on the radar tile and 248px in the sheet at 320dp, both wider than
/// its 233px intrinsic width at 2.0x.
///
/// There is deliberately **one arrangement from 1.0x to 2.0x**: the `stacked`
/// branch (and the `FittedBox` on the other branch) is gone, because the pill
/// needed the full width at 1.0x too. The tests below therefore loop every scale
/// and assert the same invariants at each.
///
/// The status line's trailing age is pinned separately at 1.0x and 2.0x. It used
/// to sit in a `Wrap(alignment: spaceBetween)`, which applies one alignment to
/// every run — and places a *lone* child at the run's start (wrap.dart:111) — so
/// once the age wrapped (1.6x and above) it landed at x=32, under the pill's left
/// edge, with 189.5px of dead space to its right. `_StatusLine` in
/// `live_radar_tile.dart` now keeps it against the right edge on either run.
///
/// "Nothing overflows" was the assertion that hid the original bug: scaling is
/// precisely what kept the row from overflowing. These tests measure the label
/// the user actually sees — declared size x the enclosing text scaler x the paint
/// transform of every `RenderFittedBox` above it — and separately assert that no
/// `FittedBox` sits above the pill at all.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The bundled typefaces: a 2.0x layout test must measure real advances,
    // not the square-glyph test font.
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
  });

  /// Every scale the app has to survive, 1.0x (the default) through 2.0x (the
  /// largest setting Android exposes).
  const scales = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0];

  LiveUpdate update({
    String examName = 'SSC CGL Result 2026',
    UpdateStatus status = UpdateStatus.admitCardLive,
    int? latency = 82,
  }) => LiveUpdate(
    examId: 'exam_ssc_cgl',
    category: ExamCategory.ssc,
    examName: examName,
    contextLine: 'Direct PDF · 18.4 MB',
    status: status,
    publishedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    expiresAt: DateTime.now().add(const Duration(days: 2)),
    mirrorLatencyMs: latency,
  );

  /// 320x568 — the smallest phone the design targets — at [textScale].
  void smallPhone(WidgetTester tester, {required double textScale}) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// The label's painted size in logical pixels.
  ///
  /// `RenderParagraph` lays its glyphs out at `fontSize x textScaler`, and any
  /// enclosing `RenderFittedBox` shrinks them again during paint. Multiplying
  /// both factors is the only honest answer to "how big is this text on
  /// screen?" — reading `style.fontSize` alone reports 11.0 no matter what the
  /// row did to it, which is exactly how the 8.25px paint went unnoticed.
  double paintedFontSize(WidgetTester tester, Finder textFinder) {
    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    final declared = paragraph.text.style?.fontSize;
    expect(declared, isNotNull, reason: 'the pill label must carry a size');
    final scaler = MediaQuery.textScalerOf(tester.element(textFinder));
    return scaler.scale(declared!) * _fittedScaleAbove(paragraph);
  }

  /// The number of `RenderFittedBox` ancestors between [node] and the root.
  int fittedAncestorsAbove(RenderObject node) {
    var count = 0;
    RenderObject? cursor = node.parent;
    while (cursor != null) {
      if (cursor is RenderFittedBox) count++;
      cursor = cursor.parent;
    }
    return count;
  }

  /// The Finder for one row's pill label.
  Finder pillLabel({Finder? within}) {
    final pill = within == null
        ? find.byType(EvStatusPill)
        : find.descendant(of: within, matching: find.byType(EvStatusPill));
    return find.descendant(of: pill, matching: find.byType(RichText)).first;
  }

  /// The three invariants that hold at every scale, for one pill.
  ///
  /// Shared by the tile and the sheet so the two cannot drift: no `FittedBox`
  /// above the label, the label painted at >= 11 x the reader's scale, and the
  /// label never ellipsised (the word *is* the colour-blind signal).
  void expectPillAtFloor(WidgetTester tester, Finder label, double scale) {
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(
      fittedAncestorsAbove(paragraph),
      isZero,
      reason:
          'a FittedBox is what painted an 11px label at 8.25px; nothing above '
          'the pill may scale it',
    );
    expect(
      paintedFontSize(tester, label),
      greaterThanOrEqualTo(11.0 * scale),
      reason:
          'the 11px floor (theme_tokens.dart:11) applies at the default text '
          'size too, and it scales with the reader\'s setting',
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason:
          'the status word must stay whole: colour is never the only signal',
    );
  }

  group('LiveRadarTile status pill', () {
    /// The row at its real width: the radar list insets rows by
    /// `EvSpace.gutter` (16px each side) and the tile pads another 16px
    /// internally, so the content box is 256px on a 320dp phone. Without the
    /// gutter a bare tile hands the pill a 233px column and it would fit at
    /// 2.0x — the measurement would then pass on the broken code.
    Widget tileHost(LiveUpdate row) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EvSpace.gutter),
          child: LiveRadarTile(update: row, onTap: () {}, onAlertToggle: () {}),
        ),
      ),
    );

    for (final scale in scales) {
      testWidgets('320x568 @${scale}x paints the label at 11px x scale', (
        tester,
      ) async {
        smallPhone(tester, textScale: scale);
        await tester.pumpWidget(tileHost(update()));

        expectPillAtFloor(tester, pillLabel(), scale);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the row must fit 320dp at every scale — 1.4x used to overflow '
              'by 1.2px in the meta line',
        );
      });
    }

    testWidgets('320x568 @2.0x gives the pill its intrinsic width', (
      tester,
    ) async {
      smallPhone(tester, textScale: 2.0);
      await tester.pumpWidget(tileHost(update()));

      // 233px is the "ADMIT CARD LIVE" pill's intrinsic width at 2.0x; the old
      // 100px column forced the FittedBox to 0.42x.
      expect(
        tester.getRect(find.byType(EvStatusPill)).width,
        greaterThanOrEqualTo(233.0),
        reason: 'the pill is laid out at its natural size, not squeezed',
      );
    });

    testWidgets('320x568 @2.0x does not overflow and keeps the headline', (
      tester,
    ) async {
      smallPhone(tester, textScale: 2.0);
      await tester.pumpWidget(tileHost(update()));

      expect(tester.takeException(), isNull);

      final headline = tester.renderObject<RenderParagraph>(
        find.text('SSC CGL Result 2026'),
      );
      expect(
        headline.didExceedMaxLines,
        isFalse,
        reason: 'the pill no longer competes with the headline for width',
      );

      // Everything else the row carries must survive.
      expect(find.byType(EvStatusPill), findsOneWidget);
      expect(find.text('Direct PDF · 18.4 MB'), findsOneWidget);
      expect(find.text('82ms'), findsOneWidget);
      expect(find.textContaining('m ago'), findsOneWidget);
      expect(
        tester.getSize(
          find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 44 && w.height == 44,
          ),
        ),
        const Size(44, 44),
        reason: 'the alert bell keeps its 44px thumb target',
      );
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('320x568 @${scale}x uses the same full-width pill line', (
        tester,
      ) async {
        // One arrangement at every scale: the pill sits on its own line beneath
        // the copy block and starts at the row's content edge, left of the
        // headline. A `stacked` branch would put it in the right-hand column
        // here instead, and that column is what broke the floor.
        smallPhone(tester, textScale: scale);
        await tester.pumpWidget(tileHost(update()));

        final pillRect = tester.getRect(find.byType(EvStatusPill));
        final headlineRect = tester.getRect(find.text('SSC CGL Result 2026'));
        expect(
          pillRect.top,
          greaterThanOrEqualTo(headlineRect.bottom),
          reason: 'the pill is on its own line, below the headline',
        );
        expect(
          pillRect.left,
          lessThan(headlineRect.left),
          reason: 'it owns the row\'s full content width, not the copy column',
        );
      });
    }

    /// The row's content right edge: the tile pads `EvSpace.x4` on each side.
    double contentRight(WidgetTester tester) =>
        tester.getRect(find.byType(LiveRadarTile)).right - EvSpace.x4;

    testWidgets('320x568 @1.0x keeps the age flush right on the pill line', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      await tester.pumpWidget(tileHost(update()));

      final pillRect = tester.getRect(find.byType(EvStatusPill));
      final ageRect = tester.getRect(find.textContaining('m ago'));
      expect(
        ageRect.right,
        closeTo(contentRight(tester), 1),
        reason: 'the age is the row\'s trailing timestamp, not a stray label',
      );
      expect(
        ageRect.top,
        greaterThanOrEqualTo(pillRect.top),
        reason: 'at 1.0x the age shares the pill\'s line',
      );
      expect(ageRect.bottom, lessThanOrEqualTo(pillRect.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320x568 @2.0x keeps the age flush right on its own run', (
      tester,
    ) async {
      // The regression this pins: the line used to be a
      // `Wrap(alignment: spaceBetween)`, which applies one alignment to every
      // run, and `spaceBetween` places a *lone* child at the run's start
      // (wrap.dart:111). At 2.0x the pill takes 233px of the 256px line, so the
      // age wrapped — and landed at x=32, directly under the pill's left edge,
      // with 189.5px of dead space to its right.
      smallPhone(tester, textScale: 2.0);
      await tester.pumpWidget(tileHost(update()));

      final pillRect = tester.getRect(find.byType(EvStatusPill));
      final ageRect = tester.getRect(find.textContaining('m ago'));
      expect(
        ageRect.right,
        closeTo(contentRight(tester), 1),
        reason:
            'the age stays on the right edge when it drops to its own run — '
            '`WrapAlignment.spaceBetween` left it 189.5px short of it',
      );
      expect(
        ageRect.left,
        greaterThan(pillRect.left),
        reason:
            'the age is not stacked under the pill\'s left edge (x=32 on the '
            'broken layout)',
      );
      expect(
        ageRect.top,
        greaterThanOrEqualTo(pillRect.bottom),
        reason: 'the pill keeps its whole line; the age moves down instead',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Alerts sheet row status pill', () {
    LiveFeed feed() {
      final now = DateTime.now();
      return LiveFeed(
        generatedAt: now,
        revision: 1,
        updates: [
          for (var i = 0; i < 3; i++)
            LiveUpdate(
              examId: 'exam_$i',
              category: ExamCategory.ssc,
              examName: 'SSC CGL Tier-1 2026 notice $i',
              contextLine: 'Direct PDF · 18.4 MB',
              status: UpdateStatus.admitCardLive,
              publishedAt: now.subtract(Duration(minutes: 2 + i)),
              expiresAt: now.add(const Duration(days: 2)),
            ),
        ],
        sources: const [],
      );
    }

    Future<void> openAlerts(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
                    // Keeps the provider alive across the modal route.
                    Builder(
                      builder: (context) {
                        ref.watch(liveFeedProvider);
                        return TextButton(
                          onPressed: () => showAlertsSheet(context, ref),
                          child: const Text('open alerts'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open alerts'));
      await tester.pumpAndSettle();
    }

    /// The first row of the sheet.
    Finder firstRow() => find.ancestor(
      of: find.text('SSC CGL Tier-1 2026 notice 0'),
      matching: find.byType(InkWell),
    );

    for (final scale in scales) {
      testWidgets('320x568 @${scale}x paints the label at 11px x scale', (
        tester,
      ) async {
        smallPhone(tester, textScale: scale);
        await openAlerts(tester);

        expectPillAtFloor(tester, pillLabel(within: firstRow().first), scale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320x568 @2.0x does not clip the headline', (tester) async {
      smallPhone(tester, textScale: 2.0);
      await openAlerts(tester);

      final headline = tester.renderObject<RenderParagraph>(
        find.text('SSC CGL Tier-1 2026 notice 0'),
      );
      expect(headline.didExceedMaxLines, isFalse);

      // Same single arrangement as the tile: the pill is on its own line.
      final pillRect = tester.getRect(
        find.descendant(
          of: firstRow().first,
          matching: find.byType(EvStatusPill),
        ),
      );
      final headlineRect = tester.getRect(
        find.text('SSC CGL Tier-1 2026 notice 0'),
      );
      expect(pillRect.top, greaterThanOrEqualTo(headlineRect.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320x568 @1.0x keeps the row flush with the card content', (
      tester,
    ) async {
      // The row used to be a `Row` (mainAxisSize.max) and filled its card; the
      // Column that replaced it must still fill, or the card's centred Column
      // would indent every row.
      //
      // Anchored to the CARD, not to the row: an earlier version of this test
      // compared `pill.left` with `row.left + 16`, which passes even when the
      // row shrink-wraps and is centred — both rects move together, so it
      // pinned nothing. The card's content box does not move.
      smallPhone(tester, textScale: 1.0);
      await openAlerts(tester);

      final cardRect = tester.getRect(find.byType(EvCard));
      final rowRect = tester.getRect(firstRow().first);
      // No border inset to allow for: EvCard's 1px border is painted by a
      // DecoratedBox *over* its child, so the row spans the card exactly. The
      // alerts card also passes `padding: EdgeInsets.zero`, leaving the row's own
      // 16px padding as the only inset around the row's content.
      expect(rowRect.left, closeTo(cardRect.left, 1));
      expect(rowRect.width, closeTo(cardRect.width, 1));
      expect(tester.takeException(), isNull);
    });
  });
}

/// The paint transform of every `RenderFittedBox` above [node], multiplied.
double _fittedScaleAbove(RenderObject node) {
  var scale = 1.0;
  RenderObject? cursor = node.parent;
  while (cursor != null) {
    if (cursor is RenderFittedBox) {
      final child = cursor.child;
      if (child is RenderBox && child.hasSize && child.size.width > 0) {
        scale *= cursor.size.width / child.size.width;
      }
    }
    cursor = cursor.parent;
  }
  return scale;
}

class _StaticLiveFeed extends LiveFeedNotifier {
  _StaticLiveFeed(this.snapshot);

  final LiveFeedSnapshot snapshot;

  @override
  Future<LiveFeedSnapshot> build() async => snapshot;
}
