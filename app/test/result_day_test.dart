import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:examvault/app.dart';
import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/result_checker/engine/hashed_index.dart';
import 'package:examvault/features/shell/root_shell.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/matrix.dart';

/// The result-day path, end to end inside the widget tree.
///
/// This exists because the feature can be *correct* and still produce nothing on
/// screen. It shipped once in exactly that state: the checker found the roll,
/// then `markVerified('')` — called with an empty id because a student checking
/// straight from the radar has no saved card — indexed `_cache[-1]` and threw a
/// RangeError. The exception aborted the handler before the celebration dialog
/// was built, so a genuinely selected student saw an unchanged screen.
///
/// Nothing else in the suite covers "the answer reaches the UI", because every
/// other test stops at the engine. Hence this one.
void main() {
  const salt = '00112233445566778899aabbccddeeff';
  const examId = 'upsc_ldce_2025';
  const realRoll = '0801786';

  /// A second roll that IS in the published index but is not the saved card's
  /// own — the "checking a sibling's number" case.
  const siblingRoll = '0801766';

  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late InMemoryStore store;

  /// Every path the default mock client was asked for, in order. Tests that
  /// bring their own [MockClient] count their own hits instead.
  List<String> requestedPaths = [];

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_result_day');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    // In-memory boxes, the same pattern support/matrix.dart uses: with
    // file-backed boxes the feed refresh stalls at `await cache.put(...)` —
    // real file I/O never completes on the widget-test fake clock — so the
    // checker resolved index versions against an empty feed and silently
    // requested unversioned URLs.
    cacheBox = await Hive.openBox<dynamic>('c$stamp', bytes: Uint8List(0));
    settingsBox = await Hive.openBox<dynamic>('s$stamp', bytes: Uint8List(0));
    store = InMemoryStore();
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// A v2 hashed index over exactly [rolls].
  Uint8List hashedIndexFor(List<String> rolls) {
    final doc = {
      'v': 2,
      'mode': 'sha256-8-salted',
      'salt': salt,
      'total': rolls.length,
      'hashes': [for (final r in rolls) HashedRollIndex.digest(r, salt)]
        ..sort(),
    };
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(doc))));
  }

  /// The published object the app actually consumes: a v2 hashed index.
  Uint8List hashedIndex() => hashedIndexFor([realRoll, siblingRoll]);

  Map<String, dynamic> feedRow() => {
    'exam_id': examId,
    'category': 'upsc',
    'exam_name': 'Final Result: Combined Section Officers',
    'context': 'Official PDF · upsc.gov.in',
    'status': 'result_out',
    'published_at': DateTime.now().toUtc().toIso8601String(),
    'official_pdf': 'https://www.upsc.gov.in/sites/default/files/example.pdf',
    'index_available': true,
    'index_version': 'abc123abc123',
    'roll_count': 3,
  };

  String feedJson() => jsonEncode({
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'revision': 1,
    'updates': [feedRow()],
  });

  /// The radar row the student would have tapped, as the feed would deliver it.
  LiveUpdate liveRow() => LiveUpdate(
    examId: examId,
    category: ExamCategory.upsc,
    examName: 'Final Result: Combined Section Officers',
    contextLine: 'Official PDF · upsc.gov.in',
    status: UpdateStatus.resultOut,
    publishedAt: DateTime.now(),
    officialPdf: 'https://www.upsc.gov.in/sites/default/files/example.pdf',
    indexVersion: 'abc123abc123',
    rollCount: 3,
  );

  /// A saved card whose exam matches [feedRow], so the checker can resolve the
  /// index version from the feed exactly like the real product does.
  AdmitCard savedCard({
    String id = 'card_own',
    String roll = realRoll,
    String examCode = 'LDCE',
    String examName = 'Combined Section Officers',
  }) => AdmitCard(
    id: id,
    examId: examId,
    category: ExamCategory.upsc,
    examName: examName,
    conductingBody: 'UPSC',
    examCode: examCode,
    rollNumber: roll,
    registrationId: 'R1',
    dobOrPortalPassword: '01/01/1990',
    centerCode: 'DL-01',
    centerAddress: 'New Delhi',
    gate: 'Gate 1',
    reportBy: '09:00 AM',
    examDate: DateTime.now().add(const Duration(days: 3)),
    shift: '10:00 AM',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    checklist: const {ChecklistItem.admitCardPdf},
  );

  Widget app({
    SecureVaultStore? vault,
    MockClient? mock,
    Uint8List? rollsBody,
  }) {
    requestedPaths = [];
    final client =
        mock ??
        MockClient((req) async {
          requestedPaths.add(req.url.path);
          if (req.url.path.contains('live_feed')) {
            return http.Response(feedJson(), 200);
          }
          if (req.url.path.contains('rolls')) {
            return http.Response.bytes(rollsBody ?? hashedIndex(), 200);
          }
          return http.Response('', 404);
        });

    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: vault ?? MatrixVaultStore()),
        ),
        cdnClientProvider.overrideWithValue(
          CdnClient(
            cache: cacheBox,
            client: client,
            baseUrl: 'https://cdn.test',
          ),
        ),
      ],
      child: const ExamVaultApp(),
    );
  }

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Boots the app on a phone viewport, opens the checker tab and returns the
  /// container so providers can be driven and inspected.
  Future<ProviderContainer> pumpChecker(
    WidgetTester tester, {
    List<AdmitCard> savedCards = const [],
    SecureVaultStore? vault,
    MockClient? mock,
    Uint8List? rollsBody,
  }) async {
    await pumpPhone(
      tester,
      app(
        vault: vault ?? MatrixVaultStore(cards: savedCards),
        mock: mock,
        rollsBody: rollsBody,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExamVaultApp)),
      listen: false,
    );
    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 600));
    // Let the real event loop deliver the mocked feed. Under the fake clock the
    // MockClient's streamed body never completes, so without this the feed is
    // still the empty boot snapshot when Check is tapped — and no real user
    // ever taps Check before the feed they read the row from has arrived.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  /// Taps the primary CTA and drains the mocked network + isolate work.
  ///
  /// The fetch is real I/O through the mocked client, so it needs the real
  /// event loop: under the fake clock a `StreamedResponse` never completes and
  /// every lookup would sit at "downloading" forever. [settleMs] must also
  /// cover CdnClient's jittered retry backoff (up to ~1.2s) for tests that
  /// exercise transport failures.
  Future<void> runLookup(WidgetTester tester, {int settleMs = 500}) async {
    await tester.tap(find.text('Check my result instantly'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration(milliseconds: settleMs));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  String rollText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('roll-field')))
      .controller!
      .text;

  /// Scrolls the checker's (vertical) list until [finder] is built and visible.
  /// The outer ListView is the *first* Scrollable in pre-order tree walk — the
  /// card picker's horizontal strip, when present, is its descendant.
  Future<void> reveal(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find.byType(Scrollable).first,
      );

  /// Strict tappability: the widget's own render object (or a descendant of it)
  /// must be in the hit-test path at its centre. Pins the two dialog CTAs,
  /// which `expectTapTargets` only covers as part of a whole-screen sweep.
  void expectTapReaches(WidgetTester tester, Finder finder, String what) {
    final target = tester.element(finder).renderObject!;
    final result = HitTestResult();
    tester.binding.hitTestInView(
      result,
      tester.getRect(finder).center,
      tester.view.viewId,
    );
    final reached = result.path.any((entry) {
      final t = entry.target;
      if (t == target) return true;
      if (t is! RenderObject) return false;
      RenderObject? cur = t.parent;
      while (cur != null) {
        if (identical(cur, target)) return true;
        cur = cur.parent;
      }
      return false;
    });
    expect(reached, isTrue, reason: '$what must receive a tap at its centre');
  }

  /// Opens the checker on the live row and searches [roll].
  ///
  /// The exam is selected through the same notifier the radar row uses, because
  /// the row itself sits below the fold on a phone-sized viewport and the point
  /// of this test is the lookup, not the scroll.
  Future<void> check(WidgetTester tester, String roll) async {
    await pumpPhone(tester, app());

    final container = ProviderScope.containerOf(
      tester.element(find.text('Command Center')),
    );
    container.read(resultExamIdProvider.notifier).select(liveRow());
    await tester.pump(const Duration(milliseconds: 200));

    // No saved card exists in this scenario — that is the whole point.
    expect(container.read(admitCardsProvider).value, isEmpty);

    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 600));

    // Target the roll field by key: the Home screen has a search TextField
    // too, and "the first TextField in the tree" is no longer this one.
    await tester.enterText(find.byKey(const ValueKey('roll-field')), roll);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Check my result instantly'));
    await tester.pump();

    // The fetch is real I/O through the mocked client, so it needs the real
    // event loop: under the fake clock a `StreamedResponse` never completes and
    // every lookup would sit at "downloading" forever.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('markVerified', () {
    // The direct contract behind the bug above. A student checking from the
    // radar has no saved card, so the screen calls `markVerified('')`. That has
    // to be a no-op — not a `RangeError` from `_cache[-1]`, and not an error
    // logged on every single result check.
    test('an unknown id is a no-op, not an error', () async {
      final repo = AdmitCardRepository(store: store);

      expect(await repo.markVerified(''), isNull);
      expect(await repo.markVerified('never-existed'), isNull);
      expect(repo.cached, isEmpty);
    });

    test('a known id flips the verified flag and persists it', () async {
      final repo = AdmitCardRepository(store: store);
      final card = AdmitCard(
        id: 'c1',
        examId: examId,
        category: ExamCategory.upsc,
        examName: 'Combined Section Officers',
        conductingBody: 'UPSC',
        examCode: 'LDCE',
        rollNumber: realRoll,
        registrationId: 'R1',
        dobOrPortalPassword: '01/01/1990',
        centerCode: 'DL-01',
        centerAddress: 'New Delhi',
        gate: 'Gate 1',
        reportBy: '09:00 AM',
        examDate: DateTime.now().add(const Duration(days: 3)),
        shift: '10:00 AM',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        checklist: const {ChecklistItem.admitCardPdf},
      );
      await repo.save(card);

      final updated = await repo.markVerified('c1');
      expect(updated!.rollNumberVerified, isTrue);
      expect(store.raw['c1'], contains('"verified":true'));
    });
  });

  testWidgets('a found roll shows the celebration with no saved card', (
    tester,
  ) async {
    await check(tester, realRoll);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a bookkeeping failure must never abort the result',
    );
    expect(
      find.text('YOUR ROLL IS IN THE LIST'),
      findsOneWidget,
      reason: 'the answer is the entire product — it must reach the screen',
    );
    expect(find.text(realRoll), findsWidgets, reason: 'echo the roll back');
    // The hashed-index guarantee must be visible, not just claimed in a doc.
    expect(find.textContaining('one-way hash'), findsWidgets);
  });

  testWidgets('"Share the news" lands on Share with the roll on the card', (
    tester,
  ) async {
    await check(tester, realRoll);

    await tester.tap(find.text('Share the news'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The old behaviour only closed the dialog: the loudest button on the screen
    // did nothing. It must reach the share sheet, and the sheet must carry the
    // verified roll even though this student has no saved admit card.
    expect(find.text('YOUR ROLL IS IN THE LIST'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.textContaining(realRoll), findsWidgets);
  });

  testWidgets('an absent roll explains itself instead of celebrating', (
    tester,
  ) async {
    await check(tester, '9999999');

    expect(find.text('Not in this list yet'), findsOneWidget);
    expect(find.text('YOUR ROLL IS IN THE LIST'), findsNothing);
    expect(find.textContaining('one-way hash'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the official document link is offered, not a copy of it', (
    tester,
  ) async {
    await pumpPhone(tester, app());

    final container = ProviderScope.containerOf(
      tester.element(find.text('Command Center')),
    );
    container.read(resultExamIdProvider.notifier).select(liveRow());
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Official PDF'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    // The wording is a product decision: we link, we do not host.
    expect(find.textContaining("commission's own site"), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // (a) The recent-checks badge follows the verdict AND the roll's identity.
  // -------------------------------------------------------------------------

  group('recent-checks badge', () {
    testWidgets('own roll found stamps FOUND on the card', (tester) async {
      final container = await pumpChecker(tester, savedCards: [savedCard()]);

      // Cold-start prefill owns the field: the saved card's roll is in it.
      expect(rollText(tester), realRoll);

      await runLookup(tester);
      expect(find.text('YOUR ROLL IS IN THE LIST'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      await reveal(tester, find.text('FOUND'));
      expect(find.text('FOUND'), findsOneWidget);
      expect(
        container.read(admitCardsProvider).value!.single.rollNumberVerified,
        isTrue,
        reason: "the card's own roll was found in its own exam's list",
      );
    });

    testWidgets(
      "a sibling roll being found does not stamp FOUND on this card",
      (tester) async {
        await pumpChecker(tester, savedCards: [savedCard()]);

        await tester.enterText(
          find.byKey(const ValueKey('roll-field')),
          siblingRoll,
        );
        await tester.pump(const Duration(milliseconds: 200));
        await runLookup(tester);

        // The searched roll IS in the list, so the celebration is correct…
        expect(find.text('YOUR ROLL IS IN THE LIST'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        // …but the card's badge describes the CARD's own roll, which was never
        // the subject of a found verdict. `verified` used to OR-in any found
        // result regardless of roll identity, printing FOUND here.
        await reveal(tester, find.text('NOT CHECKED'));
        expect(find.text('FOUND'), findsNothing);
        expect(find.text('NOT CHECKED'), findsOneWidget);
      },
    );

    testWidgets("the sibling card's own not-found verdict reads NOT FOUND", (
      tester,
    ) async {
      await pumpChecker(
        tester,
        savedCards: [
          savedCard(),
          savedCard(id: 'card_sib', roll: '9999999', examCode: 'SIB'),
        ],
      );

      // With two saved cards the picker must be reachable even though the exam
      // is already resolved (from the card's feed row). It used to be hidden
      // whenever any update was resolved, making the sibling card unselectable.
      final chip = find.text('SIB');
      await reveal(tester, chip);
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 400));
      expect(rollText(tester), '9999999');

      await runLookup(tester);

      expect(find.text('Not in this list yet'), findsOneWidget);
      // A finished search of THIS card's own roll is a check: the badge must
      // read NOT FOUND, never the untouched NOT CHECKED.
      await reveal(tester, find.text('NOT FOUND'));
      expect(find.text('NOT FOUND'), findsOneWidget);
      expect(find.text('NOT CHECKED'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // (b) The request path is the versioned, content-addressed one.
  // -------------------------------------------------------------------------

  group('versioned index path', () {
    testWidgets('a saved-card check requests the versioned path', (
      tester,
    ) async {
      await pumpChecker(tester, savedCards: [savedCard()]);

      // No radar row was tapped: the exam comes from the saved card, whose id
      // the feed row matches, so the version must be resolved from the feed —
      // never the unversioned path, which 404s for a published list.
      await runLookup(tester);

      final rolls = requestedPaths.where((p) => p.contains('rolls')).toList();
      expect(rolls, isNotEmpty);
      expect(
        rolls,
        everyElement('/v1/rolls/${examId}_abc123abc123_rolls.json.gz'),
      );
    });

    testWidgets('a tapped row never freezes the index version', (tester) async {
      final container = await pumpChecker(tester);

      // The row was tapped earlier in the session, *before* the commission
      // published a corrected list. The feed (polled every 60s) already knows
      // the new version; the tapped LiveUpdate is a frozen snapshot of the old
      // one. Old versioned URLs stay valid on the immutable edge, so trusting
      // the snapshot would silently search the pre-correction list forever —
      // a confident wrong verdict with no 404 to expose it.
      container
          .read(resultExamIdProvider.notifier)
          .select(
            LiveUpdate(
              examId: examId,
              category: ExamCategory.upsc,
              examName: 'Final Result: Combined Section Officers',
              contextLine: 'Official PDF · upsc.gov.in',
              status: UpdateStatus.resultOut,
              publishedAt: DateTime.now(),
              indexVersion: 'stale000000',
              rollCount: 3,
            ),
          );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(
        find.byKey(const ValueKey('roll-field')),
        realRoll,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await runLookup(tester);

      final rolls = requestedPaths.where((p) => p.contains('rolls')).toList();
      expect(rolls, isNotEmpty);
      expect(
        rolls,
        everyElement('/v1/rolls/${examId}_abc123abc123_rolls.json.gz'),
        reason:
            'the version must be resolved fresh from the feed at check time',
      );
      expect(requestedPaths.any((p) => p.contains('stale000000')), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // (c) The durable VERIFIED stamp: identity-gated, normalisation-tolerant.
  // -------------------------------------------------------------------------

  group('verification stamp', () {
    testWidgets("checking someone else's roll never stamps the card", (
      tester,
    ) async {
      final vault = MatrixVaultStore(cards: [savedCard()]);
      final container = await pumpChecker(tester, vault: vault);

      await tester.enterText(
        find.byKey(const ValueKey('roll-field')),
        siblingRoll,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await runLookup(tester);
      expect(find.text('YOUR ROLL IS IN THE LIST'), findsOneWidget);

      expect(
        container.read(admitCardsProvider).value!.single.rollNumberVerified,
        isFalse,
        reason: 'the found roll belongs to somebody else',
      );
      expect(
        await vault.readAllRaw(),
        isEmpty,
        reason:
            'nothing about a sibling verdict may be persisted onto this card',
      );
    });

    testWidgets('an own roll typed in lowercase still stamps the card', (
      tester,
    ) async {
      const alphaRoll = 'LDCE0801786';
      final container = await pumpChecker(
        tester,
        savedCards: [savedCard(roll: alphaRoll)],
        rollsBody: hashedIndexFor([alphaRoll]),
      );

      // The engine normalises (trim + upper-case) before searching, so the
      // verdict is FOUND — but the stamp gate used to compare the raw field
      // text case-sensitively, and a lowercase-typed own roll never stamped.
      await tester.enterText(
        find.byKey(const ValueKey('roll-field')),
        'ldce0801786',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await runLookup(tester);
      expect(find.text('YOUR ROLL IS IN THE LIST'), findsOneWidget);

      expect(
        container.read(admitCardsProvider).value!.single.rollNumberVerified,
        isTrue,
        reason:
            'the stamp gate must compare the same normalisation the engine searches with',
      );
    });
  });

  // -------------------------------------------------------------------------
  // (d) The unavailable branches, and the guards that keep them honest.
  // -------------------------------------------------------------------------

  group('unavailable branches', () {
    testWidgets('503 reads as transport, and Try again re-hits the network', (
      tester,
    ) async {
      var failing = true;
      var rollsHits = 0;
      final mock = MockClient((req) async {
        if (req.url.path.contains('live_feed')) {
          return http.Response(feedJson(), 200);
        }
        if (req.url.path.contains('rolls')) {
          rollsHits++;
          if (failing) return http.Response('', 503);
          return http.Response.bytes(hashedIndex(), 200);
        }
        return http.Response('', 404);
      });

      await pumpChecker(tester, savedCards: [savedCard()], mock: mock);
      // settleMs covers CdnClient's jittered retry backoff (3 attempts).
      await runLookup(tester, settleMs: 2400);

      await reveal(tester, find.text('Could not reach the result index'));
      expect(find.text('Could not reach the result index'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The one-line note must describe the same fault as the card: it used to
      // claim "No index to search yet." even for a pure transport failure.
      expect(find.text('Retry when you are back online.'), findsOneWidget);
      // The mirror panel OBSERVED the failed fetch; the feed's "published"
      // flag must not paint green READY next to a card that says unreachable.
      expect(find.text('MISSING'), findsOneWidget);
      expect(find.text('READY'), findsNothing);
      final hitsAfterFailure = rollsHits;
      expect(hitsAfterFailure, greaterThan(0));

      // The edge recovers. "Try again" must actually go back to the network —
      // a retry that re-served the memoised failure was the original bug.
      failing = false;
      await reveal(tester, find.text('Try again'));
      // ensureVisible aligns the button with the viewport's bottom edge, which
      // on this screen puts it *under* the floating tab bar; one more drag
      // lifts it into genuinely tappable space (the recent-checks card below
      // leaves the list room to scroll).
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        rollsHits,
        greaterThan(hitsAfterFailure),
        reason: 'Try again must issue a fresh request',
      );
      expect(find.text('YOUR ROLL IS IN THE LIST'), findsOneWidget);
    });

    testWidgets('a malformed 200 payload reads as "could not be read"', (
      tester,
    ) async {
      // Valid gzip, invalid JSON inside: the engine raises a FormatException,
      // which must surface as our fault — not a verdict, not "not published".
      final malformed = Uint8List.fromList(
        gzip.encode(utf8.encode('NOT JSON {{{')),
      );
      await pumpChecker(
        tester,
        savedCards: [savedCard()],
        rollsBody: malformed,
      );
      await runLookup(tester);

      await reveal(tester, find.textContaining('could not be read'));
      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.text('YOUR ROLL IS IN THE LIST'), findsNothing);
      expect(find.text('Not in this list yet'), findsNothing);
    });

    testWidgets(
      'a 404 says "not published yet" and offers no pointless retry',
      (tester) async {
        final mock = MockClient((req) async {
          if (req.url.path.contains('live_feed')) {
            return http.Response(feedJson(), 200);
          }
          return http.Response('', 404);
        });
        await pumpChecker(tester, savedCards: [savedCard()], mock: mock);
        await runLookup(tester, settleMs: 700);

        // The repository's 404 reason is 'The result for this exam has not been
        // published yet.' — a matcher on contains('not published') missed it
        // ('not *been* published'), so this honest branch was unreachable and
        // users got the generic card plus a retry that just 404'd again.
        await reveal(tester, find.text('Result not published yet'));
        expect(find.text('Result not published yet'), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
        expect(find.text('Could not check this exam'), findsNothing);
        expect(
          find.text('We never show a result we cannot verify.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('an implausible roll is rejected locally, with zero network', (
      tester,
    ) async {
      var rollsHits = 0;
      final mock = MockClient((req) async {
        if (req.url.path.contains('live_feed')) {
          return http.Response(feedJson(), 200);
        }
        if (req.url.path.contains('rolls')) {
          rollsHits++;
          return http.Response.bytes(hashedIndex(), 200);
        }
        return http.Response('', 404);
      });
      await pumpChecker(tester, savedCards: [savedCard()], mock: mock);

      final field = find.byKey(const ValueKey('roll-field'));
      // The field itself caps input, so a 40-char paste can never even reach
      // the controller through the keyboard.
      expect(tester.widget<TextField>(field).maxLength, 24);

      // Set the controller directly: the shape a formatter bypass would have
      // (and the belt to the maxLength's braces). The engine always rejected
      // >24 chars — but only AFTER the 12 MB download and gunzip it was meant
      // to prevent. The pre-flight check must reject with no network at all.
      tester.widget<TextField>(field).controller!.text = 'A' * 30;
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Check my result instantly'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Check the roll number'), findsOneWidget);
      expect(
        rollsHits,
        0,
        reason: 'an implausible roll must never trigger an index download',
      );
    });
  });

  // -------------------------------------------------------------------------
  // (e) The celebration dialog's geometry at the hostile matrix points.
  // -------------------------------------------------------------------------

  /// Boots the real shell at [point] and drives the found-verdict flow until
  /// the celebration dialog is open.
  Future<void> pumpDialogAt(WidgetTester tester, MatrixPoint point) async {
    await loadMatrixFonts();
    tester.view.physicalSize = Size(point.width, point.height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(feedJson(), 200);
      }
      if (req.url.path.contains('rolls')) {
        return http.Response.bytes(hashedIndex(), 200);
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
            (ref) => AdmitCardRepository(
              store: MatrixVaultStore(cards: [savedCard()]),
            ),
          ),
          cdnClientProvider.overrideWithValue(
            CdnClient(
              cache: cacheBox,
              client: mock,
              baseUrl: 'https://cdn.test',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: point.dark ? ThemeMode.dark : ThemeMode.light,
          home: const RootShell(),
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

    // Unmount on teardown: cancels the 60s feed poll even when an assertion
    // aborts the body (same pattern as pumpMatrix).
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    });

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 600));
    // Deliver the mocked feed on the real event loop, so the version is
    // resolved from the feed exactly like a real session (see pumpChecker).
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The cold-start prefill filled the card's own roll.
    expect(rollText(tester), realRoll);

    // Trigger the check through the keyboard's search action rather than a tap
    // on the CTA: at 2.0x on 320px the scrolled-to CTA can sit *under* the
    // floating tab bar — geometrically "visible" to ensureVisible, but the tap
    // lands on the bar. The field's onSubmitted path is the same `_check`.
    final field = find.byKey(const ValueKey('roll-field'));
    await tester.showKeyboard(field);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('YOUR ROLL IS IN THE LIST'),
      findsOneWidget,
      reason: 'the dialog must be open before its geometry is measured',
    );
  }

  for (final point in matrixPoints.where(
    (mp) => const ['scaled200small', 'small', 'light'].contains(mp.name),
  )) {
    testWidgets('the celebration dialog survives $point', (tester) async {
      await pumpDialogAt(tester, point);

      expectNoFlexOverflow(tester, point);
      expectClean(tester, because: 'celebration dialog at $point');
      expectInsideViewport(tester, point);
      // At 2.0x on a 320px screen the dialog's content is taller than its own
      // viewport and scrolls, so the CTAs start below the fold. Bring each
      // into view before pinning tappability — exactly as a user would. The
      // checker's ListView is the *first* Scrollable in tree order; the
      // dialog's own is the SingleChildScrollView, so target that one.
      final dialogScroll = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Share the news'),
        80,
        scrollable: dialogScroll,
      );
      // The two CTAs must actually receive taps — the whole point of the
      // dialog is the share hand-off.
      expectTapReaches(tester, find.text('Share the news'), 'Share the news');
      await tester.scrollUntilVisible(
        find.text('Close'),
        80,
        scrollable: dialogScroll,
      );
      expectTapReaches(tester, find.text('Close'), 'Close');

      // The tappability sweep treats everything under a modal barrier as
      // "covered", which is correct modal behaviour, not a layout bug — so it
      // runs on the same screen state with the dialog dismissed (the verdict
      // card and badge remain), where every control must be reachable.
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('YOUR ROLL IS IN THE LIST'), findsNothing);
      expectTapTargets(tester, point);
    });
  }
}

/// In-memory stand-in for the Keystore-backed store, which needs a platform
/// channel that does not exist under `flutter test`.
class InMemoryStore implements SecureVaultStore {
  final Map<String, String> raw = {};

  @override
  Future<List<String>> readIndex() async {
    final value = raw['__index'];
    if (value == null) return const [];
    return (jsonDecode(value) as List).cast<String>();
  }

  @override
  Future<void> writeIndex(List<String> ids) async {
    raw['__index'] = jsonEncode(ids);
  }

  @override
  Future<String?> readRaw(String id) async => raw[id];

  @override
  Future<void> writeRaw(String id, String payload) async {
    raw[id] = payload;
  }

  @override
  Future<void> deleteRaw(String id) async {
    raw.remove(id);
  }

  @override
  Future<Map<String, String>> readAllRaw() async => Map.of(raw);

  @override
  Future<void> wipe() async => raw.clear();
}
