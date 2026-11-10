import 'dart:convert';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/vault/vault_form_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Regressions for the add/edit form: alphanumeric roll numbers, the required
/// exam date, duplicate cards, and re-resolving a renamed card's exam id.
void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late _MemoryStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_vault_form');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('cache_$stamp');
    settingsBox = await Hive.openBox<dynamic>('settings_$stamp');
    store = _MemoryStore();
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  AdmitCard card({
    String id = 'chsl',
    String examId = 'ssc_chsl_2026',
    String examName = 'SSC CHSL 2026',
    String rollNumber = '2201098765',
    DateTime? examDate,
  }) {
    final now = DateTime.now();
    return AdmitCard(
      id: id,
      examId: examId,
      category: ExamCategory.ssc,
      examName: examName,
      conductingBody: 'Staff Selection Commission',
      examCode: 'CHSL',
      rollNumber: rollNumber,
      registrationId: 'SSC-CHSL-26-441122',
      dobOrPortalPassword: '11/05/1998',
      centerCode: 'DL-07-2210',
      centerAddress: 'Sector 9, Rohini, New Delhi',
      gate: 'Gate 2',
      reportBy: '08:00 AM',
      examDate: examDate ?? now.add(const Duration(days: 9)),
      shift: '10:00 AM – 11:00 AM',
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget harness(Widget home, {TextScaler textScaler = TextScaler.noScaling}) {
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        return http.Response(
          jsonEncode({
            'generated_at': DateTime.now().toUtc().toIso8601String(),
            'revision': 1,
            'updates': <dynamic>[],
          }),
          200,
        );
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
      child: MaterialApp(
        theme: AppTheme.light(),
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
    );
  }

  Future<void> seed(AdmitCard value) async {
    await store.writeRaw(value.id, AdmitCardCodec.encode(value));
    await store.writeIndex([value.id]);
  }

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// The form's fields in build order; the roll number is fourth.
  Future<void> fill(WidgetTester tester, List<String> values) async {
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), values[i]);
    }
    await tester.pump();
  }

  Future<void> pickToday(WidgetTester tester) async {
    await tester.tap(find.text('Not set — tap to choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  String rollValue(WidgetTester tester) {
    final field = find.byType(TextFormField).at(3);
    return tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .controller
        .text;
  }

  group('exam id resolution', () {
    LiveUpdate update() => LiveUpdate(
      examId: 'ssc_whats_new_result_1',
      category: ExamCategory.ssc,
      examName: 'SSC CHSL 2026 Result',
      contextLine: 'Direct PDF · 4.2 MB',
      status: UpdateStatus.resultOut,
      publishedAt: DateTime(2026, 7, 1),
    );

    test('a fresh match wins, so a renamed card re-resolves', () {
      expect(
        resolveExamId(
          examName: 'SSC CHSL 2026',
          match: update(),
          previous: 'ssc_chsl_typo',
        ),
        'ssc_whats_new_result_1',
      );
    });

    test('keeps the stored id when nothing is published', () {
      expect(
        resolveExamId(examName: 'SSC CHSL 2026', previous: 'ssc_chsl_typo'),
        'ssc_chsl_typo',
      );
    });

    test('falls back to a slug of the typed name', () {
      expect(resolveExamId(examName: '  SSC CHSL 2026 '), 'ssc_chsl_2026');
    });
  });

  group('roll number', () {
    testWidgets('accepts an alphanumeric roll and upper-cases it', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(3), 'a123/B-9');
      await tester.pump();

      // A digits-only filter used to keep "1239" and drop the letters, which
      // saved a different, unmatchable roll number.
      expect(rollValue(tester), 'A123/B-9');
    });

    testWidgets('strips pasted spaces and keeps up to 24 characters', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(3),
        'A123 4567 8901 2345 6789 0123',
      );
      await tester.pump();

      expect(rollValue(tester), 'A12345678901234567890123');
      expect(rollValue(tester).length, 24);
    });
  });

  group('exam date', () {
    testWidgets('starts unset and blocks Save until a date is chosen', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      expect(find.text('Not set — tap to choose'), findsOneWidget);

      await fill(tester, ['SSC CHSL 2026', '', '', 'A1234567']);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose the exam date — tap the field above.'),
        findsOneWidget,
      );
      expect(store.raw['__index'], isNull);
    });

    testWidgets('the picker opens for a card saved more than a year ago', (
      tester,
    ) async {
      useTallViewport(tester);
      final old = card(
        id: 'old',
        examDate: DateTime.now().subtract(const Duration(days: 800)),
      );
      await seed(old);

      await tester.pumpWidget(harness(_FormHost(existing: old)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await tester.pumpAndSettle();

      // firstDate used to be now-365d while initialDate came from the card, so
      // this asserted inside showDatePicker.
      expect(tester.takeException(), isNull);
      expect(find.text('OK'), findsOneWidget);
    });
  });

  group('duplicates', () {
    testWidgets('blocks the same exam and roll twice', (tester) async {
      useTallViewport(tester);
      await seed(card());
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['SSC CHSL 2026', '', '', '2201098765']);
      await pickToday(tester);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      expect(
        find.text('You already saved this card — same exam and roll number.'),
        findsOneWidget,
      );
      final index = jsonDecode(store.raw['__index']!) as List<dynamic>;
      expect(index, ['chsl']);
    });

    testWidgets('editing a card is not a duplicate of itself', (tester) async {
      useTallViewport(tester);
      final existing = card();
      await seed(existing);

      await tester.pumpWidget(harness(_FormHost(existing: existing)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already saved this card'), findsNothing);
      expect(find.text('Edit admit card'), findsNothing);
    });
  });

  group('layout', () {
    testWidgets('form lays out at 320px with a 2.0 text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(const _FormHost(), textScaler: const TextScaler.linear(2.0)),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scroll body clears the keyboard', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      // The keyboard used to cover the save button with no way to scroll clear.
      expect((scroll.padding! as EdgeInsets).bottom, 28 + 320);
    });
  });
}

class _FormHost extends ConsumerWidget {
  const _FormHost({this.existing});

  final AdmitCard? existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure the vault (and so the duplicate check) is loaded before the form
    // can be submitted, as it is in the real app.
    ref.watch(admitCardsProvider);
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showVaultFormSheet(context, ref, existing: existing),
          child: const Text('Open form'),
        ),
      ),
    );
  }
}

/// In-memory stand-in for the Keystore-backed store.
class _MemoryStore implements SecureVaultStore {
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
  Future<void> writeRaw(String id, String payload) async => raw[id] = payload;

  @override
  Future<void> deleteRaw(String id) async => raw.remove(id);

  @override
  Future<Map<String, String>> readAllRaw() async => Map.of(raw);

  @override
  Future<void> wipe() async => raw.clear();
}
