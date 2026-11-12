import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The state-matrix harness.
///
/// ## Why this exists
///
/// Three rounds of "an agent looks at screenshots" each found bugs in a *different*
/// place. That method structurally cannot see a 3px misalignment, a state nobody
/// captured, a tap that lands on the wrong widget, or every combination of
/// screen × state × size × text scale × theme.
///
/// These assertions are mechanical, so they hold for combinations no human would
/// sit and eyeball. Each one encodes a bug that shipped:
///
///  * [expectRenders/expectClean] — RenderFlex overflow (the 107px pass footer).
///  * [expectHitTestable] — content under the floating dock / tab bar (the
///    checklist row that fired "Check my result", the CTA under the tab bar).
///  * [expectTapTargets] — 36px icon buttons, 32px close buttons.
///  * [expectNoClippedText] — text cut mid-word with no ellipsis.
///  * [expectInsideViewport] — anything laid out off-screen.

/// A screen size / text scale / theme the product must survive.
@immutable
class MatrixPoint {
  const MatrixPoint({
    required this.name,
    required this.width,
    required this.height,
    required this.textScale,
    required this.dark,
  });

  final String name;
  final double width;
  final double height;
  final double textScale;
  final bool dark;

  @override
  String toString() =>
      '$name ${width.toInt()}x${height.toInt()} @${textScale}x '
      '${dark ? 'dark' : 'light'}';
}

/// The points we assert every screen against.
///
/// 320 is the smallest Android phone still in use; 430 is a large iPhone. 0.9 and
/// 2.0 are the clamp's endpoints, so both are reachable by a real user.
const matrixPoints = <MatrixPoint>[
  MatrixPoint(
    name: 'small',
    width: 320,
    height: 568,
    textScale: 1.0,
    dark: true,
  ),
  MatrixPoint(
    name: 'default',
    width: 393,
    height: 852,
    textScale: 1.0,
    dark: true,
  ),
  MatrixPoint(
    name: 'large',
    width: 430,
    height: 932,
    textScale: 1.0,
    dark: true,
  ),
  MatrixPoint(
    name: 'scaled135',
    width: 393,
    height: 852,
    textScale: 1.35,
    dark: true,
  ),
  MatrixPoint(
    name: 'scaled200',
    width: 393,
    height: 852,
    textScale: 2.0,
    dark: true,
  ),
  MatrixPoint(
    name: 'scaled200small',
    width: 320,
    height: 568,
    textScale: 2.0,
    dark: true,
  ),
  MatrixPoint(
    name: 'light',
    width: 393,
    height: 852,
    textScale: 1.0,
    dark: false,
  ),
  MatrixPoint(
    name: 'shrunk',
    width: 393,
    height: 852,
    textScale: 0.9,
    dark: true,
  ),
];

/// An in-memory vault. `hang` reproduces the platform-channel stall;
/// `fail` reproduces a Keystore reset.
class MatrixVaultStore implements SecureVaultStore {
  MatrixVaultStore({
    this.cards = const [],
    this.hang = false,
    this.fail = false,
  });

  final List<AdmitCard> cards;
  final bool hang;
  final bool fail;

  final Map<String, String> _raw = {};

  Future<void> _maybeFail() async {
    if (fail) throw StateError('keystore unavailable');
    // A Completer, not `Future.delayed`: the delay is a real Timer, which the test
    // framework correctly reports as pending at teardown. Never completing models
    // the hang without scheduling anything.
    if (hang) return Completer<void>().future;
  }

  @override
  Future<List<String>> readIndex() async {
    if (hang) return Completer<List<String>>().future;
    await _maybeFail();
    return cards.map((c) => c.id).toList();
  }

  @override
  Future<String?> readRaw(String id) async {
    await _maybeFail();
    for (final c in cards) {
      if (c.id == id) return AdmitCardCodec.encode(c);
    }
    return _raw[id];
  }

  @override
  Future<void> writeIndex(List<String> ids) async {}

  @override
  Future<void> writeRaw(String id, String payload) async {
    _raw[id] = payload;
  }

  @override
  Future<void> deleteRaw(String id) async {
    _raw.remove(id);
  }

  @override
  Future<Map<String, String>> readAllRaw() async => Map.of(_raw);

  @override
  Future<void> wipe() async => _raw.clear();
}

