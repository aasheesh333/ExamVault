import 'dart:async';

import '../../domain/entities/admit_card.dart';
import '../local/secure_vault_store.dart';
import '../services/app_logger.dart';

/// Domain-facing encrypted vault.
///
/// Responsibilities:
///  * keep one in-memory copy so the UI never awaits the Keystore on scroll;
///  * serialise writes so two rapid edits cannot interleave and corrupt the
///    index;
///  * broadcast changes so Riverpod can rebuild exactly once.
class AdmitCardRepository {
  AdmitCardRepository({SecureVaultStore? store})
      : _store = store ?? SecureVaultStore();

  final SecureVaultStore _store;
  final _changes = StreamController<List<AdmitCard>>.broadcast();

  List<AdmitCard> _cache = const [];
  bool _loaded = false;

  /// Serialises mutations. Every write path funnels through this.
  Future<void> _writeQueue = Future<void>.value();

  Stream<List<AdmitCard>> get changes => _changes.stream;

  List<AdmitCard> get cached => _cache;
  bool get isLoaded => _loaded;

  Future<List<AdmitCard>> load({bool force = false}) async {
    if (_loaded && !force) return _cache;

    try {
      final ids = await _store.readIndex();
      final cards = <AdmitCard>[];

      for (final id in ids) {
        final raw = await _store.readRaw(id);
        if (raw == null) continue;
        final card = AdmitCardCodec.decode(raw);
        if (card != null) cards.add(card);
      }

      // Soonest exam first — the pass the user needs is always on top.
      cards.sort((a, b) => a.examDate.compareTo(b.examDate));

      _cache = List.unmodifiable(cards);
      _loaded = true;
      _emit();
      return _cache;
    } catch (e, st) {
      // A Keystore reset (device restore, OEM bug) must not brick the app.
      AppLogger.e('vault', 'load failed', e, st);
      _cache = const [];
      _loaded = true;
      _emit();
      return _cache;
    }
  }

  Future<AdmitCard> save(AdmitCard card) {
    return _enqueue(() async {
      final existingIndex = await _store.readIndex();
      await _store.writeRaw(card.id, AdmitCardCodec.encode(card));

      if (!existingIndex.contains(card.id)) {
        await _store.writeIndex([...existingIndex, card.id]);
      }

      final next = [..._cache];
      final at = next.indexWhere((c) => c.id == card.id);
      if (at >= 0) {
        next[at] = card;
      } else {
        next.add(card);
      }
      next.sort((a, b) => a.examDate.compareTo(b.examDate));

      _cache = List.unmodifiable(next);
      _loaded = true;
      _emit();
      return card;
    });
  }

  Future<void> delete(String id) {
    return _enqueue(() async {
      final index = await _store.readIndex();
      await _store.deleteRaw(id);
      await _store.writeIndex(index.where((e) => e != id).toList());

      _cache = List.unmodifiable(_cache.where((c) => c.id != id));
      _emit();
    });
  }

  Future<AdmitCard?> toggleChecklist(String id, ChecklistItem item) {
    return _enqueue(() async {
      final at = _cache.indexWhere((c) => c.id == id);
      if (at < 0) return null;

      final card = _cache[at];
      final next = {...card.checklist};
      if (!next.remove(item)) next.add(item);

      final updated = card.copyWith(checklist: next, updatedAt: DateTime.now());
      await _store.writeRaw(id, AdmitCardCodec.encode(updated));

      final list = [..._cache];
      list[at] = updated;
      _cache = List.unmodifiable(list);
      _emit();
      return updated;
    });
  }

  Future<AdmitCard?> markVerified(String id) {
    return _enqueue(() async {
      final at = _cache.indexWhere((c) => c.id == id);
      if (at < 0 || _cache[at].rollNumberVerified) return _cache[at];

      final updated =
          _cache[at].copyWith(rollNumberVerified: true, updatedAt: DateTime.now());
      await _store.writeRaw(id, AdmitCardCodec.encode(updated));

      final list = [..._cache];
      list[at] = updated;
      _cache = List.unmodifiable(list);
      _emit();
      return updated;
    });
  }

  AdmitCard? byId(String id) {
    for (final c in _cache) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The most urgent card (soonest exam still in the future), else the soonest.
  AdmitCard? get primaryCard {
    if (_cache.isEmpty) return null;
    final now = DateTime.now();
    for (final c in _cache) {
      if (c.examDate.isAfter(now)) return c;
    }
    return _cache.first;
  }

  Future<void> wipe() async {
    await _enqueue(() async {
      await _store.wipe();
      _cache = const [];
      _emit();
    });
  }

  /// Runs [action] after any in-flight mutation, keeping writes strictly ordered.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        AppLogger.e('vault', 'mutation failed', e, st);
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(_cache);
  }

  void dispose() => _changes.close();
}
