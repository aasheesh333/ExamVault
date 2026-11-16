import 'dart:async';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/data/services/share_service.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/share_card/whatsapp_share_card_screen.dart';
import 'package:examvault/features/share_card/widgets/share_infographic.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:share_plus/share_plus.dart';

import 'support/matrix.dart';

/// The share handoff contract, pinned end-to-end.
///
/// The card image is the hero path, but three things can go wrong between
/// "tap Share" and "message sent": the capture fails, the platform refuses the
/// image *after* a successful capture, and the user double-taps while a share
/// is already in flight. In every one of those the caption — with its link —
/// must still leave the app exactly once, and the user must be told when the
/// image did not go out. A silent downgrade lets a student believe a 200-person
/// group received the card when it received nothing.
void main() {
  late Directory hiveDir;
  late Box<dynamic> cacheBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_share_flow');
    Hive.init(hiveDir.path);
    // Real bundled fonts, loaded from the async zone as matrix.dart requires.
    // The tile-label test asserts real line breaking at 2.0x; the test
    // framework's placeholder font is a full em per glyph, so it would report
    // an overflow that no phone shows.
    await loadMatrixFonts();
  });

  setUp(() async {
    // In-memory box (bytes:): a file-backed box opened inside setUp leaves
    // writes pending that the test's fake clock can never drain.
    cacheBox = await Hive.openBox<dynamic>(
      'flow${DateTime.now().microsecondsSinceEpoch}',
      bytes: Uint8List(0),
    );
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Mounts the screen with [share] in place of the real service and one
  /// saved card in the vault. The radar row is selected by default so the
  /// card — and the caption — carry an official link.
  ///
  /// [feedRows] is the live feed the screen re-resolves facts against. It is
  /// always overridden: the real notifier would start its 60 s poll timer and
  /// hit the network from inside a widget test.
  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeShare share, {
    bool withRadarRow = true,
    LiveUpdate? pinnedRow,
    List<AdmitCard>? cards,
    List<LiveUpdate> feedRows = const [],
    Size viewSize = const Size(393, 1400),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          httpCacheBoxProvider.overrideWithValue(cacheBox),
          admitCardsProvider.overrideWith(
            () => _FakeCards(cards ?? [_savedCard()]),
          ),
          liveFeedProvider.overrideWith(() => _FakeFeed(feedRows)),
          shareServiceProvider.overrideWithValue(share),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const WhatsappShareCardScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    if (withRadarRow) {
      // A radar row gives the card an official URL — and the caption a link
      // the fallback text share must carry.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WhatsappShareCardScreen)),
      );
      container
          .read(resultExamIdProvider.notifier)
          .select(pinnedRow ?? _radarRow());
      await tester.pump();
      await tester.pump();
    }
  }

  /// The provider container behind the mounted screen.
  ProviderContainer containerFor(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(WhatsappShareCardScreen)),
      );

  testWidgets('a failed capture falls back to an audible text share', (
    tester,
  ) async {
    final share = _FakeShare(png: null);
    await pumpScreen(tester, share);

    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(
      share.captureCalls,
      3,
      reason:
          'capture is retried at the derived base ratio, then two-thirds and '
          'one-third of it, before giving up',
    );
    expect(share.imageShares, isEmpty);
    expect(share.textShares, hasLength(1));
    expect(
      share.textShares.single,
      contains('https://www.upsc.gov.in/sites/default/files/example.pdf'),
      reason: 'the fallback caption must still carry the link',
    );
    expect(
      find.textContaining('shared the message text instead.'),
      findsOneWidget,
      reason: 'the downgrade must be audible, never silent',
    );
    expect(
      share.clears,
      1,
      reason: 'native shares must prune the PNG cache in a finally',
    );

    await _drainSnack(tester);
  });

  testWidgets('a refused image handoff still sends the caption', (
    tester,
  ) async {
    // The capture succeeded but the platform refused the image (share sheet
    // would not open; browser without Web Share file support). The old catch
    // only snacked "try again" and the captured PNG was silently discarded.
    final share = _FakeShare(
      png: Uint8List.fromList(const [1, 2, 3]),
      imageShareThrows: true,
    );
    await pumpScreen(tester, share);

    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(share.imageShares, hasLength(1), reason: 'the PNG must be offered');
    expect(
      share.textShares,
      hasLength(1),
      reason: 'a successful capture must never be silently discarded',
    );
    expect(
      share.textShares.single,
      contains('upsc.gov.in'),
      reason: 'the fallback caption must still carry the link',
    );
    expect(
      find.textContaining('shared the message text instead.'),
      findsOneWidget,
    );

    await _drainSnack(tester);
  });

  testWidgets('double-tapping Share fires exactly one share', (tester) async {
    // The first capture never completes until released, keeping _share() in
    // flight while the second tap lands.
    final share = _FakeShare(png: null, hangFirstCapture: true);
    await pumpScreen(tester, share);

    await tester.tap(find.text('Share card'));
    await tester.pump(); // _sharing takes effect; the tile disables.

    await tester.tap(find.text('Share card'), warnIfMissed: false);
    await tester.pump();

    expect(
      share.captureCalls,
      1,
      reason: 'the re-entrancy guard must stop the second tap at the door',
    );

    share.releaseCapture();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(share.textShares, hasLength(1));

    await _drainSnack(tester);
  });

  testWidgets('with no link anywhere, Copy link is disabled and inert', (
    tester,
  ) async {
    // No radar row (no official URL) and no EV_WEB_BASE in tests (no app
    // URL): data.link is null, so the tile must announce itself disabled and
    // a tap must not reach the clipboard.
    final clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          clipboardCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpScreen(tester, _FakeShare(png: null), withRadarRow: false);

    expect(find.text('Copy link'), findsOneWidget);

    // The nearest Semantics ancestor is InkWell's own internal node; the
    // tile's declaration is the first ancestor that marks itself a button.
    final semantics = tester
        .widgetList<Semantics>(
          find.ancestor(
            of: find.text('Copy link'),
            matching: find.byType(Semantics),
          ),
        )
        .firstWhere((s) => s.properties.button == true);
    expect(
      semantics.properties.enabled,
      isFalse,
      reason:
          'a tile with nothing to copy must not announce itself as '
          'actionable — TalkBack users otherwise tap it and get silence',
    );

    await tester.tap(find.text('Copy link'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      clipboardCalls.where((c) => c.method == 'Clipboard.setData'),
      isEmpty,
      reason: 'tapping the disabled tile must copy nothing',
    );
    expect(find.textContaining('copied'), findsNothing);
  });

  testWidgets('an explicitly selected card outranks a pinned radar row', (
    tester,
  ) async {
    // Bug: `_cardFor` ignored `selectedCardIdProvider` whenever a radar row was
    // pinned. After any radar tap in the session, swiping the vault pager to
    // another card and opening Share exported the *pinned* exam's card — its
    // exam name and its roll number — and the preview was the only warning.
    await pumpScreen(
      tester,
      _FakeShare(png: null),
      cards: [_savedCard(), _secondCard()],
    );

    containerFor(tester).read(selectedCardIdProvider.notifier).select('card-2');
    await tester.pump();
    await tester.pump();

    expect(
      find.text('5550001'),
      findsOneWidget,
      reason: 'the selected card\'s roll must be the one on the exported card',
    );
    expect(
      find.textContaining('0801786'),
      findsNothing,
      reason: 'the pinned exam\'s roll must not leak onto another exam\'s card',
    );
    expect(
      find.text('ADMIT CARD IS LIVE'),
      findsWidgets,
      reason:
          'a saved admit card has no published result, so the pinned radar '
          'row\'s status must not be borrowed',
    );
    expect(find.textContaining('RESULT IS LIVE'), findsNothing);
    expect(
      find.text('SSC CHSL 2026'),
      // Twice: once on the card, once in the header. `findsWidgets` would be
      // satisfied by the card alone, so deleting the header name would not
      // fail this test.
      findsNWidgets(2),
      reason: 'the header names the exam being exported, above the preview',
    );
    expect(
      find.textContaining('COMBINED SECTION'),
      findsNothing,
      reason: 'the pinned exam\'s name must not appear anywhere on the screen',
    );

    await _drainSnack(tester);
  });

  testWidgets('selecting the pinned exam keeps the radar row in charge', (
    tester,
  ) async {
    // The other half of the rule: when the selection *is* the pinned exam,
    // behaviour is unchanged — the radar row still supplies the status and the
    // official link.
    await pumpScreen(
      tester,
      _FakeShare(png: null),
      cards: [_savedCard(), _secondCard()],
    );

    containerFor(tester).read(selectedCardIdProvider.notifier).select('card-1');
    await tester.pump();
    await tester.pump();

    expect(find.text('RESULT IS LIVE'), findsWidgets);
    expect(
      find.textContaining('0801786'),
      findsWidgets,
      reason: 'the saved card\'s roll stays on the card and in the caption',
    );
    expect(find.textContaining('18.4 MB'), findsOneWidget);

    await _drainSnack(tester);
  });

  testWidgets('a stale awaited row is upgraded to the feed\'s live result', (
    tester,
  ) async {
    // Bug: status, headline, official URL and PDF size were read from the
    // `LiveUpdate` frozen at tap time. The feed repolls every 60 s, so a row
    // tapped while `awaited` kept exporting "UPDATE AWAITED" long after the
    // result had dropped.
    final stale = _awaitedRow();
    await pumpScreen(
      tester,
      _FakeShare(png: null),
      pinnedRow: stale,
      feedRows: [_resultRowWithSize()],
    );

    expect(
      find.textContaining('UPDATE AWAITED'),
      findsNothing,
      reason: 'the tapped row is only a fallback, never the source of truth',
    );
    expect(
      find.text('RESULT IS LIVE'),
      findsWidgets,
      reason: 'the feed says the result is out, so the card must say so too',
    );
    expect(
      find.textContaining('18.4 MB'),
      findsOneWidget,
      reason: 'the fresh row\'s PDF size travels with the fresh status',
    );

    await _drainSnack(tester);
  });

  testWidgets('a dismissed share sheet does not claim the text was sent', (
    tester,
  ) async {
    // Bug: the fallback snackbar was unconditional, so dismissing the sheet
    // still reported "shared the message text instead" — the app claimed a
    // handoff the platform had explicitly said did not happen.
    final share = _FakeShare(
      png: null,
      textStatus: ShareResultStatus.dismissed,
    );
    await pumpScreen(tester, share);

    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(share.textShares, hasLength(1), reason: 'the caption was offered');
    expect(
      find.textContaining('Nothing was sent'),
      findsOneWidget,
      reason: 'a dismissed sheet must not be reported as a successful share',
    );
    expect(
      find.textContaining('shared the message text instead'),
      findsNothing,
    );

    await _drainSnack(tester);
  });

  testWidgets('an unconfirmable share is neither success nor "nothing sent"', (
    tester,
  ) async {
    // `unavailable` means the platform shared but could not report what the
    // user did (web builds, older Android). Saying "Nothing was sent" asserts a
    // negative nobody observed; saying it was shared asserts a positive nobody
    // observed. The only honest line points at the caption the user still has.
    final share = _FakeShare(
      png: null,
      textStatus: ShareResultStatus.unavailable,
    );
    await pumpScreen(tester, share);

    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(
      find.textContaining('Could not confirm the share'),
      findsOneWidget,
      reason: 'an unknown outcome must be reported as unknown',
    );
    expect(find.textContaining('Nothing was sent'), findsNothing);
    expect(
      find.textContaining('shared the message text instead'),
      findsNothing,
    );

    await _drainSnack(tester);
  });

  testWidgets('a dismissed image share is reported, not silent', (
    tester,
  ) async {
    // Bug: the image path discarded its ShareResult, so a dismissed sheet said
    // nothing at all — inconsistent with the text path now telling the truth.
    final share = _FakeShare(
      png: Uint8List.fromList(const [1, 2, 3]),
      imageStatus: ShareResultStatus.dismissed,
    );
    await pumpScreen(tester, share);

    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(share.imageShares, hasLength(1), reason: 'the PNG was offered');
    expect(
      find.textContaining('Nothing was sent'),
      findsOneWidget,
      reason: 'a dismissed image share must be audible, never silent',
    );
    expect(
      find.textContaining('shared the message text instead'),
      findsNothing,
    );

    await _drainSnack(tester);
  });

  testWidgets('the capture ratio is derived from the capped card width', (
    tester,
  ) async {
    // Bug: a flat 3x made the PNG width a property of the window — 1194 px on a
    // 430 dp phone, ~2300 px (a ~27 MB bitmap) in a desktop-web window. The
    // card is now capped at 400 dp and the ratio follows the laid-out width.
    final share = _FakeShare(png: Uint8List.fromList(const [1, 2, 3]));
    await pumpScreen(
      tester,
      share,
      viewSize: const Size(1200, 900),
      withRadarRow: false,
    );

    final cardWidth = tester.getSize(find.byType(ShareInfographic)).width;
    expect(
      cardWidth,
      lessThanOrEqualTo(400),
      reason: 'the captured card must not grow with the window',
    );

    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.captureRatios, hasLength(1));
    expect(
      share.captureRatios.single * cardWidth,
      closeTo(1080, 1),
      reason: 'the export is ~1080 px wide on any device',
    );
    expect(
      share.captureRatios.single,
      lessThanOrEqualTo(3.0),
      reason: 'the ratio is clamped, not unbounded on a wide window',
    );

    await _drainSnack(tester);
  });

  testWidgets('the share tile label is never truncated at 2.0x', (
    tester,
  ) async {
    // Bug: `SizedBox(width: 88)` + `maxLines: 2` + ellipsis rendered "Copy
    // official link" as "Copy / officia…" — a label the user cannot finish
    // reading on the tile that copies the commission's own link.
    //
    // 319.5 dp is the fractional case: three 94 dp tiles plus the gutters must
    // still fit when the viewport is a half-pixel under the 320 dp floor, so a
    // future gutter change cannot turn the row into a RenderFlex overflow.
    for (final width in const [320.0, 319.5]) {
      await pumpScreen(
        tester,
        _FakeShare(png: null),
        viewSize: Size(width, 1600),
        textScale: 2.0,
      );

      final label = find.text('Copy official link');
      expect(label, findsOneWidget, reason: 'at ${width}dp');

      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason:
            'every word of the label must fit at ${width}dp — nothing may be '
            'ellipsised',
      );
      expect(
        paragraph.text.toPlainText(),
        'Copy official link',
        reason: 'the full label, not a fragment',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow at ${width}dp',
      );
    }

    await _drainSnack(tester);
  });
}