/// The feed the matrix renders against. Mirrors the real wire format.
///
/// `full: true` adds the wire variants the original four hand-written rows never
/// carried: the `awaited` / `answer_key` pill labels, a page-only row (no PDF),
/// size and mirror-latency metadata, a publisher-expired row, and a 95-character
/// Devanagari exam name. Together with `rows: 60` they let the matrix see states
/// it was blind to — every pill width, both link flavours, expiry filtering and
/// non-Latin glyph advances at 320px.
///
/// Requesting more `rows` than there are samples now generates filler rows
/// instead of silently clamping: the old `i < samples.length` guard meant a
/// "60-row feed" state rendered four rows, so long-list behaviour (sliver
/// recycling, scroll depth, "9+" badge counts) was unreachable from the matrix.
String matrixFeedJson({int rows = 4, bool empty = false, bool full = false}) {
  final updates = <Map<String, dynamic>>[];
  if (!empty) {
    final samples = <Map<String, dynamic>>[
      {
        'exam_name': 'RRB CEN 09/2026 · Notification',
        'category': 'railways',
        // The longest status label in the app ("ADMIT CARD LIVE"): the fixture
        // used to only carry short statuses, so the matrix never exercised the
        // pill widths that overflow on a 320px row.
        'status': 'admit_card_live',
        'context': 'Railway Recruitment Board · 9 Nov 2026',
      },
      {
        'exam_name':
            'Identity Verification (IV) for the candidates '
            'shortlisted in FRTA of Combined Hindi Translators Examination',
        'category': 'ssc',
        'status': 'result_out',
        'context': 'Notice board · ssc.gov.in',
        'index_available': true,
        'index_version': 'abc123abc123',
        'roll_count': 2526,
      },
      {
        'exam_name':
            'Final Result: Combined Section Officers (Grade B) LDCE-2025',
        'category': 'upsc',
        'status': 'result_out',
        'context': 'Official PDF · upsc.gov.in',
        'index_available': true,
        'index_version': 'def456def456',
        'roll_count': 30,
      },
      {
        'exam_name': 'TNPSC 01/2024 · COMBINED CIVIL SERVICES EXAMINATION-IV',
        'category': 'state_psc',
        'status': 'form_closing',
        'context': 'Registration closes 15 Nov 2026',
      },
    ];
    if (full) {
      samples.addAll([
        {
          // `awaited`: the one status whose pill label ("AWAITED") and default
          // 90-day TTL no matrix cell had ever rendered.
          'exam_name': 'IBPS PO Phase-III · Interview schedule',
          'category': 'banking',
          'status': 'awaited',
          'context': 'Result expected by 30 Nov 2026',
        },
        {
          // `answer_key` plus the pdf_size label the row footer renders.
          'exam_name': 'SSC CGL Tier-1 2026 · Answer key released',
          'category': 'ssc',
          'status': 'answer_key',
          'context': 'Objections open till 14 Nov 2026 · ssc.gov.in',
          'pdf_size': '2.7 MB',
        },
        {
          // Page-only row: `official_page` with the default `official_pdf`
          // explicitly nulled, so the "Official site" button (not "Official
          // PDF") and its icon get exercised. A row carrying neither link is
          // rejected by the feed validator and must not be fabricated here.
          'exam_name':
              'UPSC Engineering Services (Mains) 2026 · Personality test '
              'schedule published as a notice, not a document',
          'category': 'upsc',
          'status': 'form_closing',
          'context': 'Notice board · upsc.gov.in',
          'official_pdf': null,
          'official_page': 'https://upsc.gov.in/notices/esm-2026-pt',
        },
        {
          // Mirror latency of 4820ms: the radar row's "slow mirror" styling,
          // and a latency wide enough to wrap on a 320px row.
          'exam_name': 'RRB NTPC CBT-2 · City intimation and travel advisory',
          'category': 'railways',
          'status': 'admit_card_live',
          'context': 'Fastest mirror measured 20 min ago',
          'mirror_latency_ms': 4820,
        },
        {
          // Already expired on the publisher's side: the row must be filtered
          // out of the live list and badge counts, while the fixture proves
          // the filter actually runs.
          'exam_name': 'BPSC 70th CCE · Preliminary result (retired notice)',
          'category': 'state_psc',
          'status': 'result_out',
          'context': 'Withdrawn by the commission',
          'expires_at': DateTime.now()
              .subtract(const Duration(days: 3))
              .toUtc()
              .toIso8601String(),
        },
        {
          // Exactly 95 characters of Devanagari — the widest glyphs and the
          // longest single-field string the feed can carry. Wrapped line
          // breaking, matra overhang and ellipsis behaviour all differ from
          // Latin text; the matrix had only ever measured Latin.
          'exam_name':
              'यूपीएससी द्वारा आयोजित सिविल सेवाएं प्रारंभिक परीक्षा 2027 का '
              'अंतिम परिणाम, उत्तर-पुस्तिका सहित',
          'category': 'upsc',
          'status': 'result_out',
          'context': 'आधिकारिक वेबसाइट · upsc.gov.in',
          'index_available': true,
          'index_version': 'hin789hin789',
          'roll_count': 1421,
        },
      ]);
    }
    for (var i = 0; i < rows; i++) {
      final sample = i < samples.length ? samples[i] : _generatedSample(i);
      updates.add({
        'exam_id': 'exam_$i',
        'published_at': DateTime.now()
            .subtract(Duration(hours: i * 7 + 1))
            .toUtc()
            .toIso8601String(),
        'source': 'test',
        'source_id': 'test',
        'official_pdf': 'https://example.gov.in/list.pdf',
        ...sample,
      });
    }
  }
  return jsonEncode({
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'revision': 1,
    'sources': [
      {
        'id': 'ssc',
        'label': 'SSC',
        'status': 'ok',
        'rows': 17,
        'homepage': 'https://ssc.gov.in/',
      },
      {
        'id': 'upsc',
        'label': 'UPSC',
        'status': 'unavailable',
        'rows': 0,
        'reason': 'HTTP 503',
      },
    ],
    'updates': updates,
  });
}

