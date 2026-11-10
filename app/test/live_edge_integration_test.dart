import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:examvault/core/config/app_config.dart';
import 'package:examvault/features/result_checker/engine/gunzip.dart';
import 'package:examvault/features/result_checker/engine/roll_index_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// End-to-end proof against the **real published object**.
///
/// Everything else in the suite uses fixtures. This test reads the live feed,
/// takes the exam the app would offer, downloads the exact index the app
/// downloads, and searches it. If any link in the chain breaks — the feed field,
/// the content-addressed R2 key, the gzip format, the sort order, the digest —
/// this fails.
///
/// It also asserts the copyright guarantee against the real wire bytes: the
/// object must not contain the candidate list in recoverable form.
///
/// Skipped automatically when the network is unavailable, because a CI runner
/// without egress must not report a product bug.
void main() {
  const edge = 'https://examvault-edge.aasheeshkatheriya.workers.dev';

  test('the live feed offers a searchable result and its index is hashed', () async {
    late http.Response feedRes;
    try {
      feedRes = await http
          .get(Uri.parse('$edge${AppConfig.liveFeedPath}'))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      markTestSkipped('edge unreachable: $e');
      return;
    }
    expect(feedRes.statusCode, 200, reason: 'the feed must be published');

    // Take whatever the feed currently offers instead of hardcoding an exam id.
    // The result cycle moves every month; a pinned id would rot, and pinning a
    // real candidate's roll number would put their data in a public repo.
    final feed = jsonDecode(feedRes.body) as Map<String, dynamic>;
    final updates = (feed['updates'] as List).cast<Map<String, dynamic>>();
    // Pick the largest published list: a small final list is legitimate (a
    // 30-post LDCE publishes 30 rolls), but the count assertion below is only
    // meaningful on a real shortlist.
    final indexed =
        updates
            .where(
              (u) =>
                  u['index_available'] == true &&
                  u['index_version'] is String &&
                  u['roll_count'] is num,
            )
            .toList()
          ..sort(
            (a, b) =>
                (b['roll_count'] as num).compareTo(a['roll_count'] as num),
          );
    final row = indexed.isEmpty ? const <String, dynamic>{} : indexed.first;
    if (row.isEmpty) {
      markTestSkipped('feed currently advertises no published index');
      return;
    }

    final examId = row['exam_id'] as String;
    final version = row['index_version'] as String;
    final url = '$edge${AppConfig.rollIndexPath(examId, version: version)}';

    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      fail(
        'index missing from the edge (HTTP ${res.statusCode}) at $url — the '
        'publisher or the R2 key changed',
      );
    }

    final bytes = Uint8List.fromList(res.bodyBytes);
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

    // --- The copyright guarantee, asserted on the real bytes ---------------
    expect(
      index.isPrivacyPreserving,
      isTrue,
      reason: 'published indexes must be the v2 hashed format',
    );
    expect(
      index.rolls,
      isEmpty,
      reason: 'the device must never receive the candidate list',
    );

    final raw = utf8.decode(gunzipBytes(bytes), allowMalformed: true);
    expect(
      RegExp(r'\b1\d{11}\b').allMatches(raw).length,
      0,
      reason: 'the published object must not reproduce the official roll list',
    );

    // --- The product guarantee ---------------------------------------------
    final miss = RollIndexEngine.searchDecoded(
      index: index,
      rollNumber: '999999999999',
    );
    expect(miss.isFound, isFalse);
    expect(miss.privacyPreserving, isTrue);

    // A genuine hit cannot be derived from a hash, and committing a real
    // candidate's roll number to the repository would be its own privacy
    // problem. So the positive path is opt-in:
    //   EV_LIVE_ROLL=1234567890 flutter test test/live_edge_integration_test.dart
    final live = Platform.environment['EV_LIVE_ROLL'];
    if (live == null || live.isEmpty) {
      // ignore: avoid_print
      print('structural proof only — set EV_LIVE_ROLL to also assert a hit');
      return;
    }

    final hit = RollIndexEngine.searchDecoded(index: index, rollNumber: live);
    expect(hit.isFound, isTrue, reason: 'EV_LIVE_ROLL=$live should be listed');
    expect(hit.privacyPreserving, isTrue);
    expect(hit.elapsedMicros, lessThan(5000));

    // ignore: avoid_print
    print(
      'verified ${index.total} hashed rolls from $examId@$version · '
      'lookup=${hit.elapsedMicros}µs',
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
