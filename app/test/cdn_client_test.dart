import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:examvault/data/remote/cdn_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = 'https://cdn.test';
const _path = '/v1/live_feed_v1.json';

void main() {
  late Directory dir;
  late Box<dynamic> box;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ev_cdn_test');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('t_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  CdnClient client(http.Client inner, {int? seed}) => CdnClient(
        cache: box,
        client: inner,
        baseUrl: _base,
      );

  group('single-flight', () {
    test('N concurrent gets produce exactly one socket', () async {
      var calls = 0;
      final gate = Completer<void>();

      final inner = MockClient((req) async {
        calls++;
        await gate.future;
        return http.Response('{"ok":true}', 200);
      });

      final c = client(inner);

      final futures = List.generate(12, (_) => c.get(_path, freshWindow: Duration.zero));
      gate.complete();
      await Future.wait(futures);

      expect(calls, 1, reason: '12 callers must coalesce into one request');
      expect(c.inflightCount, 0);
    });

    test('a second get after completion hits the fresh cache, not the network',
        () async {
      var calls = 0;
      final inner = MockClient((req) async {
        calls++;
        return http.Response('{"ok":true}', 200);
      });

      final c = client(inner);
      await c.get(_path, freshWindow: const Duration(minutes: 5));
      final second = await c.get(_path, freshWindow: const Duration(minutes: 5));

      expect(calls, 1);
      expect(second.fromCache, isTrue);
    });
  });

  group('conditional GET', () {
    test('sends If-None-Match and serves the cached body on 304', () async {
      const etag = '"abc123"';
      var calls = 0;
      final headersSeen = <String, String?>{};

      final inner = MockClient((req) async {
        calls++;
        headersSeen['inm'] = req.headers['If-None-Match'];
        if (calls == 1) {
          return http.Response('{"v":1}', 200, headers: {'etag': etag});
        }
        return http.Response('', 304);
      });

      final c = client(inner);

      final first = await c.get(_path, freshWindow: Duration.zero);
      // bypassCache forces a network attempt even though the entry is new.
      final second = await c.get(_path, freshWindow: Duration.zero, bypassCache: true);

      expect(calls, 2);
      expect(headersSeen['inm'], etag, reason: 'must revalidate, not re-download');
      expect(utf8.decode(second.bytes), '{"v":1}');
      expect(second.fromCache, isTrue);
      expect(first.etag, etag);
    });
  });

  group('failure handling', () {
    test('serves stale cache when every attempt fails', () async {
      var calls = 0;
      final inner = MockClient((req) async {
        calls++;
        if (calls == 1) return http.Response('stale-body', 200);
        return http.Response('boom', 503);
      });

      final c = client(inner);
      await c.get(_path, freshWindow: Duration.zero);

      final result = await c.get(_path, freshWindow: Duration.zero);
      expect(result.fromCache, isTrue);
      expect(utf8.decode(result.bytes), 'stale-body');
      expect(calls, greaterThan(1), reason: 'should have retried');
    });

    test('404 is not retried — it means "not published yet"', () async {
      var calls = 0;
      final inner = MockClient((req) async {
        calls++;
        return http.Response('nope', 404);
      });

      final c = client(inner);
      await expectLater(
        c.get(_path, freshWindow: Duration.zero),
        throwsA(isA<CdnException>().having((e) => e.statusCode, 'status', 404)),
      );
      expect(calls, 1, reason: '404 must not burn the retry budget');
    });

    test('rejects an object larger than the download budget (declared length)',
        () async {
      // Declares 100 MB but streams nothing: the guard must fire on the header
      // alone, before a single megabyte is buffered on a user's phone.
      final inner = MockClient.streaming((req, bodyStream) async {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          200,
          contentLength: 100 * 1024 * 1024,
        );
      });

      final c = client(inner);
      await expectLater(
        c.get(_path, freshWindow: Duration.zero),
        throwsA(isA<CdnException>()),
      );
    });

    test('rejects an object that grows past the budget mid-stream', () async {
      // No content-length (chunked), so the guard has to count as it reads.
      final inner = MockClient.streaming((req, bodyStream) async {
        final chunk = Uint8List(1024 * 1024);
        final controller = StreamController<List<int>>();
        // 14 MB in 1 MB chunks, then done.
        scheduleMicrotask(() async {
          for (var i = 0; i < 14; i++) {
            controller.add(chunk);
          }
          await controller.close();
        });
        return http.StreamedResponse(controller.stream, 200);
      });

      final c = client(inner);
      await expectLater(
        c.get(_path, freshWindow: Duration.zero),
        throwsA(isA<CdnException>()),
      );
    });

    test('surfaces a typed exception when there is nothing cached', () async {
      final inner = MockClient((req) async => http.Response('down', 500));
      final c = client(inner);
      await expectLater(
        c.get(_path, freshWindow: Duration.zero),
        throwsA(isA<CdnException>()),
      );
    });
  });

  group('cache-control parsing', () {
    test('exposes max-age when the origin sends it', () async {
      final inner = MockClient((req) async => http.Response(
            'x',
            200,
            headers: {'cache-control': 'public, max-age=60, s-maxage=3600'},
          ));
      final c = client(inner);
      final payload = await c.get(_path, freshWindow: Duration.zero);
      expect(payload.maxAge, const Duration(seconds: 60));
    });
  });
}
