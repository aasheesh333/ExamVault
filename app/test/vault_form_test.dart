import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/models/live_feed_dto.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/features/vault/vault_form_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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

  /// A published feed row for "UPSC CSE 2027" — the name a card is renamed to
  /// when the test needs a fresh match rather than an unpublished name.
  Map<String, dynamic> upscFeedRow() => {
    'exam_id': 'upsc_cse_2027_feed',
    'category': 'upsc',
    'exam_name': 'UPSC CSE 2027 Final Result',
    'context': 'Direct PDF · 2.1 MB',
    'status': 'result_out',
    'published_at': DateTime.now().toUtc().toIso8601String(),
    // Explicit far-future expiry: the default TTL runs from published_at, so
    // omitting it would make this fixture flip on its own expiry date.
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(days: 365))
        .toIso8601String(),
    'official_pdf': 'https://upsc.gov.in/example.pdf',
    'index_available': true,
    'index_version': 'abc123abc123',
    'roll_count': 3,
  };

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

  /// Puts the feed in the on-device cache, which the provider reads
  /// synchronously on first paint. The network refresh is fire-and-forget, so it
  /// does not complete inside a widget test's fake async — seeding the cache is
  /// how a test gets a feed the form can actually see. The Hive write itself is
  /// real I/O, hence `runAsync`.
  Future<void> seedFeed(
    WidgetTester tester,
    List<Map<String, dynamic>> updates,
  ) async {
    await tester.runAsync(() async {
      await cacheBox.put(
        LiveFeedStore.key,
        jsonEncode({
          'generated_at': DateTime.now().toUtc().toIso8601String(),
          'revision': 1,
          'updates': updates,
        }),
      );
    });
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

  /// Captures the messages the form sends to the platform screen reader.
  List<String> captureAnnouncements() {
    final messages = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final event = message as Map<dynamic, dynamic>;
        if (event['type'] == 'announce') {
          final data = event['data'] as Map<dynamic, dynamic>;
          messages.add(data['message'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        null,
      ),
    );
    return messages;
  }

  String rollValue(WidgetTester tester) {
    final field = find.byType(TextFormField).at(4);
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

    test('keeps the stored id when the exam name is unchanged', () {
      expect(
        resolveExamId(
          examName: 'SSC CHSL 2026',
          previous: 'ssc_chsl_typo',
          previousName: 'SSC CHSL 2026',
        ),
        'ssc_chsl_typo',
      );
    });

    test('a case or whitespace fix is not a rename', () {
      expect(
        resolveExamId(
          examName: '  SSC CHSL 2026 ',
          previous: 'ssc_chsl_typo',
          previousName: 'ssc chsl 2026',
        ),
        'ssc_chsl_typo',
      );
    });

    test('a renamed card does not inherit the previous exam id', () {
      // The old fallback pinned the previous id even when the name had changed
      // completely, so the checker searched another exam's roll index.
      expect(
        resolveExamId(
          examName: 'UPSC CSE 2027',
          previous: 'ssc_chsl_2026',
          previousName: 'SSC CHSL 2026',
        ),
        'upsc_cse_2027',
      );
    });

    test('without the old name it cannot claim the id is unchanged', () {
      expect(
        resolveExamId(examName: 'SSC CHSL 2026', previous: 'ssc_chsl_typo'),
        'ssc_chsl_2026',
      );
    });

    test('falls back to a slug of the typed name', () {
      expect(resolveExamId(examName: '  SSC CHSL 2026 '), 'ssc_chsl_2026');
    });
  });

  group('field semantics', () {
    /// The semantics node a screen reader focuses for the field at [index].
    SemanticsData nodeFor(WidgetTester tester, int index) => tester
        .getSemantics(
          find.descendant(
            of: find.byType(TextFormField).at(index),
            matching: find.byType(EditableText),
          ),
        )
        .getSemanticsData();

    testWidgets('every field is named by its label, not its hint', (
      tester,
    ) async {
      // The handle is disposed in the body, not via addTearDown: the
      // framework's end-of-test check runs before tearDowns.
      final handle = tester.ensureSemantics();
      try {
        useTallViewport(tester);
        await tester.pumpWidget(harness(const _FormHost()));
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();

        // TalkBack used to read the *hint* — "Street, area, city" for the field
        // labelled "Centre address", "e.g. Gate 2" for "Gate" — so twelve
        // fields on the credential-entry form sounded identical.
        expect(nodeFor(tester, 0).label, 'Your name (optional)');
        expect(nodeFor(tester, 1).label, 'Exam name');
        expect(nodeFor(tester, 4).label, 'Roll number');
        expect(nodeFor(tester, 8).label, 'Centre address');
        expect(nodeFor(tester, 11).label, 'Gate');

        // The label has to merge *onto* the field, not replace it: a wrapper
        // that took the name but dropped the text-field role would leave the
        // label readable and the field unusable.
        final examName = nodeFor(tester, 1);
        expect(examName.flagsCollection.isTextField, isTrue);
        await tester.enterText(find.byType(TextFormField).at(1), 'SSC CHSL');
        await tester.pump();
        final typed = nodeFor(tester, 1);
        expect(typed.label, 'Exam name');
        expect(typed.value, 'SSC CHSL');
        expect(typed.flagsCollection.isTextField, isTrue);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the hint is still rendered under the label', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // Naming the field must not cost the example under it: Material's
      // `labelText` hides `hintText` whenever the label is inline, which would
      // have blanked every hint on this form.
      final hint = find.text('Street, area, city');
      expect(hint, findsOneWidget);
      final faded = tester
          .widgetList<AnimatedOpacity>(
            find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)),
          )
          .any((w) => w.opacity == 0);
      expect(faded, isFalse);
    });

    testWidgets('the password toggle has a name and a tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        useTallViewport(tester);
        await tester.pumpWidget(harness(const _FormHost()));
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();

        // It used to be a bare "Button" on the most sensitive field.
        final toggle = find.byTooltip('Show password');
        expect(toggle, findsOneWidget);
        final data = tester.getSemantics(toggle).getSemanticsData();
        expect(data.tooltip, 'Show password');
        expect(data.hasAction(SemanticsAction.tap), isTrue);

        await tester.tap(toggle);
        await tester.pump();
        expect(find.byTooltip('Hide password'), findsOneWidget);
      } finally {
        handle.dispose();
      }
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

      await tester.enterText(find.byType(TextFormField).at(4), 'a123/B-9');
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
        find.byType(TextFormField).at(4),
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

      await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      expect(find.text('Choose the exam date before saving.'), findsOneWidget);
      expect(store.raw['__index'], isNull);
    });

    testWidgets('a missing date scrolls the date field into view', (
      tester,
    ) async {
      // Phone-sized: the date is a hard save blocker but sits five rows above
      // Save, so "tap the field above" pointed at nothing.
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // Name and roll valid: the date is the only thing blocking the save.
      await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      final date = find.text('Not set — tap to choose');
      final before = tester.getRect(date).top;

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      expect(find.text('Choose the exam date before saving.'), findsOneWidget);
      // The field was not just named, it was scrolled up towards the top of the
      // sheet (as far as the content below it allows).
      expect(date.hitTestable(), findsOneWidget);
      expect(tester.getRect(date).top, lessThan(before));
      expect(tester.getRect(date).top, lessThan(300));
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

      await fill(tester, ['', 'SSC CHSL 2026', '', '', '2201098765']);
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

    testWidgets('waits for the vault to open instead of skipping the check', (
      tester,
    ) async {
      useTallViewport(tester);
      final gate = Completer<void>();
      store = _MemoryStore(indexGate: gate);
      // A card with exactly the exam + roll the form is about to save.
      await seed(card());

      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['', 'SSC CHSL 2026', '', '', '2201098765']);
      await pickToday(tester);

      await tester.tap(find.text('Save to vault'));
      await tester.pump();

      // The vault is still opening: `.value ?? const []` used to read that as
      // "no cards" and save the duplicate. The button now stays busy while the
      // check waits.
      expect(
        tester.widget<EvPrimaryButton>(find.byType(EvPrimaryButton)).busy,
        isTrue,
      );
      expect(store.raw['__index'], isNotNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('You already saved this card — same exam and roll number.'),
        findsOneWidget,
      );
      final index = jsonDecode(store.raw['__index']!) as List<dynamic>;
      expect(index, ['chsl']);
    });

    testWidgets('an unreadable vault refuses the save and says so', (
      tester,
    ) async {
      final announced = captureAnnouncements();
      useTallViewport(tester);
      // The Keystore read throws: the duplicate check cannot run at all.
      store = _MemoryStore(failIndex: true);

      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
      await pickToday(tester);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      // The refusal names the outcome (not saved) as well as the cause, and it
      // is spoken, not only painted.
      expect(find.textContaining('has not been saved yet'), findsOneWidget);
      expect(
        announced.any((m) => m.contains('has not been saved yet')),
        isTrue,
      );
      // Nothing was written: an unchecked save is not a save.
      expect(store.raw, isEmpty);
      expect(store.attemptedWriteIds, isEmpty);
    });

    testWidgets('an optional name survives save', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['Asha Verma', 'SSC CHSL 2026', '', '', '2201098765']);
      await pickToday(tester);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      final index = jsonDecode(store.raw['__index']!) as List<dynamic>;
      final saved =
          jsonDecode(store.raw[index.first as String]!) as Map<String, dynamic>;
      expect(saved['name'], 'Asha Verma');

      // And the edit form seeds from it (the controller initialiser is the
      // whole edit path for this field).
      final card = AdmitCardCodec.decode(store.raw[index.first as String]!)!;
      expect(card.candidateName, 'Asha Verma');
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

  group('save with an off-screen error', () {
    testWidgets('says why Save refused and scrolls to the offender', (
      tester,
    ) async {
      // A phone-sized viewport, not the tall one: the point is that the
      // invalid field (exam name, first in the sheet) is scrolled out of
      // view when the thumb reaches Save at the bottom.
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // Roll valid, exam name empty: validate() fails on the first field.
      await tester.enterText(find.byType(TextFormField).at(4), 'A1234567');
      await tester.pump();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save to vault').hitTestable(), findsOneWidget);
      // Precondition: the offender is off-screen — its error would paint
      // where nobody can see it, and Save used to be a silent no-op.
      expect(find.text('EXAM NAME').hitTestable(), findsNothing);

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      // A near-button notice explains the refusal…
      expect(find.text('Fix the highlighted field above'), findsOneWidget);
      // …and the sheet scrolled back so the offender and its error are
      // actually on screen.
      expect(find.text('EXAM NAME').hitTestable(), findsOneWidget);
      expect(find.text('Enter the exam name').hitTestable(), findsOneWidget);
      // Nothing was saved.
      expect(store.raw['__index'], isNull);
    });
  });

  group('save bounds', () {
    testWidgets('a hung write times out into the error path with Retry', (
      tester,
    ) async {
      final announced = captureAnnouncements();
      useTallViewport(tester);
      // Writes never complete: the Keystore hang that used to leave the sheet
      // saving forever.
      store = _MemoryStore(hangWrites: true);

      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
      await pickToday(tester);
      await tester.tap(find.text('Save to vault'));
      // The busy spinner animates forever, so pumpAndSettle would never settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<EvPrimaryButton>(find.byType(EvPrimaryButton)).busy,
        isTrue,
      );

      // A close attempt during the save must say what is happening instead of
      // hitting `if (_saving) return;` in silence. "Working", not "saving":
      // the same wait can be the duplicate check reading the vault.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Still working on your card…'), findsOneWidget);
      expect(find.text('Add admit card'), findsOneWidget);

      // Past the 15 s ceiling the write is abandoned: an error with Retry, not
      // a permanent spinner.
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Saving took too long'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester.widget<EvPrimaryButton>(find.byType(EvPrimaryButton)).busy,
        isFalse,
      );
      expect(
        announced.any((m) => m.startsWith('Saving took too long')),
        isTrue,
      );
      expect(store.raw['__index'], isNull);
    });

    testWidgets('a refused save is announced, not only painted', (
      tester,
    ) async {
      final announced = captureAnnouncements();
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      // A screen-reader user tapping Save used to hear nothing at all.
      expect(announced, contains('Choose the exam date before saving.'));
    });

    testWidgets('the refusal and the error rows are live regions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        useTallViewport(tester);
        store = _MemoryStore(hangWrites: true);
        await tester.pumpWidget(harness(const _FormHost()));
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();

        await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
        await tester.tap(find.text('Save to vault'));
        await tester.pumpAndSettle();
        final notice = find.text('Choose the exam date before saving.');
        expect(
          tester
              .getSemantics(notice)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );

        await pickToday(tester);
        await tester.tap(find.text('Save to vault'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 16));
        await tester.pump();
        final error = find.textContaining('Saving took too long');
        expect(
          tester
              .getSemantics(error)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a retry after a timeout saves one card, not two', (
      tester,
    ) async {
      useTallViewport(tester);
      store = _MemoryStore();
      // The first write takes 20 s: the form stops waiting at 15 s, but the
      // write still lands. This is the race a Retry has to survive — a slow
      // Keystore write that arrives after the user has tapped again.
      store.nextWriteDelay = const Duration(seconds: 20);

      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await fill(tester, ['', 'SSC CHSL 2026', '', '', 'A1234567']);
      await pickToday(tester);
      await tester.tap(find.text('Save to vault'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();

      expect(find.textContaining('Saving took too long'), findsOneWidget);
      // The write is still in flight: nothing in the vault yet.
      expect(store.raw.containsKey('__index'), isFalse);

      // Retry while the first write is still pending, then let it land.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      final cards = store.raw.keys.where((k) => k != '__index').toList();
      expect(cards, hasLength(1));
      // Retry reused the id the first attempt used, so its write overwrote that
      // card instead of minting a second one for the same exam + roll.
      expect(store.attemptedWriteIds, hasLength(2));
      expect(store.attemptedWriteIds.toSet(), {cards.single});
      expect(jsonDecode(store.raw['__index']!) as List<dynamic>, [
        cards.single,
      ]);
    });
  });

  group('the VERIFIED claim', () {
    testWidgets('editing the roll number drops a stale VERIFIED badge', (
      tester,
    ) async {
      useTallViewport(tester);
      final verified = card().copyWith(rollNumberVerified: true);
      await seed(verified);

      await tester.pumpWidget(harness(_FormHost(existing: verified)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // Fixing a roll typo: VERIFIED was a claim about the *old* roll being
      // found in a published index — the new one never matched anything.
      await tester.enterText(find.byType(TextFormField).at(4), 'A9999999');
      await tester.pump();

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      expect(find.text('Edit admit card'), findsNothing); // saved and closed
      final saved = AdmitCardCodec.decode(store.raw['chsl']!);
      expect(saved?.rollNumber, 'A9999999');
      expect(saved?.rollNumberVerified, isFalse);
    });

    testWidgets('an edit that keeps roll and exam keeps VERIFIED', (
      tester,
    ) async {
      useTallViewport(tester);
      final verified = card().copyWith(rollNumberVerified: true);
      await seed(verified);

      await tester.pumpWidget(harness(_FormHost(existing: verified)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // The gate field (last in the sheet) touches neither the roll nor the
      // resolved exam id, so the hard-earned badge must survive.
      await tester.enterText(find.byType(TextFormField).at(11), 'Gate 5');
      await tester.pump();

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      final saved = AdmitCardCodec.decode(store.raw['chsl']!);
      expect(saved?.gate, 'Gate 5');
      expect(saved?.rollNumberVerified, isTrue);
    });

    testWidgets(
      'renaming to an unpublished name drops the old id and VERIFIED',
      (tester) async {
        useTallViewport(tester);
        final verified = card().copyWith(rollNumberVerified: true);
        await seed(verified);

        await tester.pumpWidget(harness(_FormHost(existing: verified)));
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();

        // The form now says "no published result matches this name", so keeping
        // ssc_chsl_2026 would make the checker search the old exam's index.
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'UPSC CSE 2027',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save to vault'));
        await tester.pumpAndSettle();

        final saved = AdmitCardCodec.decode(store.raw['chsl']!);
        expect(saved?.examName, 'UPSC CSE 2027');
        expect(saved?.examId, 'upsc_cse_2027');
        expect(saved?.rollNumberVerified, isFalse);
      },
    );

    testWidgets(
      'renaming to a published name adopts the feed id, not VERIFIED',
      (tester) async {
        useTallViewport(tester);
        final verified = card().copyWith(rollNumberVerified: true);
        await seed(verified);

        await seedFeed(tester, [upscFeedRow()]);
        await tester.pumpWidget(harness(_FormHost(existing: verified)));
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(1),
          'UPSC CSE 2027',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save to vault'));
        await tester.pumpAndSettle();

        final saved = AdmitCardCodec.decode(store.raw['chsl']!);
        expect(saved?.examId, 'upsc_cse_2027_feed');
        // The old roll was verified against a different exam's list.
        expect(saved?.rollNumberVerified, isFalse);
      },
    );

    testWidgets('a hyphenated rename keeps the id but still drops VERIFIED', (
      tester,
    ) async {
      useTallViewport(tester);
      final verified = card().copyWith(rollNumberVerified: true);
      await seed(verified);

      await tester.pumpWidget(harness(_FormHost(existing: verified)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // "SSC CHSL 2026" and "SSC-CHSL 2026" both slug to ssc_chsl_2026, so the
      // resolved id is unchanged and the roll is untouched. Only the name
      // comparison can tell this is a different exam, and it must drop the
      // badge — the old roll was verified against the old exam's list.
      await tester.enterText(find.byType(TextFormField).at(1), 'SSC-CHSL 2026');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      final saved = AdmitCardCodec.decode(store.raw['chsl']!);
      expect(saved?.examName, 'SSC-CHSL 2026');
      expect(saved?.examId, 'ssc_chsl_2026');
      expect(saved?.rollNumberVerified, isFalse);
    });

    testWidgets('editing the centre code keeps the id and VERIFIED', (
      tester,
    ) async {
      useTallViewport(tester);
      final verified = card().copyWith(rollNumberVerified: true);
      await seed(verified);

      await tester.pumpWidget(harness(_FormHost(existing: verified)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // The centre code is not part of the exam identity or the roll claim.
      await tester.enterText(find.byType(TextFormField).at(7), 'DL-99-0001');
      await tester.pump();
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      final saved = AdmitCardCodec.decode(store.raw['chsl']!);
      expect(saved?.centerCode, 'DL-99-0001');
      expect(saved?.examId, 'ssc_chsl_2026');
      expect(saved?.rollNumberVerified, isTrue);
    });

    testWidgets('renaming back to the original name restores no VERIFIED', (
      tester,
    ) async {
      useTallViewport(tester);
      // The card was renamed to UPSC CSE 2027 earlier and its roll was verified
      // under that name. Typing the original name back is a new resolution, not
      // a restore of the pre-rename state.
      final verified = card(
        examId: 'upsc_cse_2027',
        examName: 'UPSC CSE 2027',
      ).copyWith(rollNumberVerified: true);
      await seed(verified);

      await tester.pumpWidget(harness(_FormHost(existing: verified)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), 'SSC CHSL 2026');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      final saved = AdmitCardCodec.decode(store.raw['chsl']!);
      expect(saved?.examId, 'ssc_chsl_2026');
      expect(saved?.rollNumberVerified, isFalse);
    });
  });

  group('category seeding on edit', () {
    List<String> selectedChips(WidgetTester tester) => tester
        .widgetList<EvChip>(find.byType(EvChip))
        .where((c) => c.selected)
        .map((c) => c.label)
        .toList();

    testWidgets('retyping the name never re-files an existing card', (
      tester,
    ) async {
      useTallViewport(tester);
      final existing = card(); // filed under SSC
      await seed(existing);

      await tester.pumpWidget(harness(_FormHost(existing: existing)));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      // Fixing a typo in the name with UPSC-sounding words must not override
      // what the card's category chip already deliberately said.
      await tester.enterText(find.byType(TextFormField).at(1), 'UPSC CSE 2026');
      await tester.pump();
      expect(selectedChips(tester), ['SSC']);

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();

      final saved = AdmitCardCodec.decode(store.raw['chsl']!);
      expect(saved?.category, ExamCategory.ssc);
    });

    testWidgets('a new card still infers the category from the typed name', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), 'UPSC CSE 2026');
      await tester.pump();
      expect(selectedChips(tester), ['UPSC']);
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
  _MemoryStore({
    this.indexGate,
    this.hangWrites = false,
    this.failIndex = false,
  });

  final Map<String, String> raw = {};

  /// Blocks every index read until it completes: simulates a Keystore read
  /// still in flight when the form opens.
  final Completer<void>? indexGate;

  /// Makes [readIndex] throw: a vault the form cannot read at all.
  final bool failIndex;

  /// Makes [writeRaw] never complete: simulates the hung Keystore write that
  /// used to leave the form saving forever. Mutable so a test can let a stalled
  /// write through on a later attempt.
  bool hangWrites;

  /// How long the *next* [writeRaw] takes before it lands. A write slower than
  /// the form's 15 s ceiling: the form gives up waiting but the card still
  /// reaches the store, which is what a Retry has to cope with.
  Duration? nextWriteDelay;

  /// Every id [writeRaw] was called with, in order — including calls that never
  /// completed, so a test can prove a Retry reused the first attempt's id.
  final List<String> attemptedWriteIds = [];

  @override
  Future<List<String>> readIndex() async {
    if (failIndex) throw StateError('keystore unavailable');
    final gate = indexGate;
    if (gate != null) await gate.future;
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
    attemptedWriteIds.add(id);
    final delay = nextWriteDelay;
    if (delay != null) {
      nextWriteDelay = null;
      await Future<void>.delayed(delay);
    }
    if (hangWrites) return Completer<void>().future;
    raw[id] = payload;
  }

  @override
  Future<void> deleteRaw(String id) async => raw.remove(id);

  @override
  Future<Map<String, String>> readAllRaw() async => Map.of(raw);

  @override
  Future<void> wipe() async => raw.clear();
}
