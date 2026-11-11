import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

import 'gunzip.dart';
import 'hashed_index.dart';

/// Outcome of one roll-number lookup.
enum RollLookupState {
  /// The roll number exists in the published index.
  found,

  /// The roll number is well-formed but absent from the index.
  notFound,

  /// The input is not a plausible roll number (too short, empty, symbols).
  invalidInput,

  /// The index could not be downloaded or decoded.
  indexUnavailable,
}

/// Immutable result returned to the UI. Deliberately tiny: it is the only thing
/// that crosses the isolate boundary, so the 150 KB–50 MB index never leaves
/// the worker thread.
@immutable
class RollLookupResult {
  const RollLookupResult({
    required this.state,
    required this.rollNumber,
    required this.totalRolls,
    required this.elapsedMicros,
    this.meritRank,
    this.errorMessage,
    this.privacyPreserving = false,
  });

  const RollLookupResult.invalid(String roll)
    : state = RollLookupState.invalidInput,
      rollNumber = roll,
      totalRolls = 0,
      elapsedMicros = 0,
      meritRank = null,
      privacyPreserving = false,
      // Must cover both rejection reasons — `_isPlausibleRoll` also rejects
      // rolls *longer* than 24 characters, and "at least 4 characters" is then
      // exactly the wrong advice (it is what TalkBack announces).
      errorMessage =
          'Roll numbers are 4–24 characters: letters, digits, - and /.';

  const RollLookupResult.unavailable(String roll, String reason)
    : state = RollLookupState.indexUnavailable,
      rollNumber = roll,
      totalRolls = 0,
      elapsedMicros = 0,
      meritRank = null,
      privacyPreserving = false,
      errorMessage = reason;

  final RollLookupState state;
  final String rollNumber;
  final int totalRolls;
  final int elapsedMicros;

  /// 1-based position in the published merit list, when the index carries ranks.
  final int? meritRank;

  final String? errorMessage;

  /// True when the answer came from a one-way hashed index — i.e. the device
  /// never held the candidate list. Surfaced in the UI so the guarantee is
  /// visible rather than a claim in a README.
  final bool privacyPreserving;

  bool get isFound => state == RollLookupState.found;
  bool get hasRank => meritRank != null && meritRank! > 0;

  Duration get elapsed => Duration(microseconds: elapsedMicros);
}

/// A decoded index that can be searched repeatedly without re-parsing.
///
/// Kept out of the isolate so the UI can hold it across taps; each subsequent
/// lookup is a pure binary search over an already-materialised list.
@immutable
class RollIndex {
  const RollIndex._({
    required this.rolls,
    required this.ranks,
    required this.total,
    required this.sorted,
    this.hashed,
  });

  /// Lexicographically sorted roll numbers.
  final List<String> rolls;

  /// Parallel to [rolls]; `null` when the upstream index carries no ranks.
  final List<int?> ranks;

  final int total;

  /// False when upstream shipped an unsorted array — we then fall back to a
  /// hash set so correctness never depends on a producer's sort contract.
  final bool sorted;

  /// Set when the published object is the v2 hashed format. In that mode [rolls]
  /// is empty by design: the device never receives the candidate list at all.
  final HashedRollIndex? hashed;

  /// True when no roll number reached this device in recoverable form.
  bool get isPrivacyPreserving => hashed != null;

  static const empty = RollIndex._(
    rolls: [],
    ranks: [],
    total: 0,
    sorted: true,
  );

  bool get isEmpty => total == 0;

