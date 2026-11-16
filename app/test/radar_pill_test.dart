import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/core/theme/theme_tokens.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/command_center/widgets/alerts_sheet.dart';
import 'package:examvault/features/command_center/widgets/live_radar_tile.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The radar status pill must never paint below the 11px type floor.
///
/// The defect this file locks down: `LiveRadarTile` and `alerts_sheet.dart`'s
/// `_AlertRow` each gave the pill a narrow right-hand column and wrapped it in
/// `FittedBox(fit: BoxFit.scaleDown)`. At 320dp with 2.0x text the pill's
/// intrinsic width is 233px against a ~100px column, so the box painted the
/// 11px label at ~9.5 logical px — under `theme_tokens.dart:11`'s floor and
/// *smaller* than at 1.0x, on the exact setting the reader raised because they
/// could not read it.
///
/// "Nothing overflows" was the assertion that hid this: scaling is precisely
/// what kept the row from overflowing. These tests therefore measure the label
/// the user actually sees — declared size x the enclosing text scaler x the
/// paint transform of every `RenderFittedBox` above it — and separately assert
/// that no `FittedBox` sits above the pill on the large-text path at all.
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
  /// row did to it, which is exactly how the 9.5px paint went unnoticed.
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

    testWidgets('320x568 @2.0x paints the label at its token size', (
      tester,
    ) async {
      smallPhone(tester, textScale: 2.0);
      await tester.pumpWidget(tileHost(update()));

      final label = pillLabel();
      expect(
        fittedAncestorsAbove(tester.renderObject<RenderParagraph>(label)),
        isZero,
        reason:
            'the FittedBox is what painted an 11px label at ~9.5px; the '
            'large-text path must not scale the pill at all',
      );
      expect(
        paintedFontSize(tester, label),
        greaterThanOrEqualTo(11.0),
        reason:
            'the 11px floor (theme_tokens.dart:11) is the whole point of the '
            'stacked layout',
      );
      expect(
        tester.getRect(find.byType(EvStatusPill)).width,
        greaterThanOrEqualTo(233.0),
        reason:
            'at 2.0x the pill must be laid out at its intrinsic 233px width, '
            'not squeezed into a column',
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
        reason: 'stacking gives the headline the full row, not a sliver',
      );

      // Everything else the row carries must survive the stack.
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

      // The pill and the age share the line beneath the copy block.
      final pillRect = tester.getRect(find.byType(EvStatusPill));
      final headlineRect = tester.getRect(find.text('SSC CGL Result 2026'));
      expect(
        pillRect.top,
        greaterThanOrEqualTo(headlineRect.bottom),
        reason: 'the pill moves below the headline at large text',
      );
    });

    testWidgets('320x568 @1.0x keeps the single-line right-hand column', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      await tester.pumpWidget(tileHost(update()));

      final pillRect = tester.getRect(find.byType(EvStatusPill));
      final headlineRect = tester.getRect(find.text('SSC CGL Result 2026'));

      expect(
        pillRect.left,
        greaterThan(headlineRect.right),
        reason:
            'at 1.0x the pill still sits in the column to the right of the '
            'copy block — the arrangement the brief says to keep identical',
      );
      expect(
        pillRect.center.dy,
        lessThan(headlineRect.bottom),
        reason: 'same line as the headline, not a line below it',
      );
      // The pre-change row measured 109px tall for this fixture at 320dp @1.0x;
      // the stacked branch must not be reachable at 1.0x.
      expect(tester.getSize(find.byType(LiveRadarTile)).height, 109.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320x568 @1.4x is still the single-line arrangement', (
      tester,
    ) async {
      // The cut is "> 1.4", not ">= 1.4": a future tweak to the threshold in
      // one widget but not the other would show up here.
      //
      // No overflow assertion on this path: at 320dp @1.4x the *unchanged*
      // meta line already overflows by 1.2px (latency chip + 44px bell inside
      // a 100.5px copy column). That predates this change — measured on the
      // pre-fix file — and fixing it would mean editing the ≤1.4x arrangement
      // the brief freezes. Reported as a follow-up instead.
      smallPhone(tester, textScale: 1.4);
      await tester.pumpWidget(tileHost(update()));
      // The overflow is a paint-time diagnostic; drain it so the structural
      // assertions below are the only thing this test speaks to.
      tester.takeException();

      final pillRect = tester.getRect(find.byType(EvStatusPill));
      final headlineRect = tester.getRect(find.text('SSC CGL Result 2026'));
      expect(pillRect.left, greaterThan(headlineRect.right));
      expect(pillRect.center.dy, lessThan(headlineRect.bottom));
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

    testWidgets('320x568 @2.0x paints the label at its token size', (
      tester,
    ) async {
      smallPhone(tester, textScale: 2.0);
      await openAlerts(tester);

      final label = pillLabel(within: firstRow().first);
      expect(
        fittedAncestorsAbove(tester.renderObject<RenderParagraph>(label)),
        isZero,
        reason:
            'the sheet row must follow the radar tile onto the stacked path',
      );
      expect(
        paintedFontSize(tester, label),
        greaterThanOrEqualTo(11.0),
        reason: 'the 11px floor applies to the sheet too',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('320x568 @2.0x does not clip the headline', (tester) async {
      smallPhone(tester, textScale: 2.0);
      await openAlerts(tester);

      final headline = tester.renderObject<RenderParagraph>(
        find.text('SSC CGL Tier-1 2026 notice 0'),
      );
      expect(headline.didExceedMaxLines, isFalse);

      // The pill is on its own line beneath the copy block.
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

    testWidgets('320x568 @1.0x keeps the pill in the right-hand column', (
      tester,
    ) async {
      smallPhone(tester, textScale: 1.0);
      await openAlerts(tester);

      final pillRect = tester.getRect(
        find.descendant(
          of: firstRow().first,
          matching: find.byType(EvStatusPill),
        ),
      );
      final headlineRect = tester.getRect(
        find.text('SSC CGL Tier-1 2026 notice 0'),
      );
      expect(
        pillRect.left,
        greaterThan(headlineRect.right),
        reason: 'the 1.0x arrangement is unchanged',
      );
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
