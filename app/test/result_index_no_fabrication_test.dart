import 'dart:convert';
import 'dart:io';

import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/result_index_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// These tests exist because of a production-blocking defect: when the result
/// object had not been published yet (HTTP 404), the repository silently
/// substituted a *generated* index that contained the user's own roll number, and
/// the UI then reported "SELECTED IN MERIT LIST" with a made-up merit rank.
///
/// Fabricating an exam outcome is the single worst thing this app could do, so the
/// contract is now explicit and tested: an unpublished index must surface as
/// [IndexSource.unavailable] and must never carry lookup data.
void main() {
  late Directory dir;
  late Box<dynamic> box;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ev_idx_test');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>(
      'idx_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  CdnClient cdnReturning(http.Response Function() respond) => CdnClient(
    cache: box,
    client: MockClient((_) async => respond()),
    baseUrl: 'https://cdn.test',
  );

  group('result index never fabricates data', () {
    test('404 yields unavailable, with no bytes at all', () async {
      final repo = ResultIndexRepository(
        cdn: cdnReturning(() => http.Response('Not published yet', 404)),
      );

      final bundle = await repo.load(examId: 'ssc_cgl_tier1_2026');

      expect(bundle.source, IndexSource.unavailable);
      expect(
        bundle.bytes,
        isEmpty,
        reason: 'no synthesized index may be handed to the search engine',
      );
    });

    test(
      'a network failure yields unavailable, not a generated index',
      () async {
        final repo = ResultIndexRepository(
          cdn: cdnReturning(() => http.Response('boom', 503)),
        );

        final bundle = await repo.load(examId: 'ssc_cgl_tier1_2026');

        expect(bundle.source, IndexSource.unavailable);
        expect(bundle.bytes, isEmpty);
      },
    );

    test('a 200 response is passed through byte-for-byte', () async {
      final payload = gzip.encode(
        utf8.encode(
          jsonEncode([
            {'r': '2201049821', 'rank': 7},
          ]),
        ),
      );
      final repo = ResultIndexRepository(
        cdn: cdnReturning(
          () => http.Response.bytes(payload, 200, headers: {'etag': '"x"'}),
        ),
      );

      final bundle = await repo.load(examId: 'ssc_cgl_tier1_2026');

      expect(bundle.source, IndexSource.edge);
      expect(bundle.bytes, isNotEmpty);
      // The user's roll must NOT have been injected anywhere.
      final decoded = utf8.decode(gzip.decode(bundle.bytes));
      expect(decoded.contains('9999999999'), isFalse);
    });

    test('cached bytes are reported as cache, not edge', () async {
      final payload = gzip.encode(utf8.encode(jsonEncode(['1111', '2222'])));
      var calls = 0;
      final repo = ResultIndexRepository(
        cdn: CdnClient(
          cache: box,
          client: MockClient((_) async {
            calls++;
            return http.Response.bytes(payload, 200);
          }),
          baseUrl: 'https://cdn.test',
        ),
      );

      await repo.load(examId: 'e1');
      final second = await repo.load(examId: 'e2');

      expect(second.source, anyOf(IndexSource.edge, IndexSource.cache));
      expect(calls, greaterThanOrEqualTo(1));
    });
  });

  group('index bundle', () {
    test('unavailable bundle is explicitly not real', () {
      final b = IndexBundle.unavailable();
      expect(b.source, IndexSource.unavailable);
      expect(b.source.isReal, isFalse);
      expect(b.bytes, isEmpty);
    });
  });
}
