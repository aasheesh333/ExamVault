import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../services/app_logger.dart';

/// A byte payload from the edge plus the metadata needed to judge staleness.
class CdnPayload {
  const CdnPayload({
    required this.bytes,
    required this.fetchedAt,
    required this.fromCache,
    this.etag,
    this.contentType,
    this.maxAge,
  });

  final Uint8List bytes;
  final DateTime fetchedAt;
  final bool fromCache;
  final String? etag;
  final String? contentType;

  /// `max-age` echoed by the origin, when present.
  final Duration? maxAge;

  Duration age([DateTime? now]) =>
      (now ?? DateTime.now()).difference(fetchedAt);

  bool isFresh(Duration window, [DateTime? now]) => age(now) <= window;
}

class CdnException implements Exception {
  const CdnException(this.message, {this.statusCode, this.isTransient = true});

  final String message;
  final int? statusCode;
  final bool isTransient;

  @override
  String toString() => 'CdnException($statusCode): $message';
}

/// Edge-first HTTP client built for a thundering herd.
///
/// Four properties matter on result day and each is implemented here:
///
/// 1. **Single-flight.** N widgets asking for the same object in the same frame
///    produce exactly one socket. Without it, a tab-switch storm on a phone turns
///    into a request storm on a PoP.
/// 2. **Conditional GET.** The stored `ETag` goes back as `If-None-Match`, so a
///    refresh costs ~200 bytes instead of 150 KB. Egress is the only real cost
///    at this scale.
/// 3. **Retry with full jitter.** Clients spread over the backoff window instead
///    of retrying in lockstep, so a PoP hiccup never becomes a stampede.
/// 4. **Stale-while-offline.** A cold boot with no network still paints the last
///    good payload instead of an error screen.
class CdnClient {
  CdnClient({
    required Box<dynamic> cache,
    http.Client? client,
    Random? random,
    this.baseUrl = AppConfig.cdnBase,
  }) : _cache = cache,
       _http = client ?? http.Client(),
       _random = random ?? Random.secure();

  final Box<dynamic> _cache;
  final http.Client _http;
  final Random _random;
  final String baseUrl;

  /// url -> in-flight request. The core of the single-flight guarantee.
  final Map<String, Future<CdnPayload>> _inflight = {};

  /// Guards against a slow first request overwriting a newer one.
  final Map<String, int> _generation = {};

  static const _kBytes = 'b';
  static const _kAt = 't';
  static const _kEtag = 'e';
  static const _kType = 'c';

  int get inflightCount => _inflight.length;

  /// Fetches [path], preferring a fresh cache entry.
  ///
  /// When the entry is older than [freshWindow] a refresh is attempted; if that
  /// fails and a cached copy exists, the cached copy is returned with
  /// `fromCache: true` so the caller can show a "cached" affordance.
  Future<CdnPayload> get(
    String path, {
    required Duration freshWindow,
    bool bypassCache = false,
  }) async {
    final url = path.startsWith('http') ? path : '$baseUrl$path';
    final cached = _readCache(url);

    if (!bypassCache && cached != null && cached.isFresh(freshWindow)) {
      return cached;
    }

    final existing = _inflight[url];
    if (existing != null) {
      AppLogger.d('cdn', 'coalesced in-flight request for $path');
      return existing;
    }

    // NOTE: the callback must not *return* the removed value — `Map.remove`
    // hands back the very future being completed, and `whenComplete` awaits a
    // returned future, which deadlocks the request forever.
    final future = _fetchWithRetry(url, cached).whenComplete(() {
      _inflight.remove(url);
    });
    _inflight[url] = future;
    return future;
  }

