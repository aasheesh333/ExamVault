import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:examvault/app.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/result_checker/engine/hashed_index.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late InMemoryStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_result_day');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('c$stamp');
    settingsBox = await Hive.openBox<dynamic>('s$stamp');
    store = InMemoryStore();
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// The published object the app actually consumes: a v2 hashed index.
  Uint8List hashedIndex() {
    final doc = {
      'v': 2,
      'mode': 'sha256-8-salted',
      'salt': salt,
      'total': 3,
      'hashes': [
        HashedRollIndex.digest(realRoll, salt),
        HashedRollIndex.digest('0801766', salt),
        HashedRollIndex.digest('0801786', salt),
      ]..sort(),
    };
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(doc))));
  }

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

  Widget app({bool withSavedCard = false}) {
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(
          jsonEncode({
            'generated_at': DateTime.now().toUtc().toIso8601String(),
            'revision': 1,
            'updates': [feedRow()],
          }),
          200,
        );
      }
      if (req.url.path.contains('rolls')) {
        return http.Response.bytes(hashedIndex(), 200);
      }
      return http.Response('', 404);
    });

    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: store),
        ),
        cdnClientProvider.overrideWithValue(
          CdnClient(cache: cacheBox, client: mock, baseUrl: 'https://cdn.test'),
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

    await tester.enterText(find.byType(TextField).first, roll);
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
