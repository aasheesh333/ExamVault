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

  /// The one in-flight store read, shared by every concurrent `load()`.
  ///
  /// Without it, two callers (a boot load plus `save()`'s reload of an unread
  /// vault, or two screens mounting at once) each ran their own Keystore read,
  /// and whichever finished *last* published its snapshot — a load that
  /// started before a save but resolved after it silently rolled the vault
  /// back to its pre-save contents.
  Future<List<AdmitCard>>? _loading;

  /// Monotonic write counter, bumped by every mutation at the moment it
  /// publishes. A load compares it across its store read and re-reads if a
  /// write landed mid-flight, so a stale snapshot can never stomp newer data.
  int _writeSeq = 0;

  /// Serialises mutations. Every write path funnels through this.
  Future<void> _writeQueue = Future<void>.value();

  Stream<List<AdmitCard>> get changes => _changes.stream;

  List<AdmitCard> get cached => _cache;
  bool get isLoaded => _loaded;

  Future<List<AdmitCard>> load({bool force = false}) async {
    if (_loaded && !force) return _cache;

    // Single-flight: join the read already in progress instead of starting a
    // second one that could resolve out of order.
    final existing = _loading;
    if (existing != null) return existing;

    final future = _loadFromStore();
    _loading = future;
    try {
      return await future;
    } finally {
      if (identical(_loading, future)) _loading = null;
    }
  }

  Future<List<AdmitCard>> _loadFromStore() async {
    try {
      // A secure-storage read can hang outright on some OEMs (Keystore bugs,
      // device restores). Without a ceiling that hang becomes a permanent
      // spinner on every screen that depends on the vault, so it is bounded and
      // treated as a failure. The *whole* load is bounded, not just the index
      // read: `readRaw` runs once per card, and a hang in that loop used to
      // escape the per-read timeout — booting the app waited on it forever.
      List<AdmitCard> cards;
      var seq = _writeSeq;
      while (true) {
        cards = await _readAllCards().timeout(_loadTimeout);
        if (seq == _writeSeq) break;
        // A mutation published while this read was in flight: its write is
        // already in the store but not in the snapshot just built. Publishing
        // that snapshot would erase the write from `_cache` (and Riverpod's
        // state) until the next boot, so re-read against the new sequence.
        seq = _writeSeq;
      }

      // Soonest exam first — the pass the user needs is always on top.
      cards.sort((a, b) => a.examDate.compareTo(b.examDate));

      _cache = List.unmodifiable(cards);
      _loaded = true;
      _emit();
      return _cache;
    } catch (e, st) {
      // Deliberately NOT cached as "empty".
      //
      // This used to set `_loaded = true` and return an empty list, which turned
      // a transient Keystore failure into a permanent, indistinguishable
      // "Add your first admit card" — the most alarming screen this app can show,
      // and unrecoverable without a reinstall. Leaving `_loaded` false and
      // rethrowing lets Riverpod publish AsyncError, so the UI can offer a retry
      // and the next read tries again.
      AppLogger.e('vault', 'load failed', e, st);
      _loaded = false;
      rethrow;
    }
  }

  Future<List<AdmitCard>> _readAllCards() async {
    final ids = await _store.readIndex().timeout(_readTimeout);
    final cards = <AdmitCard>[];
    for (final id in ids) {
      final raw = await _store.readRaw(id);
      if (raw == null) continue;
      final card = AdmitCardCodec.decode(raw);
      if (card != null) cards.add(card);
    }
    return cards;
  }

  /// Upper bound on a single secure-storage read.
  static const _readTimeout = Duration(seconds: 5);

  /// Upper bound on the whole load (index + every card body).
  static const _loadTimeout = Duration(seconds: 10);

  Future<AdmitCard> save(AdmitCard card) {
    return _enqueue(() async {
      // Never claim a loaded state we did not observe. If an earlier load
      // failed, `_cache` is empty while the *stored index* still lists the
      // user's cards; building the new cache from the empty one and flipping
      // `_loaded = true` hid every existing card behind the newly saved one
      // until an app restart. Reload first (bounded); if the store is genuinely
      // unreadable the save fails loudly instead of lying about the vault's
      // contents.
      if (!_loaded) {
        await load(force: true);
      }

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

      // Bumped in the same synchronous block as the publish below: an in-flight
      // load either sees this and re-reads the store, or published before this
      // block ran — in which case the rebase on `_cache` here already includes
      // its snapshot. Either ordering ends with the saved card visible.
      _writeSeq++;
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

      _writeSeq++;
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
      _writeSeq++;
      _cache = List.unmodifiable(list);
      _emit();
      return updated;
    });
  }

  Future<AdmitCard?> markVerified(String id) {
    return _enqueue(() async {
      final at = _cache.indexWhere((c) => c.id == id);
      // Not found is normal, not an error: a student checking a result straight
      // from the radar has no saved card, and the caller passes an empty id.
      // This used to fall through to `_cache[-1]`, throwing a RangeError that
      // aborted the caller before it could show the result — so on a fresh
      // install a correct "you are selected" produced no dialog at all.
      if (at < 0) return null;
      if (_cache[at].rollNumberVerified) return _cache[at];

      final updated = _cache[at].copyWith(
        rollNumberVerified: true,
        updatedAt: DateTime.now(),
      );
      await _store.writeRaw(id, AdmitCardCodec.encode(updated));

      final list = [..._cache];
      list[at] = updated;
      _writeSeq++;
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

  /// Deletes every card and the index, then empties the in-memory copy.
  ///
  /// This is the vault half of "Delete all data": the settings keys, the cached
  /// feed and the HTTP cache are wiped alongside it by `DataWiper`
  /// (`providers/app_providers.dart`). The change stream emits the empty list,
  /// so every screen empties without a restart.
  Future<void> wipe() async {
    await _enqueue(() async {
      await _store.wipe();
      _writeSeq++;
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