/// The share service, faked. Records every call; performs none of the I/O.
class _FakeShare extends ShareService {
  _FakeShare({
    required this.png,
    this.imageShareThrows = false,
    this.hangFirstCapture = false,
    this.textStatus = ShareResultStatus.success,
    this.imageStatus = ShareResultStatus.success,
  });

  /// What [capturePng] hands back (null → the screen's text fallback).
  final Uint8List? png;

  /// True → [shareCardImage] throws after recording, modelling a platform
  /// that refuses the image handoff.
  final bool imageShareThrows;

  /// True → the first [capturePng] call parks on a Completer until
  /// [releaseCapture], modelling a slow capture so a second tap can land
  /// while the first share is still in flight.
  final bool hangFirstCapture;

  /// What the platform reports for a text share. `dismissed` models the user
  /// closing the sheet without picking a target.
  final ShareResultStatus textStatus;

  /// What the platform reports for an image share.
  final ShareResultStatus imageStatus;

  Completer<Uint8List?>? _gate;

  int captureCalls = 0;
  int clears = 0;
  final List<double> captureRatios = [];
  final List<String> textShares = [];
  final List<String> imageShares = [];

  void releaseCapture() => _gate?.complete(png);

  @override
  Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 3.0}) {
    captureCalls++;
    captureRatios.add(pixelRatio);
    if (hangFirstCapture && captureCalls == 1) {
      return (_gate = Completer<Uint8List?>()).future;
    }
    return Future.value(png);
  }

  @override
  Future<ShareResult> shareCardImage({
    required Uint8List png,
    required String caption,
    required String subject,
    Rect? origin,
    String fileName = 'examvault_result.png',
  }) async {
    imageShares.add(caption);
    if (imageShareThrows) throw StateError('platform refused the image');
    return ShareResult('', imageStatus);
  }

  @override
  Future<ShareResult> shareText({
    required String caption,
    required String subject,
    Rect? origin,
  }) async {
    textShares.add(caption);
    return ShareResult('', textStatus);
  }

  @override
  Future<void> clearCache() async => clears++;
}

