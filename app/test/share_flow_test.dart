import 'dart:async';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/services/share_service.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/share_card/whatsapp_share_card_screen.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:share_plus/share_plus.dart';

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
  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeShare share, {
    bool withRadarRow = true,
  }) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          httpCacheBoxProvider.overrideWithValue(cacheBox),
          admitCardsProvider.overrideWith(() => _FakeCards([_savedCard()])),
          shareServiceProvider.overrideWithValue(share),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
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
      container.read(resultExamIdProvider.notifier).select(_radarRow());
      await tester.pump();
      await tester.pump();
    }
  }

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
      reason: 'capture is retried at 3x, 2x and 1x before giving up',
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
}

/// The share service, faked. Records every call; performs none of the I/O.
class _FakeShare extends ShareService {
  _FakeShare({
    required this.png,
    this.imageShareThrows = false,
    this.hangFirstCapture = false,
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

  Completer<Uint8List?>? _gate;

  int captureCalls = 0;
  int clears = 0;
  final List<String> textShares = [];
  final List<String> imageShares = [];

  void releaseCapture() => _gate?.complete(png);

  @override
  Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 3.0}) {
    captureCalls++;
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
    return ShareResult.unavailable;
  }

  @override
  Future<ShareResult> shareText({
    required String caption,
    required String subject,
    Rect? origin,
  }) async {
    textShares.add(caption);
    return ShareResult.unavailable;
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