  /// Decodes `gzip(json)` or plain `json` bytes into an index.
  ///
  /// Accepts both shapes the publisher may emit:
  ///   `["2201049821", "2201049822", …]`
  ///   `[{"r": "2201049821", "rank": 1284}, …]`
  factory RollIndex.decode(Uint8List bytes, {bool transportEncoded = false}) {
    final raw = transportEncoded ? bytes : gunzipBytes(bytes);
    final decoded = jsonDecode(utf8.decode(raw, allowMalformed: true));

    // v2: one-way hashed index. This is the format that is actually published —
    // it carries no roll numbers, only salted SHA-256 digests, so the object
    // cannot be used to reconstruct the official candidate list.
    if (decoded is Map && decoded['v'] == 2) {
      final hashed = HashedRollIndex.decode(decoded);
      return RollIndex._(
        rolls: const [],
        ranks: const [],
        total: hashed.total,
        sorted: hashed.sorted,
        hashed: hashed,
      );
    }

    if (decoded is! List) {
      throw const FormatException(
        'Roll index must be a JSON array (v1) or a v2 hashed object.',
      );
    }

    final rolls = <String>[];
    final ranks = <int?>[];
    var hasRank = false;

    for (final row in decoded) {
      if (row is String) {
        rolls.add(row);
        ranks.add(null);
      } else if (row is Map) {
        final r = row['r'] ?? row['roll'] ?? row['rollNumber'];
        if (r is! String) continue;
        rolls.add(r);
        final rank = row['rank'] ?? row['meritRank'];
        final parsed = rank is int ? rank : (rank is num ? rank.toInt() : null);
        ranks.add(parsed);
        hasRank = hasRank || parsed != null;
      }
    }

    // A stable contract beats a defensive scan, but a bad producer must not turn
    // into wrong answers — so verify once, cheaply, and degrade deliberately.
    var sorted = true;
    for (var i = 1; i < rolls.length; i++) {
      if (rolls[i - 1].compareTo(rolls[i]) > 0) {
        sorted = false;
        break;
      }
    }

    return RollIndex._(
      rolls: rolls,
      ranks: hasRank
          ? ranks
          : List<int?>.filled(rolls.length, null, growable: false),
      total: rolls.length,
      sorted: sorted,
    );
  }

  /// Index of [needle] in [rolls], or -1.
  int indexOf(String needle) {
    if (rolls.isEmpty) return -1;
    if (sorted) return binarySearch(rolls, needle);

    // Degraded path: upstream violated the sort contract.
    for (var i = 0; i < rolls.length; i++) {
      if (rolls[i] == needle) return i;
    }
    return -1;
  }

  int? rankAt(int index) =>
      (index >= 0 && index < ranks.length) ? ranks[index] : null;

  /// Whether [rollNumber] is in this index. Works for both formats.
  bool contains(String rollNumber) {
    final h = hashed;
    if (h != null) return h.contains(rollNumber);
    return indexOf(rollNumber) >= 0;
  }
}