class _FakeCards extends AdmitCardsNotifier {
  _FakeCards(this.cards);

  final List<AdmitCard> cards;

  @override
  Future<List<AdmitCard>> build() async => cards;
}

class _FakeFeed extends LiveFeedNotifier {
  _FakeFeed(this.updates);

  final List<LiveUpdate> updates;

  @override
  Future<LiveFeedSnapshot> build() async => LiveFeedSnapshot(
    feed: LiveFeed(
      generatedAt: DateTime(2026, 11, 16),
      updates: updates,
      revision: 1,
    ),
    source: FeedSource.network,
    fetchedAt: DateTime(2026, 11, 16),
  );
}

/// A SnackBar keeps a 4-second dismiss Timer alive; advance past it and settle
/// the exit animation so teardown does not report a pending timer.
Future<void> _drainSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

AdmitCard _savedCard() => AdmitCard(
  id: 'card-1',
  examId: 'upsc_ldce_2025',
  category: ExamCategory.upsc,
  examName: 'Combined Section Officers',
  conductingBody: 'UPSC',
  examCode: 'LDCE',
  rollNumber: '0801786',
  registrationId: 'R1',
  dobOrPortalPassword: '01/01/1990',
  centerCode: 'DL-01',
  centerAddress: 'New Delhi',
  gate: 'Gate 1',
  reportBy: '09:00 AM',
  examDate: DateTime(2026, 12, 1),
  shift: '10:00 AM',
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  rollNumberVerified: true,
);

