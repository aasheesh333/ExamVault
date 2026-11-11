import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:examvault/core/config/app_config.dart';
import 'package:examvault/data/models/live_feed_dto.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/live_feed_repository.dart';
import 'package:examvault/data/repositories/result_index_repository.dart';
import 'package:examvault/domain/entities/exam_category.dart';
import 'package:examvault/domain/entities/live_update.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Regression tests for state that leaked across exams, time and bad payloads.
///
/// Each case maps to a defect that was visible on a phone: expired radar rows
/// stayed green for months, one malformed JSON field blanked the feed, and a
/// result checked for exam A stayed on screen under exam B.
void main() {
  late Directory dir;
  late Box<dynamic> cacheBox;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ev_state_regression');
    Hive.init(dir.path);
  });

  setUp(() async {
    cacheBox = await Hive.openBox<dynamic>(
      'state_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  });

  CdnClient cdnReturning(http.Response Function() respond) => CdnClient(
    cache: cacheBox,
    client: MockClient((_) async => respond()),
    baseUrl: 'https://cdn.test',
  );

  group('expired radar rows', () {
    LiveUpdate row(String examId, DateTime now, {DateTime? expiresAt}) =>
        LiveUpdate(
          examId: examId,
          category: ExamCategory.ssc,
          examName: 'Exam $examId',
          contextLine: 'Direct PDF',
          status: UpdateStatus.resultOut,
          publishedAt: now.subtract(const Duration(hours: 1)),
          expiresAt: expiresAt,
        );

    test('filteredUpdatesProvider drops rows past expires_at', () async {
      final now = DateTime.now();
      final feed = LiveFeed(
        generatedAt: now,
        updates: [
          row('expired', now, expiresAt: now.subtract(const Duration(days: 1))),
          row('live', now, expiresAt: now.add(const Duration(days: 1))),
        ],
        revision: 1,
      );

      final container = ProviderContainer(
        overrides: [
          liveFeedProvider.overrideWith(
            () => _StaticLiveFeed(
              LiveFeedSnapshot(
                feed: feed,
                source: FeedSource.network,
                fetchedAt: now,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(liveFeedProvider.future);

      final visible = container.read(filteredUpdatesProvider);
      expect(visible.map((u) => u.examId), ['live']);
    });

    test('includeExpired is available for a future archive view', () {
      final now = DateTime.now();
      final feed = LiveFeed(
        generatedAt: now,
        updates: [
          row('expired', now, expiresAt: now.subtract(const Duration(days: 1))),
          row('live', now, expiresAt: now.add(const Duration(days: 1))),
        ],
        revision: 1,
      );

      expect(filterUpdates(feed, null).map((u) => u.examId), ['live']);
      expect(filterUpdates(feed, null, includeExpired: true).length, 2);
    });
  });

  group('feed parsing is total', () {
    test('a non-string field is coerced or skipped, never fatal', () {
      final doc = {
        'generated_at': '2026-11-09T10:00:00Z',
        'revision': 1,
        'updates': [
          {
            'exam_id': 'good',
            'category': 'ssc',
            'exam_name': 'Good row',
            'context': 'Direct PDF',
            'status': 'result_out',
            'published_at': '2026-11-09T09:00:00Z',
          },
          {
            'exam_id': 'bad_category',
            'category': 42,
            'exam_name': 'Bad row',
            'status': 'result_out',
            'published_at': '2026-11-09T09:00:00Z',
          },
          {
            'exam_id': 'bad_context',
            'category': 'upsc',
            'exam_name': 'Bad context',
            'context': {'nested': true},
            'status': 'result_out',
            'published_at': '2026-11-09T09:00:00Z',
            'index_available': true,
            'index_version': 99,
            'mirror_latency_ms': '__INF__',
          },
        ],
        'sources': [
          {
            'id': 'ssc',
            'label': 'SSC',
            'status': 'ok',
            'rows': 'twelve',
            'note': 42,
          },
        ],
      };

      // jsonEncode cannot emit Infinity, so splice the literal 1e999 in after.
      final body = jsonEncode(doc).replaceAll('"__INF__"', '1e999');
      final feed = LiveFeedDto.parse(body);

      expect(feed.updates.map((u) => u.examId), ['good', 'bad_context']);
      final badContext = feed.updates.last;
      expect(badContext.contextLine, 'Tap for details');
      expect(badContext.indexVersion, isNull);
      expect(badContext.mirrorLatencyMs, isNull);
      expect(feed.sources.single.note, isNull);
      expect(feed.sources.single.rows, 0);
    });

    test('a 200 body without an "updates" array is a parse error', () {
      // A rate-limit object or an error page shaped like JSON used to parse
      // as a VALID EMPTY feed: the repository then overwrote the good Hive
      // snapshot with nothing, and its error-attach catch never fired because
      // parse did not throw. Row-level tolerance stays; the document's shape
      // is not optional.
      expect(
        () => LiveFeedDto.parse(jsonEncode({'status': 'rate-limited'})),
        throwsFormatException,
      );
      expect(
        () => LiveFeedDto.parse(jsonEncode({'updates': 'not-a-list'})),
        throwsFormatException,
      );
      // An explicitly empty array remains a valid — and empty — feed.
      expect(LiveFeedDto.parse(jsonEncode({'updates': []})).updates, isEmpty);
    });
  });

  group('result index retry', () {
    test(
      'a transport failure is not memoised, so the next tap retries',
      () async {
        var failing = true;
        final repo = ResultIndexRepository(
          cdn: CdnClient(
            cache: cacheBox,
            client: MockClient((_) async {
              return failing
                  ? http.Response('boom', 503)
                  // Real gzip bytes: production roll indexes are gzip objects,
                  // and CdnClient now rejects a 200 whose body lacks the gzip
                  // magic before caching it (a captive-portal HTML page used to
                  // poison the cache for the whole fresh window). A plain '[]'
                  // fixture no longer represents a success.
                  : http.Response.bytes(gzip.encode(utf8.encode('[]')), 200);
            }),
            baseUrl: 'https://cdn.test',
          ),
        );

        final first = await repo.load(examId: 'ssc_cgl_tier1_2026');
        expect(first.hasData, isFalse);

        // A cached failure would return without another request; the fix means
        // this call actually reaches the edge and can recover.
        failing = false;
        final second = await repo.load(examId: 'ssc_cgl_tier1_2026');
        expect(second.hasData, isTrue);
      },
    );

    test('a genuine 404 is stable and stays memoised', () async {
      var calls = 0;
      final repo = ResultIndexRepository(
        cdn: CdnClient(
          cache: cacheBox,
          client: MockClient((_) async {
            calls++;
            return http.Response('not published', 404);
          }),
          baseUrl: 'https://cdn.test',
        ),
      );

      await repo.load(examId: 'ssc_cgl_tier1_2026');
      await repo.load(examId: 'ssc_cgl_tier1_2026');

      expect(calls, 1);
    });

    test('a 404 never serves stale cache bytes', () async {
      // Seed a stale cached index straight into the http box, mirroring
      // CdnClient's private entry shape: 'b' bytes, 't' fetchedAt millis,
      // 'e' etag, 'c' contentType. Old enough to be outside the fresh window,
      // so the fetch actually reaches the (404ing) edge.
      final url =
          'https://cdn.test${AppConfig.rollIndexPath('ssc_cgl_tier1_2026')}';
      await cacheBox.put(url, {
        'b': Uint8List.fromList(gzip.encode(utf8.encode('["stale_roll"]'))),
        't': DateTime.now()
            .subtract(const Duration(days: 10))
            .millisecondsSinceEpoch,
        'e': null,
        'c': null,
      });

      final repo = ResultIndexRepository(
        cdn: CdnClient(
          cache: cacheBox,
          client: MockClient((_) async => http.Response('pulled', 404)),
          baseUrl: 'https://cdn.test',
        ),
      );

      // The retry loop breaks on the non-transient 404 and then fell into the
      // transport-failure fallback, answering "not published" with last
      // month's index — the checker confidently searched stale bytes. A
      // definitive 404 must surface as unavailable, not as cached data.
      final bundle = await repo.load(examId: 'ssc_cgl_tier1_2026');
      expect(bundle.hasData, isFalse);
      expect(bundle.source, IndexSource.unavailable);
      expect(bundle.bytes, isEmpty);
    });
  });

  group('result check state', () {
    test('carries the exam id it was produced for', () async {
      final container = ProviderContainer(
        overrides: [
          resultIndexRepositoryProvider.overrideWithValue(
            ResultIndexRepository(
              cdn: cdnReturning(() => http.Response('not published', 404)),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(resultCheckerProvider.notifier)
          .check(examId: 'exam_a', rollNumber: '1234567');

      final state = container.read(resultCheckerProvider);
      expect(state.examId, 'exam_a');
      expect(state.belongsTo('exam_a'), isTrue);
      expect(state.belongsTo('exam_b'), isFalse);
    });

    test('a superseded slow lookup cannot overwrite a newer one', () async {
      final repo = _QueuedIndexRepository(
        cdn: cdnReturning(() => http.Response('', 200)),
      );
      final container = ProviderContainer(
        overrides: [resultIndexRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(resultCheckerProvider.notifier);
      final first = notifier.check(examId: 'exam_a', rollNumber: '1111');
      final second = notifier.check(examId: 'exam_b', rollNumber: '2222');

      // The newer lookup lands first…
      repo.requests[1].complete(IndexBundle.unavailable('exam_b'));
      await second;
      // …and the older one must not repaint the screen with exam_a.
      repo.requests[0].complete(IndexBundle.unavailable('exam_a'));
      await first;

      final state = container.read(resultCheckerProvider);
      expect(state.examId, 'exam_b');
      expect(state.belongsTo('exam_a'), isFalse);
    });
  });
}

class _StaticLiveFeed extends LiveFeedNotifier {
  _StaticLiveFeed(this.snapshot);

  final LiveFeedSnapshot snapshot;

  @override
  Future<LiveFeedSnapshot> build() async => snapshot;
}

class _QueuedIndexRepository extends ResultIndexRepository {
  _QueuedIndexRepository({required super.cdn});

  final List<Completer<IndexBundle>> requests = [];

  @override
  Future<IndexBundle> load({
    required String examId,
    String? version,
    bool force = false,
  }) {
    final completer = Completer<IndexBundle>();
    requests.add(completer);
    return completer.future;
  }
}