  Future<CdnPayload> _fetchWithRetry(String url, CdnPayload? cached) async {
    final generation = (_generation[url] ?? 0) + 1;
    _generation[url] = generation;

    CdnException? lastError;

    for (var attempt = 1; attempt <= AppConfig.maxAttempts; attempt++) {
      try {
        final payload = await _attempt(url, cached);
        if (_generation[url] == generation) return payload;
        return _readCache(url) ?? payload;
      } on CdnException catch (e) {
        lastError = e;
        if (!e.isTransient || attempt == AppConfig.maxAttempts) break;

        // Exponential backoff with *full* jitter: sleep in [0, base * 2^n).
        final ceilingMs = 400 * (1 << (attempt - 1));
        final delay = Duration(milliseconds: _random.nextInt(ceilingMs + 1));
        AppLogger.d(
          'cdn',
          'retry $attempt/${AppConfig.maxAttempts} in ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      }
    }

    // A definitive answer from the edge is not a transport failure. The loop
    // breaks early on any non-transient error (404 "not published", unexpected
    // status, download-budget violation), and this fallback used to run for
    // those too — so a genuine 404 was answered with last month's cached
    // index, and the result checker confidently searched stale bytes for an
    // exam whose list had been pulled. Only *transport-exhausted* paths may
    // serve stale data.
    if (lastError != null && !lastError.isTransient) throw lastError;

    // Network exhausted: a 72-hour-old feed beats an error screen on result day.
    if (cached != null) {
      AppLogger.w(
        'cdn',
        'serving stale cache for $url (${lastError?.message})',
      );
      return CdnPayload(
        bytes: cached.bytes,
        fetchedAt: cached.fetchedAt,
        fromCache: true,
        etag: cached.etag,
        contentType: cached.contentType,
      );
    }

    throw lastError ?? const CdnException('Unknown network failure');
  }

  Future<CdnPayload> _attempt(String url, CdnPayload? cached) async {
    final headers = <String, String>{
      'Accept': '*/*',
      // The roll index is a gzip *object*, not a gzip transfer encoding. Asking
      // for identity keeps the byte stream exactly as published.
      'Accept-Encoding': 'identity',
    };
    if (cached?.etag != null) headers['If-None-Match'] = cached!.etag!;

    // Reuse the pooled client: HTTP keep-alive to the same Cloudflare PoP saves a
    // TLS handshake (~120 ms on 3G) on every single request. The owner closes it
    // in `dispose()`, and `streamed.stream` is drained or cancelled below so no
    // socket is leaked on the error paths.
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(headers);

      final pending = _http.send(request);
      late final http.StreamedResponse streamed;
      try {
        streamed = await pending.timeout(AppConfig.connectTimeout);
      } on TimeoutException {
        // Future.timeout abandons but cannot cancel. Drain the response
        // whenever it does arrive so the keep-alive socket returns to the pool
        // instead of leaking — on a congested result-day PoP each fetch could
        // strand up to maxAttempts open requests per URL.
        unawaited(
          pending.then(
            (lateResponse) => lateResponse.stream.drain<void>(),
            onError: (Object _) {},
          ),
        );
        throw const CdnException('Request timed out');
      }

      // Every early exit below must drain the body. An abandoned
      // StreamedResponse strands its keep-alive socket — the pooled client is
      // never closed between polls, so a 304/404/429/5xx on every tick leaked
      // one socket per request, exactly the failure the timeout path above
      // already guards against. Draining returns the socket to the pool.
      void drainBody() =>
          unawaited(streamed.stream.drain<void>().catchError((Object _) {}));

      if (streamed.statusCode == 304 && cached != null) {
        drainBody();
        _writeCache(
          url,
          cached.bytes,
          DateTime.now(),
          cached.etag,
          cached.contentType,
        );
        return CdnPayload(
          bytes: cached.bytes,
          fetchedAt: DateTime.now(),
          fromCache: true,
          etag: cached.etag,
          contentType: cached.contentType,
        );
      }

      if (streamed.statusCode == 404) {
        drainBody();
        throw const CdnException(
          'Not published yet',
          statusCode: 404,
          isTransient: false,
        );
      }

      if (streamed.statusCode == 429 || streamed.statusCode >= 500) {
        drainBody();
        throw CdnException(
          'Edge returned ${streamed.statusCode}',
          statusCode: streamed.statusCode,
        );
      }

      if (streamed.statusCode != 200) {
        drainBody();
        throw CdnException(
          'Unexpected status ${streamed.statusCode}',
          statusCode: streamed.statusCode,
          isTransient: false,
        );
      }

      final declared = streamed.contentLength;
      if (declared != null && declared > AppConfig.maxDownloadBytes) {
        drainBody();
        throw const CdnException(
          'Object exceeds the download budget',
          isTransient: false,
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(
        AppConfig.receiveTimeout,
      )) {
        builder.add(chunk);
        if (builder.length > AppConfig.maxDownloadBytes) {
          throw const CdnException(
            'Object exceeds the download budget',
            isTransient: false,
          );
        }
      }

      final bytes = builder.takeBytes();
      final etag = streamed.headers['etag'];
      final type = streamed.headers['content-type'];

      // Validate before caching. Any 200 body used to be written as
      // authoritative — a captive-portal HTML page or proxy interstitial then
      // poisoned the roll index for the full 12-hour fresh window, and every
      // lookup reported "index is malformed" with no self-healing path.
      // Gzip objects must start with the 0x1f 0x8b magic.
      if (url.contains('.gz') &&
          (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b)) {
        throw const CdnException(
          'Object is not the gzip document that was requested',
        );
      }

      _writeCache(url, bytes, DateTime.now(), etag, type);

      return CdnPayload(
        bytes: bytes,
        fetchedAt: DateTime.now(),
        fromCache: false,
        etag: etag,
        contentType: type,
        maxAge: _parseMaxAge(streamed.headers['cache-control']),
      );
    } on TimeoutException {
      throw const CdnException('Request timed out');
    } on CdnException {
      rethrow;
    } catch (e) {
      throw CdnException('Network error: $e');
    }
  }

  static Duration? _parseMaxAge(String? cacheControl) {
    if (cacheControl == null) return null;
    for (final part in cacheControl.split(',')) {
      final trimmed = part.trim();
      if (!trimmed.startsWith('max-age=')) continue;
      final seconds = int.tryParse(trimmed.substring(8));
      if (seconds != null) return Duration(seconds: seconds);
    }
    return null;
  }

  CdnPayload? _readCache(String url) {
    final raw = _cache.get(url);
    if (raw is! Map) return null;

    final bytes = raw[_kBytes];
    final at = raw[_kAt];
    if (bytes is! Uint8List || at is! int) return null;

    return CdnPayload(
      bytes: bytes,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(at),
      fromCache: true,
      etag: raw[_kEtag] as String?,
      contentType: raw[_kType] as String?,
    );
  }

  /// Cap on the Hive http box.
  ///
  /// Roll indexes are content-addressed: every republished version lands at a
  /// NEW url (~12 MB each) and nothing ever overwrote or evicted the previous
  /// one, so the cache grew without bound for the life of the install. 24
  /// entries covers several republish generations of every tracked exam —
  /// far more than any fresh window needs.
  static const _maxCacheEntries = 24;

  void _writeCache(
    String url,
    Uint8List bytes,
    DateTime at,
    String? etag,
    String? type,
  ) {
    // Fire-and-forget: a cache write must never block the UI or throw.
    unawaited(
      _cache
          .put(url, {
            _kBytes: bytes,
            _kAt: at.millisecondsSinceEpoch,
            _kEtag: etag,
            _kType: type,
          })
          .catchError((Object e) {
            AppLogger.w('cdn', 'cache write failed: $e');
          })
          .then((_) => _pruneCache())
          .catchError((Object e) {
            AppLogger.w('cdn', 'cache prune failed: $e');
          }),
    );
  }

  /// Drops the oldest entries (by the fetch timestamp stored with each value)
  /// once the box grows past [_maxCacheEntries]. Runs after the put completes,
  /// so the entry just written is included in the count and can never be the
  /// one evicted for being "old".
  Future<void> _pruneCache() async {
    // Only entries this client wrote are eviction candidates. The box is
    // shared with LiveFeedStore's 'feed' snapshot, which carries no 't'
    // timestamp and must survive pruning — the radar's instant cold-boot
    // paint reads it.
    final fetchedAt = <Object?, int>{};
    for (final key in _cache.keys) {
      final raw = _cache.get(key);
      final at = raw is Map ? raw[_kAt] : null;
      if (at is int) fetchedAt[key] = at;
    }
    final excess = fetchedAt.length - _maxCacheEntries;
    if (excess <= 0) return;

    final oldest = fetchedAt.keys.toList()
      ..sort((a, b) => fetchedAt[a]!.compareTo(fetchedAt[b]!));
    await _cache.deleteAll(oldest.take(excess));
  }

  /// Drops every cached payload and forgets in-flight reads.
  ///
  /// Deliberately kept although nothing calls it yet: the Settings "Delete all
  /// data" action must clear the CDN cache as well as the vault, and this is the
  /// only path that does. Removing it would leave that flow with no way to
  /// honour the promise it makes.
  Future<void> evictAll() async {
    _inflight.clear();
    _generation.clear();
    await _cache.clear();
  }

  void dispose() => _http.close();
}
