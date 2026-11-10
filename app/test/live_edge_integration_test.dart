
import 'package:examvault/features/result_checker/engine/roll_index_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// End-to-end proof against the **real published index**.
///
/// Everything else in the suite uses fixtures. This test downloads the actual
/// object the app downloads, from the actual edge, and looks up a real roll
/// number that appears in the official SSC PDF. If any link in the chain breaks
/// — the R2 key, the gzip format, the sort order, the binary search — this fails.
///
/// Skipped automatically when the network is unavailable, because a CI runner
/// without egress must not report a product bug.
void main() {
  const edge = 'https://examvault-edge.aasheeshkatheriya.workers.dev';
  const examId = 's40d16nackd16h0_gsnhl7k5fqtrfr3zzmtfj';

  test('finds a real roll in the real index, and rejects a fake one', () async {
    late http.Response res;
    try {
      res = await http
          .get(Uri.parse('$edge/v1/rolls/${examId}_rolls.json.gz'))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      markTestSkipped('edge unreachable: $e');
      return;
    }

    if (res.statusCode != 200) {
      fail(
        'index missing from the edge (HTTP ${res.statusCode}) — the '
        'publisher or the R2 key changed',
      );
    }

    final bytes = res.bodyBytes;
    expect(bytes, isNotEmpty);

    // Decode once, off an isolate, exactly like the app does.
    final index = await RollIndexEngine.decodeInIsolate(bytes);
    expect(
      index.total,
      greaterThan(1000),
      reason:
          'a real shortlist is thousands of rows; '
          '${index.total} suggests a writeup PDF was published by mistake',
    );
    expect(index.sorted, isTrue, reason: 'binary search depends on it');

    // A roll that genuinely exists in the published PDF.
    final real = index.rolls[index.total ~/ 2];
    final hit = RollIndexEngine.searchDecoded(index: index, rollNumber: real);
    expect(hit.isFound, isTrue, reason: 'middle element must be findable');
    expect(hit.elapsedMicros, lessThan(5000));

    // A roll that cannot exist: same length, different digits.
    final fake = '9${real.substring(1)}';
    final miss = RollIndexEngine.searchDecoded(index: index, rollNumber: fake);
    expect(miss.isFound, isFalse);

    // And the whole compressed path, as the app runs it.
    final compressed = await RollIndexEngine.searchCompressed(
      compressed: bytes,
      rollNumber: real,
    );
    expect(compressed.state, RollLookupState.found);
    expect(compressed.totalRolls, index.total);

    // ignore: avoid_print
    print(
      'verified ${index.total} real rolls · middle=$real · '
      'lookup=${compressed.elapsedMicros}µs',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('an unpublished exam is reported honestly, never guessed', () async {
    final res = await http
        .get(Uri.parse('$edge/v1/rolls/this_exam_does_not_exist_rolls.json.gz'))
        .timeout(const Duration(seconds: 30));

    expect(res.statusCode, 404);

    // The body is a human-readable sentence, not an index. What matters is that
    // it cannot be mistaken for one: a gzip index always starts with 0x1f 0x8b.
    expect(
      res.bodyBytes.length >= 2 &&
          res.bodyBytes[0] == 0x1f &&
          res.bodyBytes[1] == 0x8b,
      isFalse,
      reason: 'a 404 must never look like a valid index',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
