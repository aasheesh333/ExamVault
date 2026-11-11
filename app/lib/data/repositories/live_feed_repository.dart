import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/live_update.dart';
import '../models/live_feed_dto.dart';
import '../remote/cdn_client.dart';
import '../services/app_logger.dart';

/// Where a snapshot came from. The UI shows this honestly instead of pretending
/// stale data is live — trust is the whole product.
enum FeedSource {
  network,
  cache,

  /// Nothing stored and nothing fetched — the radar is genuinely empty.
  none;

  bool get isLive => this == FeedSource.network;
}

class LiveFeedSnapshot {
  const LiveFeedSnapshot({
    required this.feed,
    required this.source,
    required this.fetchedAt,
    this.error,
  });

  final LiveFeed feed;
  final FeedSource source;
  final DateTime fetchedAt;
  final String? error;

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > const Duration(minutes: 5);

  LiveFeedSnapshot copyWith({
    LiveFeed? feed,
    FeedSource? source,
    DateTime? fetchedAt,
    String? error,
  }) => LiveFeedSnapshot(
    feed: feed ?? this.feed,
    source: source ?? this.source,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    error: error ?? this.error,
  );
}

/// The radar.
///
/// Read order on every cold start:
///   1. Hive (synchronous, sub-5 ms)  -> paint immediately
///   2. CDN (fresh if < 60 s, else conditional GET)
///   3. bundled seed                  -> never show an empty screen to a new user
class LiveFeedRepository {
  LiveFeedRepository({required CdnClient cdn, required Box<dynamic> cache})
    : _cdn = cdn,
      _cache = cache;

  final CdnClient _cdn;
  final Box<dynamic> _cache;

  LiveFeedSnapshot? _last;

  /// Instant, network-free read for the first frame.
  LiveFeedSnapshot? readCached() {
    if (_last != null) return _last;

    final stored = LiveFeedStore.fromDynamic(_cache.get(LiveFeedStore.key));
    if (stored == null || stored.isEmpty) return null;

    _last = LiveFeedSnapshot(
      feed: stored,
      source: FeedSource.cache,
      fetchedAt: stored.generatedAt ?? DateTime.now(),
    );
    return _last;
  }

  /// An explicit "we have no data" snapshot.
  ///
  /// This used to return a hand-written demo feed, which meant a device with no
  /// network and no cache displayed four confident, entirely invented exam
  /// updates — including "RESULT OUT" for exams that had not been published. An
  /// empty feed with a clear label is the only honest answer.
  LiveFeedSnapshot emptySnapshot() => LiveFeedSnapshot(
    feed: LiveFeed.empty,
    source: FeedSource.none,
    fetchedAt: DateTime.now(),
  );

  Future<LiveFeedSnapshot> refresh({bool force = false}) async {
    try {
      final payload = await _cdn.get(
        AppConfig.liveFeedPath,
        freshWindow: AppConfig.feedFreshWindow,
        bypassCache: force,
      );

      // utf8.decode, not String.fromCharCodes. The latter maps each byte to a
      // code point, so every multi-byte sequence arrives mangled: the middle dot
      // in "Direct PDF · 18.4 MB" (U+00B7) rendered as "Â·" on screen.
      final feed = LiveFeedDto.parse(
        utf8.decode(payload.bytes, allowMalformed: true),
      );

      if (!payload.fromCache) {
        await _cache.put(LiveFeedStore.key, LiveFeedStore.toJson(feed));
      }

      final snapshot = LiveFeedSnapshot(
        feed: feed,
        source: payload.fromCache ? FeedSource.cache : FeedSource.network,
        fetchedAt: payload.fetchedAt,
      );
      _last = snapshot;
      return snapshot;
    } on CdnException catch (e) {
      AppLogger.w('feed', 'refresh failed: ${e.message}');
      final cached = readCached();
      if (cached != null) {
        return cached.copyWith(error: e.message);
      }
      // Fresh install + no network: seed, but say so.
      return emptySnapshot().copyWith(error: e.message);
    } catch (e) {
      AppLogger.w('feed', 'refresh failed: $e');
      final cached = readCached();
      // Attach the failure here too. The realistic trigger is a malformed edge
      // document: CdnClient has already cached those bytes as fresh, so every
      // refresh inside the window re-parses the same garbage. Returning a bare
      // snapshot with error == null made that hard failure indistinguishable
      // from a genuinely empty radar — a confident "no updates" on result day.
      return (cached ?? emptySnapshot()).copyWith(
        error: 'The live feed could not be read. Pull to retry.',
      );
    }
  }

  Future<void> clear() async {
    _last = null;
    await _cache.delete(LiveFeedStore.key);
  }
}
