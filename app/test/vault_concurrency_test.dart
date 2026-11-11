import 'dart:async';
import 'dart:convert';

import 'package:examvault/data/local/secure_vault_store.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/domain/entities/admit_card.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vault races: a Keystore read is slow, users are not.
///
/// Each case maps to a defect where a load and a write overlapped and the
/// *older* snapshot won: a save landed while the boot load was in flight and
/// was then silently erased from both the repository cache and the provider
/// state, and two concurrent loads ran two competing store reads whose
/// resolution order decided what the user saw.
void main() {
  AdmitCard card(String id, {int daysFromNow = 9}) => AdmitCard(
    id: id,
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
    examDate: DateTime.now().add(Duration(days: daysFromNow)),
    shift: '10:00 AM – 11:00 AM',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  /// The store shape `FakeVaultStore` uses: id -> encoded card, plus a
  /// comma-joined `__index`.
  Map<String, String> seed(Iterable<AdmitCard> cards) => {
    for (final c in cards) c.id: AdmitCardCodec.encode(c),
    '__index': cards.map((c) => c.id).join(','),
  };

  group('load/save races', () {
    test(
      'a save during an in-flight load ends with both cards visible',
      () async {
        final existing = card('card_a', daysFromNow: 5);
        final gate = Completer<void>();
        final store = _ControllableVaultStore(seed: seed([existing]))
          ..gate = gate;
        final repo = AdmitCardRepository(store: store);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [admitCardRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        // The provider's build starts the load, which parks on the gate — the
        // slow-Keystore window in which a user taps "Save to vault".
        final built = container.read(admitCardsProvider.future);
        final saving = container
            .read(admitCardsProvider.notifier)
            .save(card('card_b', daysFromNow: 20));

        // Let every caller reach the store; both now hang on the same gate.
        await Future<void>.delayed(Duration.zero);
        expect(container.read(admitCardsProvider).isLoading, isTrue);

        gate.complete();
        store.gate = null;
        await saving;
        await built;

        // The bug: the pre-save load snapshot resolved last and stomped the
        // cache, and the build future — resolving to the *captured* list —
        // then overwrote the state the save had written. Both cards must be
        // visible in the provider AND in the repository.
        final state = container.read(admitCardsProvider);
        expect(state.hasValue, isTrue);
        expect(state.value!.map((c) => c.id), ['card_a', 'card_b']);
        expect(repo.cached.map((c) => c.id), ['card_a', 'card_b']);
        expect((await store.readIndex()).toSet(), {'card_a', 'card_b'});
      },
    );

    test('a save during a forced reload is not stomped by it', () async {
      final store = _ControllableVaultStore(
        seed: seed([card('card_a', daysFromNow: 5)]),
      );
      final repo = AdmitCardRepository(store: store);
      addTearDown(repo.dispose);

      await repo.load();
      expect(repo.cached.map((c) => c.id), ['card_a']);

      // A forced reload (the retry path) parks mid-read with a snapshot that
      // predates the save below.
      final gate = Completer<void>();
      store.gate = gate;
      final reloading = repo.load(force: true);
      await Future<void>.delayed(Duration.zero);
      store.gate = null;

      // `_loaded` is true, so the save does NOT join the reload — it writes
      // and publishes while the stale read is still in flight.
      await repo.save(card('card_b', daysFromNow: 20));
      expect(repo.cached.map((c) => c.id), ['card_a', 'card_b']);

      gate.complete();
      await reloading;

      // The reload's snapshot ([card_a] only) must not win: the write-seq
      // guard forces a re-read before publishing.
      expect(repo.cached.map((c) => c.id), ['card_a', 'card_b']);
    });

    test('two concurrent loads perform exactly one store read', () async {
      final store = _ControllableVaultStore(seed: seed([card('card_a')]));
      final repo = AdmitCardRepository(store: store);
      addTearDown(repo.dispose);

      final first = repo.load();
      final second = repo.load();
      final results = await Future.wait([first, second]);

      expect(
        store.indexReads,
        1,
        reason: 'the second load must join the in-flight first',
      );
      expect(results[0], same(results[1]));
      expect(results[0].map((c) => c.id), ['card_a']);
    });
  });

  group('honest failure (resetOnError is off)', () {
    test('a throwing store surfaces AsyncError, never AsyncData([])', () async {
      final repo = AdmitCardRepository(store: _ThrowingVaultStore());
      addTearDown(repo.dispose);

      final container = ProviderContainer(
        overrides: [admitCardRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // With AndroidOptions(resetOnError: true) the plugin deleted the keys on
      // a read failure and reported success-with-null, so this path returned
      // an empty vault and the UI said "Add your first admit card" over data
      // that had just been erased. The failure must reach the state instead.
      await expectLater(
        container.read(admitCardsProvider.future),
        throwsA(isA<StateError>()),
      );

      final state = container.read(admitCardsProvider);
      expect(state.hasError, isTrue);
      expect(
        state.hasValue,
        isFalse,
        reason: 'an unreadable vault must not masquerade as an empty one',
      );
    });
  });

  group('codec degradation', () {
    String cardJson(List<Object?> checklist) => jsonEncode({
      'v': 1,
      'id': 'card_a',
      'examId': 'ssc_cgl_tier1_2026',
      'category': 'ssc',
      'examName': 'SSC CGL Tier-1 2026',
      'conductingBody': 'Staff Selection Commission',
      'examCode': 'CGL · TIER-1',
      'roll': '2201049821',
      'regId': 'SSC-CGL-26-884213',
      'dob': '14/03/1999',
      'centerCode': 'DL-04-1187',
      'centerAddress': 'Sector 12, Dwarka, New Delhi',
      'gate': 'Gate 3',
      'reportBy': '08:15 AM',
      'examDate': DateTime(2026, 11, 20).toIso8601String(),
      'shift': '09:00 AM – 10:00 AM',
      'createdAt': DateTime(2026, 11, 1, 9, 30).toIso8601String(),
      'updatedAt': DateTime(2026, 11, 2, 10, 15).toIso8601String(),
      'verified': false,
      'checklist': checklist,
    });

    test('a non-string checklist entry is skipped, the card survives', () {
      // `item as String?` threw a TypeError on the int, and the outer catch
      // discarded the ENTIRE card — one bad array element erased the student's
      // saved credentials from the vault.
      final decoded = AdmitCardCodec.decode(cardJson([1, 'admitCardPdf']));
      expect(decoded, isNotNull);
      expect(decoded!.checklist, {ChecklistItem.admitCardPdf});
    });

    test('all-invalid checklist entries still keep the card', () {
      final decoded = AdmitCardCodec.decode(cardJson([1, 'admit_pdf']));
      expect(decoded, isNotNull, reason: 'the card must not be discarded');
      expect(decoded!.checklist, isEmpty);
      expect(decoded.id, 'card_a');
      expect(decoded.rollNumber, '2201049821');
    });
  });
}

/// In-memory vault the test drives by hand.
///
/// `readIndex` snapshots the stored value at *call* time — like a Keystore read
/// that already ran — and then, when [gate] is set, delays *delivering* it
/// until the test releases the gate. That models the exact race the fixes
/// address: a read whose answer is stale by the time it lands. Every read is
/// counted so single-flight behaviour can be asserted.
class _ControllableVaultStore implements SecureVaultStore {
  _ControllableVaultStore({Map<String, String>? seed}) : raw = {...?seed};

  final Map<String, String> raw;

  Completer<void>? gate;
  var indexReads = 0;

  @override
  Future<List<String>> readIndex() async {
    indexReads++;
    final value = raw['__index'];
    final g = gate;
    if (g != null) await g.future;
    if (value == null) return const [];
    return value.split(',').where((e) => e.isNotEmpty).toList();
  }

  @override
  Future<void> writeIndex(List<String> ids) async {
    raw['__index'] = ids.join(',');
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

/// A vault whose every read fails, the way an unavailable Keystore does.
class _ThrowingVaultStore implements SecureVaultStore {
  @override
  Future<List<String>> readIndex() async =>
      throw StateError('keystore unavailable');

  @override
  Future<String?> readRaw(String id) async =>
      throw StateError('keystore unavailable');

  @override
  Future<void> writeIndex(List<String> ids) async =>
      throw StateError('keystore unavailable');

  @override
  Future<void> writeRaw(String id, String payload) async =>
      throw StateError('keystore unavailable');

  @override
  Future<void> deleteRaw(String id) async =>
      throw StateError('keystore unavailable');

  @override
  Future<Map<String, String>> readAllRaw() async =>
      throw StateError('keystore unavailable');

  @override
  Future<void> wipe() async => throw StateError('keystore unavailable');
}
