import 'dart:convert';

import '../../core/config/app_config.dart';
import '../../domain/entities/admit_card.dart';
import '../../domain/entities/exam_category.dart';
import '../services/app_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wire format for a vault entry.
///
/// The blob is stored as a JSON string inside `flutter_secure_storage`, which on
/// Android is backed by `EncryptedSharedPreferences` over a hardware-backed
/// Keystore key. The ciphertext never leaves the device and is excluded from
/// Android Auto Backup (see `AndroidManifest.xml`).
abstract final class AdmitCardCodec {
  static String encode(AdmitCard c) => jsonEncode({
    'v': 1,
    'id': c.id,
    'examId': c.examId,
    'category': c.category.id,
    'examName': c.examName,
    'conductingBody': c.conductingBody,
    'examCode': c.examCode,
    'roll': c.rollNumber,
    'regId': c.registrationId,
    'dob': c.dobOrPortalPassword,
    'centerCode': c.centerCode,
    'centerAddress': c.centerAddress,
    'gate': c.gate,
    'reportBy': c.reportBy,
    'examDate': c.examDate.toIso8601String(),
    'shift': c.shift,
    'createdAt': c.createdAt.toIso8601String(),
    'updatedAt': c.updatedAt.toIso8601String(),
    'verified': c.rollNumberVerified,
    'checklist': c.checklist.map((e) => e.id).toList(),
    'name': c.candidateName,
  });

  /// Returns null for anything that cannot be trusted, so a half-written entry
  /// from a killed process can never crash the vault.
  static AdmitCard? decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;

      final category = ExamCategory.fromId(map['category'] as String?);
      final examDate = DateTime.tryParse(map['examDate'] as String? ?? '');
      final createdAt = DateTime.tryParse(map['createdAt'] as String? ?? '');
      final id = map['id'];
      final examName = map['examName'];
      final roll = map['roll'];

      if (category == null ||
          examDate == null ||
          createdAt == null ||
          id is! String ||
          examName is! String ||
          roll is! String) {
        return null;
      }

      final checklistRaw = map['checklist'];
      final checklist = <ChecklistItem>{};
      if (checklistRaw is List) {
        for (final item in checklistRaw) {
          // Per-item tolerance, like every other field above: `item as String?`
          // threw a TypeError on a single non-string entry, and the outer catch
          // then discarded the ENTIRE card — one malformed element in the array
          // silently erased a student's saved credentials from the vault.
          final parsed = ChecklistItem.fromId(item is String ? item : null);
          if (parsed != null) checklist.add(parsed);
        }
      }

      return AdmitCard(
        id: id,
        examId: map['examId'] as String? ?? '',
        category: category,
        examName: examName,
        conductingBody: map['conductingBody'] as String? ?? '',
        examCode: map['examCode'] as String? ?? '',
        rollNumber: roll,
        registrationId: map['regId'] as String? ?? '',
        dobOrPortalPassword: map['dob'] as String? ?? '',
        centerCode: map['centerCode'] as String? ?? '',
        centerAddress: map['centerAddress'] as String? ?? '',
        gate: map['gate'] as String? ?? '',
        reportBy: map['reportBy'] as String? ?? '',
        examDate: examDate,
        shift: map['shift'] as String? ?? '',
        createdAt: createdAt,
        updatedAt:
            DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? createdAt,
        rollNumberVerified: map['verified'] == true,
        checklist: checklist,
        // Cards saved before the field existed carry no 'name' key: absent is
        // empty, never an error (same per-field tolerance as the rest).
        candidateName: map['name'] is String ? map['name'] as String : '',
      );
    } catch (e) {
      AppLogger.w('vault', 'discarding unreadable entry: $e');
      return null;
    }
  }
}

/// Low-level encrypted storage for admit cards.
///
/// The *index* of ids lives in the same encrypted store as the values. That is
/// intentional: an id alone leaks nothing, but keeping them together means one
/// corruption surface instead of two.
class SecureVaultStore {
  SecureVaultStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Hardware-backed AES-GCM with RSA-OAEP key wrapping; the default
            // in v11 and the strongest non-biometric option.
            //
            // resetOnError is explicitly OFF — and note the plugin defaults it
            // to *true*, so removing the flag would not disable it. With it on,
            // the Android side runs handleStorageError(deleteOnFailure) on a
            // read failure: it deletes the key (or every key, on readAll),
            // retries, and reports *success* with a null value. A transient
            // Keystore fault therefore erased the user's admit cards and told
            // Dart nothing had happened, which made the repository's documented
            // rethrow-and-retry defence dead code. An honest error the UI can
            // retry is recoverable; a silent wipe is not.
            aOptions: AndroidOptions(resetOnError: false),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _key(String id) => '${AppConfig.secureNamespace}.card.$id';

  Future<List<String>> readIndex() async {
    final raw = await _storage.read(key: AppConfig.secureIndexKey);
    // A missing key is the only "empty" this method may report. Anything else
    // that fails to decode is corruption and must THROW: returning `const []`
    // on a decode failure made a damaged index indistinguishable from an empty
    // vault, and the next save() then rewrote the index from that empty
    // baseline — orphaning every card still sitting in the store. The
    // repository rethrows the failure so Riverpod can publish AsyncError and
    // the UI can offer a retry.
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('vault index is not a JSON list: $decoded');
    }
    return decoded.whereType<String>().toList(growable: false);
  }

  Future<void> writeIndex(List<String> ids) =>
      _storage.write(key: AppConfig.secureIndexKey, value: jsonEncode(ids));

  Future<String?> readRaw(String id) => _storage.read(key: _key(id));

  Future<void> writeRaw(String id, String payload) =>
      _storage.write(key: _key(id), value: payload);

  Future<void> deleteRaw(String id) => _storage.delete(key: _key(id));

  Future<Map<String, String>> readAllRaw() => _storage.readAll();

  /// Wipes every key this app owns. Used by "Delete all data".
  Future<void> wipe() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(AppConfig.secureNamespace)) {
        await _storage.delete(key: key);
      }
    }
  }
}
