import 'dart:convert';
import 'dart:io';

import 'package:examvault/app.dart';
import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Full-journey test: a saved card must reach every screen that depends on it.
///
/// This is the loop a real user walks on day one and it had never been tested:
/// add a card → it appears on Home → Vault shows it → the checker targets *that*
/// exam (not a hardcoded one) → the share card is built from it.
void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late InMemoryVaultStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_journey');
    Hive.init(dir.path);
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('c$stamp');
    settingsBox = await Hive.openBox<dynamic>('s$stamp');
    store = InMemoryVaultStore();
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  AdmitCard card() => AdmitCard(
    id: 'chsl',
    examId: 'ssc_chsl_tier1_2026',
    category: ExamCategory.ssc,
    examName: 'SSC CHSL Tier-1 2026',
    conductingBody: 'Staff Selection Commission',
    examCode: 'CHSL · TIER-1',
    rollNumber: '2201098765',
    registrationId: 'SSC-CHSL-26-441122',
    dobOrPortalPassword: '11/05/1998',
    centerCode: 'DL-07-2210',
    centerAddress: 'Sector 9, Rohini, New Delhi',
    gate: 'Gate 2',
    reportBy: '08:00 AM',
    examDate: DateTime.now().add(const Duration(days: 9)),
    shift: '10:00 AM – 11:00 AM',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    checklist: const {ChecklistItem.admitCardPdf},
  );

  Widget app() {
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

  testWidgets('a saved card reaches Home, Vault, Checker and Share', (
    tester,
  ) async {
    await store.writeRaw(card().id, AdmitCardCodec.encode(card()));
    await store.writeIndex([card().id]);

    await pumpPhone(tester, app());

    // 1. Home shows the card.
    expect(find.textContaining('SSC CHSL Tier-1 2026'), findsWidgets);
    expect(find.textContaining('1 exam tracked'), findsOneWidget);
    expect(find.text('Add your first admit card'), findsNothing);

    // 2. Vault shows the same card with its roll number.
    await tester.tap(find.text('Vault'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2201098765'), findsWidgets);

    // 3. Checker targets *that* exam, not a hardcoded one.
    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('SSC CHSL Tier-1 2026'), findsWidgets);
    expect(find.text('Which result?'), findsNothing);

    // 4. Share builds from the same card.
    await tester.tap(find.text('Share'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nothing to share yet'), findsNothing);
    expect(find.textContaining('SSC CHSL'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the only card returns every screen to empty', (
    tester,
  ) async {
    await store.writeRaw(card().id, AdmitCardCodec.encode(card()));
    await store.writeIndex([card().id]);

    await pumpPhone(tester, app());

    final container = ProviderScope.containerOf(
      tester.element(find.text('Command Center')),
    );
    await container.read(admitCardsProvider.notifier).delete(card().id);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add your first admit card'), findsOneWidget);
    expect(find.textContaining('0 exams tracked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a checklist toggle persists through the repository', (
    tester,
  ) async {
    await store.writeRaw(card().id, AdmitCardCodec.encode(card()));
    await store.writeIndex([card().id]);

    await pumpPhone(tester, app());
    final container = ProviderScope.containerOf(
      tester.element(find.text('Command Center')),
    );

    await container
        .read(admitCardsProvider.notifier)
        .toggleChecklist(card().id, ChecklistItem.originalId);
    await tester.pump(const Duration(milliseconds: 400));

    final updated = container.read(admitCardRepositoryProvider).byId(card().id);
    expect(updated!.checklist.contains(ChecklistItem.originalId), isTrue);
    expect(store.raw[card().id], contains('originalId'));
  });
}

/// In-memory stand-in for the Keystore-backed store.
///
/// `flutter_secure_storage` needs a platform channel, which does not exist under
/// `flutter test`. The repository is exercised for real; only the storage
/// primitive is swapped.
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

  // Unused members of the concrete type.
  FlutterSecureStorage get storage => const FlutterSecureStorage();
}