/// Synthetic filler for `rows` beyond the hand-written samples (generator mode).
///
/// Cycles categories and statuses so a long feed is not one repeated row: the
/// list must still exercise every pill colour and category label at row 59, and
/// the ages spread across weeks so the "N live updates" and badge counts see a
/// realistic mix.
Map<String, dynamic> _generatedSample(int i) {
  const categories = ['ssc', 'upsc', 'banking', 'railways', 'state_psc'];
  const statuses = [
    'result_out',
    'admit_card_live',
    'form_closing',
    'answer_key',
    'awaited',
  ];
  final category = categories[i % categories.length];
  return {
    'exam_name':
        'Generated notice ${i + 1} · $category recruitment bulletin for the '
        'current cycle with a deliberately long single-line name',
    'category': category,
    'status': statuses[i % statuses.length],
    'context': 'Generated row ${i + 1} · example.gov.in',
  };
}

/// Builds a card with intentionally awkward content so the layout is stressed.
///
/// [checklist] exists because the sparse-fields variant needs a *non-empty*
/// checklist to prove the tick rows render while every other optional field is
/// empty — it used to be hardcoded `const {}`, so the checklist UI was never
/// exercised by the matrix at all.
AdmitCard matrixCard({
  String id = 'card_a',
  String candidateName = '',
  String examName = 'SSC CGL Tier-1 2026',
  String roll = '2201098765',
  String centerAddress = 'Sector 9, Rohini, New Delhi',
  String centerCode = 'DL-07-2210',
  String gate = 'Gate 2',
  String reportBy = '08:00 AM',
  String shift = '10:00 AM – 11:00 AM',
  int daysFromNow = 9,
  bool verified = false,
  String registrationId = 'SSC-CHSL-26-441122',
  String dorOrPassword = '11/05/1998',
  String conductingBody = 'Staff Selection Commission',
  String examCode = 'CGL · TIER-1',
  ExamCategory category = ExamCategory.ssc,
  Set<ChecklistItem> checklist = const {},
}) => AdmitCard(
  candidateName: candidateName,
  id: id,
  examId: 'exam_$id',
  category: category,
  examName: examName,
  conductingBody: conductingBody,
  examCode: examCode,
  rollNumber: roll,
  registrationId: registrationId,
  dobOrPortalPassword: dorOrPassword,
  centerCode: centerCode,
  centerAddress: centerAddress,
  gate: gate,
  reportBy: reportBy,
  examDate: DateTime.now().add(Duration(days: daysFromNow)),
  shift: shift,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
  rollNumberVerified: verified,
  checklist: checklist,
);

/// Hive boxes for one matrix test.
///
/// Opened in `setUp`, never inside `testWidgets`: box opening is real file I/O,
/// and `testWidgets` runs on a fake clock, so awaiting it inside the test body
/// never completes and the test times out.
class MatrixEnv {
  MatrixEnv({required this.cacheBox, required this.settingsBox, this.dir});

  final Box<dynamic> cacheBox;
  final Box<dynamic> settingsBox;
  final Directory? dir;