/// Classic half-open binary search over a lexicographically sorted list.
///
/// Verified by `test/roll_index_engine_test.dart` against `List.indexOf` for
/// every index plus every absent neighbour, on 10 000 random inputs.
int binarySearch(List<String> sorted, String needle) {
  var low = 0;
  var high = sorted.length - 1;

  while (low <= high) {
    final mid = low + ((high - low) >> 1);
    final cmp = sorted[mid].compareTo(needle);
    if (cmp == 0) return mid;
    if (cmp < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

/// Normalises user input without corrupting legitimate values.
///
/// Strips whitespace, non-ASCII word joiners and en/em dashes that survive a
/// copy-paste out of a PDF, then upper-cases.
String normaliseRoll(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    // 0x200B zero-width space, 0x2013 en dash, 0x2014 em dash, 0x00A0 nbsp.
    if (rune == 0x200B || rune == 0x2013 || rune == 0x2014 || rune == 0x00A0) {
      continue;
    }
    final ch = String.fromCharCode(rune);
    if (ch.trim().isEmpty) continue;
    buffer.write(ch);
  }
  return buffer.toString().toUpperCase();
}

bool _isPlausibleRoll(String normalised) {
  if (normalised.length < 4 || normalised.length > 24) return false;
  for (final unit in normalised.codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isUpper = unit >= 0x41 && unit <= 0x5A;
    final isDash = unit == 0x2D || unit == 0x2F;
    if (!isDigit && !isUpper && !isDash) return false;
  }
  return true;
}

/// Runs [computation] off the UI isolate — or inline on the web.
///
/// `Isolate.run` throws `Unsupported operation: new RawReceivePort` on the web:
/// dart2js has no isolates. The app still has to work in a browser (that is how
/// it is smoke-tested), so the web path runs inline. The work is bounded — a
/// 150 KB gunzip plus one binary search — so it does not jank a frame, and the
/// caller already awaits, which yields between phases.
Future<T> _offload<T>(T Function() computation) {
  if (kIsWeb) return Future<T>(computation);
  return Isolate.run(computation);
}

/// Runs the whole decode + search pipeline on a background isolate.
///
/// A 10M-concurrent-user result day means millions of devices doing this at the
/// same second. Everything costly — gunzip, JSON parse, sort verification — is
/// pushed off the UI thread so the app never drops a frame while waiting.
abstract final class RollIndexEngine {
  /// End-to-end: compressed bytes in, verdict out. Runs in an isolate.
  static Future<RollLookupResult> searchCompressed({
    required Uint8List compressed,
    required String rollNumber,
    bool transportEncoded = false,
  }) {
    final normalised = normaliseRoll(rollNumber);
    if (!_isPlausibleRoll(normalised)) {
      return Future.value(RollLookupResult.invalid(rollNumber));
    }
    if (compressed.isEmpty) {
      return Future.value(
        RollLookupResult.unavailable(rollNumber, 'Result index is empty.'),
      );
    }

    // The closure is handed to a worker on native. Captured values are copied;
    // the 150 KB payload is well under any practical transfer budget.
    return _offload(() {
      final watch = Stopwatch()..start();
      try {
        final index = RollIndex.decode(
          compressed,
          transportEncoded: transportEncoded,
        );
        return _lookup(index, normalised, watch);
      } on FormatException catch (e) {
        return RollLookupResult.unavailable(
          rollNumber,
          'Result index is malformed (${e.message}).',
        );
      } catch (_) {
        return RollLookupResult.unavailable(
          rollNumber,
          'Could not read the result index.',
        );
      }
    });
  }

  /// Re-checks an index that is already decoded in memory. Sub-millisecond.
  static RollLookupResult searchDecoded({
    required RollIndex index,
    required String rollNumber,
  }) {
    final normalised = normaliseRoll(rollNumber);
    if (!_isPlausibleRoll(normalised)) {
      return RollLookupResult.invalid(rollNumber);
    }
    return _lookup(index, normalised, Stopwatch()..start());
  }

  /// Decodes without searching — used to warm the index right after download.
  static Future<RollIndex> decodeInIsolate(
    Uint8List bytes, {
    bool transportEncoded = false,
  }) {
    return _offload(
      () => RollIndex.decode(bytes, transportEncoded: transportEncoded),
    );
  }

  static RollLookupResult _lookup(
    RollIndex index,
    String normalised,
    Stopwatch watch,
  ) {
    final found = index.contains(normalised);
    final elapsed = watch.elapsedMicroseconds;
    if (!found) {
      return RollLookupResult(
        state: RollLookupState.notFound,
        rollNumber: normalised,
        totalRolls: index.total,
        elapsedMicros: elapsed,
        privacyPreserving: index.isPrivacyPreserving,
      );
    }
    // Ranks are only exposed by the plaintext format. Publishing a rank would leak
    // position information from the official list, which defeats the point of the
    // hashed index, so the published format omits them.
    final at = index.isPrivacyPreserving ? -1 : index.indexOf(normalised);
    return RollLookupResult(
      state: RollLookupState.found,
      rollNumber: normalised,
      totalRolls: index.total,
      elapsedMicros: elapsed,
      meritRank: at >= 0 ? index.rankAt(at) : null,
      privacyPreserving: index.isPrivacyPreserving,
    );
  }
}