LiveUpdate _radarRow() => LiveUpdate(
  examId: 'upsc_ldce_2025',
  category: ExamCategory.upsc,
  examName: 'Combined Section Officers',
  contextLine: 'Official PDF · upsc.gov.in',
  status: UpdateStatus.resultOut,
  publishedAt: DateTime(2026, 11, 10),
  officialPdf: 'https://www.upsc.gov.in/sites/default/files/example.pdf',
  pdfSizeLabel: '18.4 MB',
);

/// A row tapped before the commission published anything.
LiveUpdate _awaitedRow() => LiveUpdate(
  examId: 'upsc_ldce_2025',
  category: ExamCategory.upsc,
  examName: 'Combined Section Officers',
  contextLine: 'Notice · upsc.gov.in',
  status: UpdateStatus.awaited,
  publishedAt: DateTime(2026, 11, 9),
  officialPage: 'https://www.upsc.gov.in/whats-new',
);

/// The same exam, after the feed repolled and the result dropped.
LiveUpdate _resultRowWithSize() => LiveUpdate(
  examId: 'upsc_ldce_2025',
  category: ExamCategory.upsc,
  examName: 'Combined Section Officers',
  contextLine: 'Official PDF · upsc.gov.in',
  status: UpdateStatus.resultOut,
  publishedAt: DateTime(2026, 11, 16),
  officialPdf: 'https://www.upsc.gov.in/sites/default/files/example.pdf',
  pdfSizeLabel: '18.4 MB',
);

/// A second saved card, for the exam whose selection must outrank the pin.
AdmitCard _secondCard() => AdmitCard(
  id: 'card-2',
  examId: 'ssc_chsl_2026',
  category: ExamCategory.ssc,
  examName: 'SSC CHSL 2026',
  conductingBody: 'SSC',
  examCode: 'CHSL',
  rollNumber: '5550001',
  registrationId: 'R2',
  dobOrPortalPassword: '02/02/1991',
  centerCode: 'MH-02',
  centerAddress: 'Mumbai',
  gate: 'Gate 2',
  reportBy: '10:00 AM',
  examDate: DateTime(2026, 12, 5),
  shift: '11:00 AM',
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);