  /// A fresh, **in-memory** box pair.
  ///
  /// Deliberately not file-backed and deliberately not shared between tests:
  /// a `CdnClient` write queued in test N is still pending when test N+1 opens,
  /// and a file-backed box's `clear()` then waits behind that write forever on the
  /// fake test clock. Memory boxes have no queue and no disk, so each test starts
  /// genuinely clean.
  static Future<MatrixEnv> open() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final cacheBox = await Hive.openBox<dynamic>(
      'c$stamp',
      bytes: Uint8List(0),
    );
    final settingsBox = await Hive.openBox<dynamic>(
      's$stamp',
      bytes: Uint8List(0),
    );
    return MatrixEnv(cacheBox: cacheBox, settingsBox: settingsBox, dir: null);
  }

  Future<void> close() async {
    // Nothing to flush: the boxes are in memory.
  }
}

/// The bundled typefaces, loaded once per test isolate.
///
/// WHY: pumpMatrix used to lay out against flutter_test's square-glyph fallback
/// font, so every width-driven assertion — right-edge overflow, flex fit, the
/// FittedBox scale-down, status-pill widths — measured advances no user ever
/// sees. Real text is wider in places, which is exactly where the matrix has to
/// look. Block copied from sheets_test.dart (which already did this for the same
/// reason); the guard keeps 200+ pumps from re-reading seven font files.
///
/// WHY the boolean flag and not just a cached Future: a Future created inside
/// one `testWidgets` body belongs to that test's FakeAsync zone. Once it has
/// completed, `await`ing it from the *next* test schedules the continuation in
/// the dead zone's microtask queue, which nothing ever drains — every
/// subsequent test hangs at the await. The synchronous flag makes every call
/// after the first return a Future created (and completed) in the caller's own
/// zone, which the binding always flushes.
///
/// Suites should also call this once from `setUpAll`: there the load runs on
/// the real event loop, clear of the fake clock entirely.
bool _fontsLoaded = false;
Future<void>? _fontsLoading;

Future<void> loadMatrixFonts() async {
  if (_fontsLoaded) return;
  await (_fontsLoading ??= _loadBundledFonts());
  _fontsLoaded = true;
}

Future<void> _loadBundledFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
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
        ..addFont(rootBundle.load('assets/google_fonts/IBMPlexMono-Medium.ttf'))
        ..addFont(
          rootBundle.load('assets/google_fonts/IBMPlexMono-SemiBold.ttf'),
        ))
      .load();
}

