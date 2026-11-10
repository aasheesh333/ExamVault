import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One-way roll-number index.
///
/// ## Why this exists
///
/// The app must answer "am I selected?" without making the student download a
/// 60 MB PDF — but publishing the official candidate list as plain text is a
/// copyright grey area, and re-hosting the PDF outright is clearly not ours to do.
///
/// So the published object contains **no roll numbers at all**. It contains only
/// the SHA-256 of each roll number (salted, truncated to 8 bytes), sorted. Checking
/// a roll hashes the input and binary-searches. The object therefore answers exactly
/// one question per query — "is this specific roll present?" — and cannot be used to
/// enumerate the candidate list, because recovering 10 000 preimages would require
/// brute-forcing the entire roll space for every entry.
///
/// What is published is a derived, non-invertible artefact. What is not published
/// is the list itself, the source PDF, or any way to reconstruct either.
///
/// ## Wire format (v2)
///
/// ```json
/// {
///   "v": 2,
///   "mode": "sha256-8-salted",
///   "salt": "b4c1…",
///   "total": 10066,
///   "hashes": ["00a1b2…", "…"]     // 16 lowercase hex chars, ascending
/// }
/// ```
///
/// `salt` is public on purpose: it prevents an attacker precomputing a rainbow
/// table for the roll space, but it is not a secret and does not need protecting.
class HashedRollIndex {
  const HashedRollIndex({
    required this.salt,
    required this.hashes,
    required this.total,
    required this.sorted,
  });

  final String salt;

  /// Ascending lowercase hex digests, truncated to 8 bytes (16 hex chars).
  final List<String> hashes;

  /// Number of candidates in the original list. Disclosed because it is already
  /// public knowledge (SSC publishes the count) and it lets the UI say
  /// "searched N candidates".
  final int total;

  final bool sorted;

  static const int digestBytes = 8;
  static const String mode = 'sha256-8-salted';

  static const empty = HashedRollIndex(
    salt: '',
    hashes: [],
    total: 0,
    sorted: true,
  );

  bool get isEmpty => hashes.isEmpty;

  /// Hashes a roll number with [salt] and returns the 16-char hex digest.
  ///
  /// Normalisation happens before hashing so that a roll pasted out of a PDF with
  /// a non-breaking space hashes identically to a typed one. This is the only
  /// place that must agree with `tools/extract_rolls.py`.
  static String digest(String rollNumber, String salt) {
    final normalised = normalise(rollNumber);
    final bytes = utf8.encode('$salt:$normalised');
    final hash = sha256.convert(bytes).bytes;
    final buffer = StringBuffer();
    for (var i = 0; i < digestBytes; i++) {
      buffer.write(hash[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Decimal-safe normalisation: strip whitespace/zero-width/dashes, uppercase.
  ///
  /// Kept byte-for-byte in sync with the Python extractor. If these drift, every
  /// lookup silently fails — which is why `hashed_index_test.dart` pins both.
  static String normalise(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      // U+200B zero-width space, U+00A0 nbsp, U+2013 en dash, U+2014 em dash.
      if (rune == 0x200B ||
          rune == 0x00A0 ||
          rune == 0x2013 ||
          rune == 0x2014) {
        continue;
      }
      final ch = String.fromCharCode(rune);
      if (ch.trim().isEmpty) continue;
      buffer.write(ch);
    }
    return buffer.toString().toUpperCase();
  }

  /// Binary search for [rollNumber]. Returns true when present.
  bool contains(String rollNumber) {
    if (hashes.isEmpty || salt.isEmpty) return false;
    final needle = digest(rollNumber, salt);
    var low = 0;
    var high = hashes.length - 1;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final cmp = hashes[mid].compareTo(needle);
      if (cmp == 0) return true;
      if (cmp < 0) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return false;
  }

  factory HashedRollIndex.decode(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException('Hashed index must be a JSON object.');
    }

    final salt = decoded['salt'];
    final rawHashes = decoded['hashes'];
    if (salt is! String || salt.isEmpty) {
      throw const FormatException('Hashed index is missing its salt.');
    }
    if (rawHashes is! List) {
      throw const FormatException('Hashed index is missing its hash array.');
    }

    final hashes = <String>[];
    for (final h in rawHashes) {
      if (h is String && h.length == digestBytes * 2) hashes.add(h);
    }

    var sorted = true;
    for (var i = 1; i < hashes.length; i++) {
      if (hashes[i - 1].compareTo(hashes[i]) > 0) {
        sorted = false;
        break;
      }
    }

    final total = decoded['total'];
    return HashedRollIndex(
      salt: salt,
      hashes: hashes,
      total: total is int ? total : hashes.length,
      sorted: sorted,
    );
  }
}
