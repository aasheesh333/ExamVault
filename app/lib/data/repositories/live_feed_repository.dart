import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/live_update.dart';
import '../models/live_feed_dto.dart';
import '../remote/cdn_client.dart';
import '../seed/demo_seed.dart';
import '../services/app_logger.dart';

/// Where a snapshot came from. The UI shows this honestly instead of pretending
/// stale data is live — trust is the whole product.
enum FeedSource {
  network,
  cache,
  seed;

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

  /// The seed used only when nothing at all has ever been stored.
  LiveFeedSnapshot seedSnapshot() {
    final seed = DemoSeed.liveFeed();
    return LiveFeedSnapshot(
      feed: seed,
      source: FeedSource.seed,
      fetchedAt: DateTime.now(),
    );
  }

  Future<LiveFeedSnapshot> refresh({bool force = false}) async {
    try {
      final payload = await _cdn.get(
        AppConfig.liveFeedPath,
        freshWindow: AppConfig.feedFreshWindow,
        bypassCache: force,
      );

      final feed = LiveFeedDto.parse(String.fromCharCodes(payload.bytes));

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
      return seedSnapshot().copyWith(error: e.message);
    } catch (e) {
      AppLogger.w('feed', 'refresh failed: $e');
      final cached = readCached();
      return cached ?? seedSnapshot();
    }
  }

  Future<void> clear() async {
    _last = null;
    await _cache.delete(LiveFeedStore.key);
  }
}
