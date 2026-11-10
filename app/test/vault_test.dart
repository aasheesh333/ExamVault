import 'dart:convert';
import 'dart:io';

import 'package:examvault/core/theme/app_theme.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/features/command_center/widgets/wallet_card_stack.dart';
import 'package:examvault/features/command_center/widgets/wallet_pass_card.dart';
import 'package:examvault/features/vault/admit_card_detail_screen.dart';
import 'package:examvault/features/vault/vault_form_sheet.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Vault regressions: the pass must not overflow at large text, the form must
/// validate its roll field, and closing a dirty form must never discard it.
void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late InMemoryVaultStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_vault');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('cache_$stamp');
    settingsBox = await Hive.openBox<dynamic>('settings_$stamp');
    store = InMemoryVaultStore();
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  AdmitCard card({
    String id = 'chsl',
    String rollNumber = '2201098765',
    String centerAddress = 'Sector 9, Rohini, New Delhi',
    String gate = 'Gate 2',
    int daysFromNow = 9,
  }) => AdmitCard(
    id: id,
    examId: 'ssc_chsl_tier1_2026',
    category: ExamCategory.ssc,
    examName: 'SSC CHSL Tier-1 2026',
    conductingBody: 'Staff Selection Commission',
    examCode: 'CHSL · TIER-1',
    rollNumber: rollNumber,
    registrationId: 'SSC-CHSL-26-441122',
    dobOrPortalPassword: '11/05/1998',
    centerCode: 'DL-07-2210',
    centerAddress: centerAddress,
    gate: gate,
    reportBy: '08:00 AM',
    examDate: DateTime.now().add(Duration(days: daysFromNow)),
    shift: '10:00 AM – 11:00 AM',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

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
    // Append, don't replace: seeding three cards used to leave only the last one,
    // so the multi-card tests were silently exercising a single-card vault.
    final ids = await store.readIndex();
    if (!ids.contains(value.id)) {
      await store.writeIndex([...ids, value.id]);
    }
  }

  /// The form is taller than a phone; a tall viewport keeps every field built so
  /// validation errors and the save button are reachable without lazy-list churn.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('wallet pass', () {
    testWidgets('draws on-navy status colours in light mode', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: WalletPassCard(card: card(), onOpen: () {}),
              ),
            ),
          ),
          textScaler: const TextScaler.linear(1.35),
        ),
      );
      await tester.pumpAndSettle();

      // Light-mode tokens (#047857 etc.) vanish on navy; the pass must use its
      // own fixed on-navy colour instead.
      final saved = tester.widget<Text>(find.text('SAVED OFFLINE'));
      expect(saved.style?.color, const Color(0xFF6EE7B7));
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out at 320px with a 1.35 text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: WalletPassCard(card: card(), onOpen: () {}),
              ),
            ),
          ),
          textScaler: const TextScaler.linear(1.35),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2201098765'), findsOneWidget);
      // A fixed 176px height overflowed once the type scale was raised.
      expect(tester.takeException(), isNull);
    });

    testWidgets('home wallet stack does not overflow at a 1.35 text scale', (
      tester,
    ) async {
      // The deck now measures the front card, so its height follows the scale.
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: WalletCardStack(cards: [card()], onOpen: (_) {}),
            ),
          ),
          textScaler: const TextScaler.linear(1.35),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('wallet stack measures itself at 320px and a 2.0 text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final count in [2, 3]) {
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: WalletCardStack(
                        cards: List<AdmitCard>.generate(count, (_) => card()),
                        onOpen: (_) {},
                      ),
                    ),
                    const Text('NEXT SECTION'),
                  ],
                ),
              ),
            ),
            textScaler: const TextScaler.linear(2.0),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '$count cards');

        // The old hard-coded 180 + 44 * layers deck painted over the header of
        // the next section; the deck must now be as tall as the grown card.
        final stack = tester.getSize(find.byType(WalletCardStack));
        expect(stack.height, greaterThan(180 + 44.0 * (count - 1)));

        final front = tester.getRect(find.byType(WalletPassCard).last);
        final next = tester.getRect(find.text('NEXT SECTION'));
        expect(
          front.bottom,
          lessThanOrEqualTo(next.top),
          reason: '$count cards must not paint over the next section',
        );
      }
    });

    testWidgets('pass lays out at 320px with a 2.0 text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: WalletPassCard(card: card(), onOpen: () {}),
              ),
            ),
          ),
          textScaler: const TextScaler.linear(2.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('2201098765'), findsOneWidget);
    });

    testWidgets('compact header keeps a gap before the countdown', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Inline at a normal scale, stacked at 2.0x — both must leave a gap.
      for (final scale in [1.35, 2.0]) {
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: WalletPassCard(
                    card: card(),
                    compact: true,
                    onOpen: () {},
                  ),
                ),
              ),
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'scale $scale');

        // "Combined Gra…IN 14 DAYS": the ellipsised title used to touch it.
        final title = tester.getRect(find.text('SSC CHSL Tier-1 2026'));
        final countdown = tester.getRect(find.text('IN 9 DAYS'));
        final inlineGap = title.right + 8 <= countdown.left + 0.5;
        final stackedGap = title.bottom <= countdown.top + 0.5;
        expect(inlineGap || stackedGap, isTrue, reason: 'scale $scale');
      }
    });

    testWidgets('detail pass lays out at 320px with a 1.35 text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await seed(card());

      await tester.pumpWidget(
        harness(
          const AdmitCardDetailScreen(),
          textScaler: const TextScaler.linear(1.35),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2201098765'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('vault detail at 2.0x', () {
    testWidgets('the nav bar and pass do not overflow at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await seed(card());

      await tester.pumpWidget(
        harness(
          const AdmitCardDetailScreen(),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved Pass'), findsOneWidget);
      // The fixed 40px nav bar overflowed by 7px once the scale reached 2.0x.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dock leaves the last checklist row tappable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await seed(card());

      await tester.pumpWidget(
        harness(
          const AdmitCardDetailScreen(),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll the pass to the end, where the dock used to sit on top of the row.
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();

      final row = tester.getRect(find.text('Original photo ID'));
      final dock = tester.getRect(find.text('Check my result'));
      expect(row.bottom, lessThanOrEqualTo(dock.top));

      // Tapping the row must tick the box, not fire the dock's result button.
      await tester.tap(find.text('Original photo ID'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3 READY'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
    });

    testWidgets('pagination shows the position and count', (tester) async {
      // Disposed inline: a SemanticsHandle registered only via addTearDown is
      // still open when the binding runs its end-of-test verifications.
      final semantics = tester.ensureSemantics();
      await seed(card(id: 'a', rollNumber: '1111111111', daysFromNow: 3));
      await seed(card(id: 'b', rollNumber: '2222222222', daysFromNow: 6));
      await seed(card(id: 'c', rollNumber: '3333333333', daysFromNow: 9));

      await tester.pumpWidget(harness(const AdmitCardDetailScreen()));
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Pass 1 of 3'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Pass 2 of 3'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('deleting a pass keeps its neighbour on screen', (
      tester,
    ) async {
      await seed(card(id: 'a', rollNumber: '1111111111', daysFromNow: 3));
      await seed(card(id: 'b', rollNumber: '2222222222', daysFromNow: 6));
      await seed(card(id: 'c', rollNumber: '3333333333', daysFromNow: 9));

      await tester.pumpWidget(harness(const AdmitCardDetailScreen()));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Card options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Deleting card 2 of 3 used to throw the pager back to card 1.
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('3333333333'), findsOneWidget);
    });

    testWidgets('a gate shows even when no centre address was saved', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await seed(card(centerAddress: ''));

      await tester.pumpWidget(harness(const AdmitCardDetailScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gate 2'), findsOneWidget);
    });
  });

  group('vault form', () {
    testWidgets('validates the exam name and the roll number', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the exam name'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'SSC CGL 2026');
      await tester.pump();
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();
      expect(find.text('Roll number looks too short'), findsOneWidget);
    });

    testWidgets('roll number strips pasted spaces and caps its length', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      final roll = find.byType(TextFormField).at(3);
      await tester.enterText(roll, '1234 5678 9012 3456 7890 1234');
      await tester.pump();

      final value = tester.widget<EditableText>(
        find.descendant(of: roll, matching: find.byType(EditableText)),
      );
      expect(value.controller.text, '123456789012345678901234');
      expect(value.controller.text.length, 24);
    });

    testWidgets('cancel on a pristine form closes without asking', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard this card?'), findsNothing);
      expect(find.text('Add admit card'), findsNothing);
    });

    testWidgets('a dirty form asks before the back gesture discards it', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(const _FormHost()));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'SSC CGL 2026');
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this card?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this card?'), findsNothing);
      expect(find.text('Add admit card'), findsOneWidget);

      // System back goes through the same guard.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard this card?'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Add admit card'), findsNothing);
    });
  });
}

class _FormHost extends ConsumerWidget {
  const _FormHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showVaultFormSheet(context, ref),
          child: const Text('Open form'),
        ),
      ),
    );
  }
}

/// In-memory stand-in for the Keystore-backed store.
class InMemoryVaultStore implements SecureVaultStore {
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

  FlutterSecureStorage get storage => const FlutterSecureStorage();
}