/// Mounts [home] at a matrix point with a fake vault and a canned feed.
Future<void> pumpMatrix(
  WidgetTester tester,
  Widget home,
  MatrixPoint point, {
  required MatrixEnv env,
  List<AdmitCard> cards = const [],
  bool hangVault = false,
  bool failVault = false,
  int feedRows = 4,
  bool emptyFeed = false,
  bool fullFeed = false,
}) async {
  await loadMatrixFonts();
  // Loading and error are *UI* states, so they are injected directly rather than
  // simulated with a hanging storage read. A hanging read pulls the repository's
  // real 5-second timeout timer into the test, which then has to be drained and
  // adds noise to every teardown. A never-completing Completer schedules nothing.
  Future<List<AdmitCard>> Function()? cardsAsync;
  if (hangVault) {
    cardsAsync = () => Completer<List<AdmitCard>>().future;
  } else if (failVault) {
    cardsAsync = () =>
        Future<List<AdmitCard>>.error(StateError('keystore unavailable'));
  }
  tester.view.physicalSize = Size(point.width, point.height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cacheBox = env.cacheBox;
  final settingsBox = env.settingsBox;

  final feed = matrixFeedJson(rows: feedRows, empty: emptyFeed, full: fullFeed);
  final mock = MockClient((req) async {
    if (req.url.path.contains('live_feed')) {
      // Explicit UTF-8 content-type, like the real edge document. Without it
      // the `http` package's Response(String) constructor encodes the body as
      // latin1, and the full feed's Devanagari exam name (code units > 255)
      // made the MOCK throw — which CdnClient classified as a transient
      // network error, sending every fullFeed cell into retry backoff and
      // leaking pending timers into teardown.
      return http.Response(
        feed,
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('', 404);
  });

  captureFrameworkErrors(tester);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: MatrixVaultStore(cards: cards)),
        ),
        if (cardsAsync != null)
          admitCardsProvider.overrideWith(() => _InjectedCards(cardsAsync!)),
        cdnClientProvider.overrideWithValue(
          CdnClient(cache: cacheBox, client: mock, baseUrl: 'https://cdn.test'),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: point.dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(point.textScale),
            padding: const EdgeInsets.only(bottom: 24),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );

  // Unmount on teardown as well as explicitly: a failed assertion aborts the test
  // body before `disposeMatrix` runs, and the app's 60-second feed poll then stays
  // alive into the next test, where the fake clock can never drain it. Registering
  // it here means the timer is always cancelled.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Advance past the repository's 5s secure-storage timeout. That timeout is a
    // real Timer (and is correct product behaviour — it stops a hung Keystore from
    // stranding the UI), but it outlives the widget tree, so it must be drained or
    // teardown reports it as pending.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });

  // One frame to build, one to settle layout, one to let post-frame callbacks
  // (vault load, feed refresh, dock measurement) run.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

/// Fails on any exception, RenderFlex overflow included.
///
/// `takeException()` hands back a shortened `FlutterError`, which drops the
/// "relevant error-causing widget" block — the `file:line` needed to act on the
/// finding. Capturing `FlutterErrorDetails` while the frame runs keeps it.
void expectClean(WidgetTester tester, {String? because}) {
  final error = tester.takeException();

  final detail = _lastErrorDetail;
  _lastErrorDetail = null;

  if (error == null) return;

  final where = <String>[];
  if (detail != null) {
    final lib = detail.library;
    if (lib != null) where.add(lib);
    for (final line
        in detail.informationCollector?.call() ?? const <DiagnosticsNode>[]) {
      final text = line.toStringDeep().trim();
      if (text.contains('.dart:')) where.add(text);
    }
  }

  fail(
    '${because ?? 'the frame must render cleanly'}: $error'
    '${where.isEmpty ? '' : '\n  \u2192 ${where.take(3).join(' | ')}'}',
  );
}

/// The most recent framework error, captured with full diagnostics.
FlutterErrorDetails? _lastErrorDetail;

/// Installs the capture hook. Call once per test, before pumping.
void captureFrameworkErrors(WidgetTester tester) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _lastErrorDetail = details;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Every visible [Text] must be laid out inside the viewport.
///
/// A widget pushed under the tab bar or past the right edge still "renders" — it
/// just cannot be read.
///
/// WHY the vertical bounds are new: the old version only checked left/right, so
/// text laid out below the bottom edge (a mis-measured footer, a Column taller
/// than the screen, anything pushed off by overflow) or above the top edge was
/// invisible to the matrix yet equally unreadable. Content inside *any*
/// [Scrollable] stays exempt from the vertical check: below the fold is a
/// legitimate position for scrollable content — the user can reach it. The
/// horizontal-scroll and FittedBox exemptions are unchanged and still skip the
/// whole element.
void expectInsideViewport(
  WidgetTester tester,
  MatrixPoint point, {
  double slop = 1.0,
}) {
  final screen = Rect.fromLTWH(0, 0, point.width, point.height);
  final problems = <String>[];

  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    if (widget.data == null || widget.data!.trim().isEmpty) continue;

    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    if (!box.attached) continue;

    // A horizontal scroll view is *supposed* to hold content past the right edge:
    // a chip strip off-screen to the right is reachable by swiping. Only content
    // that cannot be scrolled to is a bug.
    if (_insideHorizontalScroll(element)) continue;
    if (_isScaledToFit(element)) continue;

    final rect = _globalRect(box);
    if (rect == null) continue;

    // Text clipped by its own scroll view is fine; text laid out beyond the
    // screen is not. Compare against the screen, with a small tolerance for
    // sub-pixel rounding.
    if (rect.right > screen.right + slop) {
      problems.add(
        '"${_preview(widget.data!)}" is '
        '${(rect.right - screen.right).toStringAsFixed(1)}px past the right edge',
      );
    }
    if (rect.left < screen.left - slop) {
      problems.add('"${_preview(widget.data!)}" starts off-screen');
    }

    // Vertical bounds, for text no scroll view can reveal. Scrollable content
    // below the fold is reachable and legitimate; a fixed widget laid out past
    // the bottom (or above the top) edge is simply never seen.
    if (!_insideAnyScrollable(element)) {
      if (rect.bottom > screen.bottom + slop) {
        problems.add(
          '"${_preview(widget.data!)}" is '
          '${(rect.bottom - screen.bottom).toStringAsFixed(1)}px below the '
          'bottom edge',
        );
      }
      if (rect.top < screen.top - slop) {
        problems.add(
          '"${_preview(widget.data!)}" starts '
          '${(screen.top - rect.top).toStringAsFixed(1)}px above the top edge',
        );
      }
    }
  }

  if (problems.isNotEmpty) {
    fail('Text outside the viewport at $point:\n  ${problems.join('\n  ')}');
  }
}

/// True when [element] is scaled to fit (FittedBox / Transform.scale).
///
/// A `FittedBox` lays its child out at intrinsic size and shrinks it during paint,
/// so the child's *layout* rect is not its visual rect. Measuring it would report a
/// phantom overflow on a roll number that is correctly scaled down.
bool _isScaledToFit(Element element) {
  var found = false;
  element.visitAncestorElements((a) {
    if (a.widget is FittedBox) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// True when [element] sits inside a scrollable that moves horizontally.
bool _insideHorizontalScroll(Element element) {
  var found = false;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Scrollable && w.axisDirection == AxisDirection.right) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// True when [element] sits inside any [Scrollable], either axis.
///
/// Used by the vertical viewport bound: content a scroll view can reveal is
/// allowed to live below the fold, so only unscrollable text is measured
/// against the bottom/top edges.
bool _insideAnyScrollable(Element element) {
  var found = false;
  element.visitAncestorElements((a) {
    if (a.widget is Scrollable) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// True when [element] sits inside a scrollable that moves vertically.
///
/// Mirrors [_insideHorizontalScroll]; used by the tap-coverage exemption for
/// content that scrolls through under the floating chrome.
bool _insideVerticalScroll(Element element) {
  var found = false;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Scrollable &&
        (w.axisDirection == AxisDirection.down ||
            w.axisDirection == AxisDirection.up)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Rect? _globalRect(RenderBox box) {
  if (!box.hasSize) return null;
  try {
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  } catch (_) {
    return null;
  }
}

String _preview(String s) => s.length > 40 ? '${s.substring(0, 40)}…' : s;

/// Text was truncated with no visual indication.
///
/// `didExceedMaxLines` plus `TextOverflow.clip` means the glyphs were simply cut
/// off mid-word — the reader cannot tell there was more.
void expectNoClippedText(WidgetTester tester, MatrixPoint point) {
  final problems = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    if (!render.hasSize) continue;

    final overflow = render.overflow;
    if (overflow != TextOverflow.clip) continue;
    if (!render.didExceedMaxLines) continue;

    // Ignore off-stage/zero-height text (IndexedStack tabs that are not showing).
    final rect = _globalRect(render);
    if (rect == null || rect.width <= 0 || rect.height <= 0) continue;

    problems.add('"${_preview(render.text.toPlainText())}"');
  }

  if (problems.isNotEmpty) {
    fail(
      'Text cut mid-word with TextOverflow.clip at $point '
      '(use ellipsis, or give it room):\n  ${problems.join('\n  ')}',
    );
  }
}

/// Every interactive element must be at least 44x44 and actually hit-testable.
///
/// The hit test is the assertion that matters: a widget can be 48x48 and still be
/// buried under the floating action dock or the tab bar, in which case the tap
/// lands on the wrong thing. That is exactly how a checklist row fired
/// "Check my result" instead of ticking its box.
int _checked = 0;

/// The widget types the harness treats as user-tappable surfaces.
List<Finder> _interactiveFinders() => <Finder>[
  find.byType(InkWell),
  find.byType(GestureDetector),
  find.byType(IconButton),
  find.byType(Switch),
  find.byType(TextField),
  find.byType(Checkbox),
];

void expectTapTargets(WidgetTester tester, MatrixPoint point) {
  final problems = <String>[];
  _checked = 0;
  final interactive = _interactiveFinders();

  for (final finder in interactive) {
    for (final element in finder.evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = _globalRect(box);
      if (rect == null) continue;

      // Zero-area render objects (a GestureDetector that only wraps nothing) are
      // not tappable surfaces; skip them rather than reporting noise.
      if (rect.width < 1 || rect.height < 1) continue;

      // Only elements the user can actually see.
      final screen = Rect.fromLTWH(0, 0, point.width, point.height);
      if (!rect.overlaps(screen)) continue;
      _checked++;

      if (rect.height < 43.0) {
        problems.add(
          '${_describeElement(element)} is only '
          '${rect.height.toStringAsFixed(1)}px tall',
        );
      }

      // A tap at the centre must reach this widget, not something painted on top.
      //
      // Exempt: content inside a *vertical* scroll view. The app's floating
      // chrome (the tab bar under `extendBody: true`, the pass dock) is
      // designed for content to scroll through underneath it, so at any scroll
      // offset some row sits below the bar — flagging those would bury the
      // real findings in by-design cases, and the user can always scroll the
      // row clear. What this check must catch are controls that can never be
      // reached: fixed chrome, and content in non-vertically-scrollable
      // surfaces — the shipped "checklist row fired Check my result" bug lived
      // in the pass PageView (horizontal), which is still checked. A primary
      // CTA *at rest* under the bar on a short screen is a genuine product
      // finding, but it is a layout fix, not something this mechanical check
      // can distinguish from a harmless scrolled-under row.
      if (rect.width >= 8 &&
          rect.height >= 8 &&
          !_insideVerticalScroll(element)) {
        final centre = rect.center;
        if (!screen.contains(centre)) continue;
        final result = HitTestResult();
        tester.binding.hitTestInView(result, centre, tester.view.viewId);
        final target = box;
        // WHY this predicate was flipped: it used to read `_isAncestorOf(t,
        // target)` — walking UP FROM THE TARGET looking for the hit entry. Every
        // ancestor the target shares with whatever was really hit (the Stack,
        // the Scrollable's listener, the Scaffold body — present in *every* hit
        // path) satisfied it, so "covered" could never fire and the check was
        // logically vacuous. Flutter's own equivalent — flutter_test
        // finders.dart `isRenderObjectAncestorOfTarget` — walks UP FROM THE HIT
        // TARGET looking for the finder's render object: the tap reached this
        // widget exactly when some hit entry *is* it or lives inside it.
        final reached = result.path.any((entry) {
          final t = entry.target;
          return t == target || (t is RenderObject && _isAncestorOf(target, t));
        });
        if (!reached) {
          problems.add(
            '${_describeElement(element)} at '
            '${centre.dx.toStringAsFixed(0)},${centre.dy.toStringAsFixed(0)} is '
            'covered — taps land on the wrong widget',
          );
        }
      }
    }
  }

  // The assertion must exist: an earlier revision collected findings and then
  // never asserted on them, so the check silently passed everything.
  if (problems.isNotEmpty) {
    fail(
      'Untappable or undersized controls at $point '
      '($_checked checked):\n  ${problems.join('\n  ')}',
    );
  }
}

/// Names an element well enough to find it: its type, the text it contains, and
/// its nearest named ancestor.
String _describeElement(Element element) {
  final parts = <String>[element.widget.runtimeType.toString()];

  String? label;
  void visit(Element e) {
    if (label != null) return;
    final w = e.widget;
    if (w is Text && w.data != null && w.data!.trim().isNotEmpty) {
      label = w.data!.trim();
    } else if (w is Icon) {
      label ??= 'icon:${w.icon?.codePoint ?? '?'}';
    }
    e.visitChildren(visit);
  }

  element.visitChildren(visit);
  if (label != null) parts.add('"${_preview(label!)}"');

  // Walk up a few frames so the report points at a recognisable widget.
  final ancestors = <String>[];
  element.visitAncestorElements((a) {
    final name = a.widget.runtimeType.toString();
    if (!name.startsWith('_') || ancestors.isEmpty) ancestors.add(name);
    return ancestors.length < 4;
  });
  parts.add('in ${ancestors.join(' < ')}');
  return parts.join(' ');
}

/// True when [candidate] is on [node]'s ancestor chain — walks UP FROM [node].
///
/// Direction matters: `expectTapTargets` asks "is the widget an ancestor of the
/// hit target", never the reverse (see the comment at the call site).
bool _isAncestorOf(RenderObject candidate, RenderObject node) {
  RenderObject? current = node.parent;
  while (current != null) {
    if (identical(current, candidate)) return true;
    current = current.parent;
  }
  return false;
}

/// Unmounts the app so owned timers (the 60s feed poll) are cancelled before the
/// test ends. Without this the widget tree outlives the body and the test hangs
/// waiting on a `Timer.periodic` that nothing will ever stop.
Future<void> disposeMatrix(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Finds every RenderFlex whose children do not fit, and names the widget.
///
/// `takeException()` returns an overflow but strips the "relevant error-causing
/// widget" block, so the report says "overflowed by 75px" with no file. Measuring
/// the render tree directly recovers the ancestor chain and the text involved.
void expectNoFlexOverflow(WidgetTester tester, MatrixPoint point) {
  final problems = <String>[];

  // `find.byType(Flex)` matches only widgets whose runtimeType is *exactly* Flex,
  // so Row and Column — the actual offending widgets — were never inspected.
  final flexes = find.byWidgetPredicate((w) => w is Flex);
  for (final element in flexes.evaluate()) {
    final render = element.renderObject;
    if (render is! RenderFlex) continue;
    if (!render.hasSize || !render.attached) continue;

    final horizontal = render.direction == Axis.horizontal;
    final limit = horizontal ? render.size.width : render.size.height;
    if (limit <= 0) continue;
    final origin = render.localToGlobal(Offset.zero);

    RenderBox? child = render.firstChild;
    while (child != null) {
      if (child.hasSize && child.attached) {
        final at = child.localToGlobal(Offset.zero);
        // Position of the child's far edge, in the flex's own coordinate space.
        final far = horizontal
            ? (at.dx - origin.dx) + child.size.width
            : (at.dy - origin.dy) + child.size.height;
        if (far > limit + 0.5) {
          final childElement = _elementForRender(child, element);
          problems.add(
            '${_describeElement(childElement ?? element)} exceeds its '
            '${horizontal ? 'Row' : 'Column'} by '
            '${(far - limit).toStringAsFixed(1)}px '
            '(needs ${far.toStringAsFixed(1)}, box ${limit.toStringAsFixed(1)})',
          );
        }
      }
      child = render.childAfter(child);
    }
  }

  if (problems.isNotEmpty) {
    fail('Flex overflow at $point:\n  ${problems.join('\n  ')}');
  }
}

/// The Element that owns [target], searching below [root].
Element? _elementForRender(RenderObject target, Element root) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (identical(e.renderObject, target)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  visit(root);
  return found;
}

/// The cell must actually render content.
///
/// WHY this exists: every other assertion in the sweep iterates the widgets it
/// finds, so a cell that rendered (nearly) nothing produced an empty problem
/// list and passed. `Vault / loadingVault` was the proof: a spinner, one label
/// and zero interactive widgets — `expectTapTargets` reported "0 checked" and
/// called it sane. A blank or stuck frame is the worst possible layout bug and
/// the harness was structurally incapable of seeing it.
///
/// [minTexts] is deliberately low: honest states like an empty vault legitimately
/// carry only a handful of strings. [minInteractive] pins the stronger half of
/// the contract: a mounted screen with no tappable surface at all is a dead end
/// the user cannot leave.
void expectRenderedSomething(
  WidgetTester tester,
  MatrixPoint point, {
  int minTexts = 3,
  int minInteractive = 1,
}) {
  final screen = Rect.fromLTWH(0, 0, point.width, point.height);

  var texts = 0;
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    if (widget.data == null || widget.data!.trim().isEmpty) continue;
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) continue;
    final rect = _globalRect(box);
    if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
    if (!rect.overlaps(screen)) continue;
    texts++;
  }

  var interactive = 0;
  for (final finder in _interactiveFinders()) {
    for (final element in finder.evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final rect = _globalRect(box);
      if (rect == null || rect.width < 1 || rect.height < 1) continue;
      if (!rect.overlaps(screen)) continue;
      interactive++;
    }
  }

  final problems = <String>[
    if (texts < minTexts)
      'only $texts visible Text widgets (minimum $minTexts)',
    if (interactive < minInteractive)
      'only $interactive interactive widgets (minimum $minInteractive)',
  ];
  if (problems.isNotEmpty) {
    fail(
      'Rendered next to nothing at $point: ${problems.join('; ')}. '
      'An empty or stuck cell must not pass as sane.',
    );
  }
}

/// The full sweep for one mounted screen.
void expectScreenSane(WidgetTester tester, MatrixPoint point) {
  // Measure flex overflow *before* asserting on exceptions: `takeException()`
  // consumes the overflow and drops the widget location, so once it fires the
  // precise measurement below would have nothing to report.
  expectNoFlexOverflow(tester, point);
  expectClean(tester, because: 'rendering $point');
  // A cell that renders nothing trivially satisfies every geometry check below,
  // so the "there is something there" floor comes first.
  expectRenderedSomething(tester, point);
  expectInsideViewport(tester, point);
  expectNoClippedText(tester, point);
  expectTapTargets(tester, point);
}

/// An [AdmitCardsNotifier] whose load is dictated by the caller.
///
/// Used to render the loading and error states without involving storage at all.
class _InjectedCards extends AdmitCardsNotifier {
  _InjectedCards(this._load);

  final Future<List<AdmitCard>> Function() _load;

  @override
  Future<List<AdmitCard>> build() async {
    final cards = await _load();
    state = AsyncData(cards);
    return cards;
  }
}
