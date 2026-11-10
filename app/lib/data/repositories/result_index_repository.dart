import 'dart:typed_data';

import '../../core/config/app_config.dart';
import '../remote/cdn_client.dart';

/// Where the index bytes came from.
enum IndexSource {
  /// Real object from the Cloudflare edge.
  edge,

  /// Previously downloaded, still within the freshness window.
  cache,

  /// The index has **not been published** (HTTP 404) or could not be fetched.
  ///
  /// There is deliberately no "demo"/"mock" member. An earlier revision generated
  /// a synthetic index here — one that contained the requesting user's own roll
  /// number — and the UI then reported "SELECTED IN MERIT LIST" with an invented
  /// merit rank. Fabricating an exam outcome is unacceptable, so the type system
  /// no longer has a way to express it.
  unavailable;

  bool get isReal => this == IndexSource.edge || this == IndexSource.cache;

  bool get hasData => this != IndexSource.unavailable;

  String get label => switch (this) {
    IndexSource.edge => 'Live index',
    IndexSource.cache => 'Cached index',
    IndexSource.unavailable => 'Not published',
  };
}

/// A downloaded index, or an explicit statement that there is none.
class IndexBundle {
  const IndexBundle({
    required this.bytes,
    required this.source,
    required this.fetchedAt,
    this.etag,
    this.reason,
  });

  /// An empty bundle. [bytes] is empty by construction so a caller cannot
  /// accidentally search it.
  factory IndexBundle.unavailable([String? reason]) => IndexBundle(
    bytes: Uint8List(0),
    source: IndexSource.unavailable,
    fetchedAt: DateTime.now(),
    reason: reason,
  );

  final Uint8List bytes;
  final IndexSource source;
  final DateTime fetchedAt;
  final String? etag;

  /// Human-readable explanation when [source] is [IndexSource.unavailable].
  final String? reason;

  bool get hasData => bytes.isNotEmpty && source != IndexSource.unavailable;
}

/// Downloads roll-number indexes.
///
/// The object is a gzip archive (`application/gzip`), **not** a
/// `Content-Encoding: gzip` response — that distinction stops the socket layer
/// from decompressing it twice and handing the isolate garbage.
class ResultIndexRepository {
  ResultIndexRepository({required CdnClient cdn}) : _cdn = cdn;

  final CdnClient _cdn;

  /// examId -> bundle, so re-tapping "Check" never re-downloads.
  final Map<String, IndexBundle> _memo = {};

  Future<IndexBundle> load({
    required String examId,
    String? version,
    bool force = false,
  }) async {
    // The memo key includes the version: a republished list must not be served
    // from a cache keyed only by exam id.
    final memoKey = version == null ? examId : '$examId@$version';
    if (!force) {
      final memo = _memo[memoKey];
      // A previously-failed attempt is cached too — at 09:11 the object is
      // missing for everyone, and hammering the edge every tap helps nobody.
      if (memo != null) return memo;
    }

    try {
      final payload = await _cdn.get(
        AppConfig.rollIndexPath(examId, version: version),
        freshWindow: AppConfig.rollIndexFreshWindow,
        bypassCache: force,
      );

      final bundle = IndexBundle(
        bytes: payload.bytes,
        source: payload.fromCache ? IndexSource.cache : IndexSource.edge,
        fetchedAt: payload.fetchedAt,
        etag: payload.etag,
      );
      _memo[memoKey] = bundle;
      return bundle;
    } on CdnException catch (e) {
      final reason = e.statusCode == 404
          ? 'The result for this exam has not been published yet.'
          : 'Could not reach the result index. Check your connection.';
      final bundle = IndexBundle.unavailable(reason);
      _memo[memoKey] = bundle;
      return bundle;
    } catch (_) {
      final bundle = IndexBundle.unavailable(
        'Could not read the result index. Check your connection.',
      );
      _memo[memoKey] = bundle;
      return bundle;
    }
  }

  Future<Uint8List> pdfBytes(String examId) async {
    final payload = await _cdn.get(
      AppConfig.resultPdfPath(examId),
      freshWindow: const Duration(days: 1),
    );
    return payload.bytes;
  }

  /// Direct edge URL for the result PDF of [examId].
  String pdfUrl(String examId) =>
      '${AppConfig.cdnBase}${AppConfig.resultPdfPath(examId)}';

  /// Public web fallback for an exam, or null when no web base is configured.
  ///
  /// Returning null keeps the app from printing a link to a domain it does not
  /// own — the share card used to hardcode `examvault.in`, which is not ours.
  String? shareUrl(String examId) {
    final base = AppConfig.webBase.trim();
    if (base.isEmpty) return null;
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme) return null;
    return '$base/r/$examId';
  }

  void clearMemo() => _memo.clear();
}
