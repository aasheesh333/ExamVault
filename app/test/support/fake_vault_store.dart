import 'dart:async';

import 'package:examvault/data/local/secure_vault_store.dart';

/// An in-memory vault that resolves immediately.
///
/// `SecureVaultStore` talks to `flutter_secure_storage`, whose platform channel
/// does not exist under `flutter test` — and in current versions the call does
/// not fail fast, it simply never completes. Any widget test that mounts the real
/// app therefore sat in `AsyncLoading` for the vault (and, once the production
/// read was given a 5 s ceiling, left a pending timer that fails teardown).
///
/// Faking the storage primitive is the honest boundary: every test using this
/// still exercises the real repository, codec and UI.
class FakeVaultStore implements SecureVaultStore {
  FakeVaultStore({Map<String, String>? seed, this.hang = false})
    : raw = {...?seed};

  final Map<String, String> raw;

  /// When true, reads never complete — used to test the hang path.
  final bool hang;

  @override
  Future<List<String>> readIndex() async {
    if (hang) return Completer<List<String>>().future;
    final value = raw['__index'];
    if (value == null) return const [];
    return (value.split(',')).where((e) => e.isNotEmpty).toList();
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
