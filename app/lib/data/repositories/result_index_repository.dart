import 'dart:typed_data';

import '../../core/config/app_config.dart';
import '../remote/cdn_client.dart';
import '../seed/demo_seed.dart';
import '../services/app_logger.dart';

/// Where the index bytes came from.
enum IndexSource {
  /// Real object from the Cloudflare edge.
  edge,

  /// Previously downloaded, still within the freshness window.
  cache,

  /// Locally generated, because the object is not published yet. This is what
  /// makes the checker testable on a fresh install and on exam day *before* the
  /// PDF drops.
  demo;

  bool get isReal => this != IndexSource.demo;

  String get label => switch (this) {
        IndexSource.edge => 'Edge CDN',
        IndexSource.cache => 'Cached index',
        IndexSource.demo => 'Demo index',
      };
}

class IndexBundle {
  const IndexBundle({
    required this.bytes,
    required this.source,
    required this.fetchedAt,
    this.etag,
  });

  final Uint8List bytes;
  final IndexSource source;
  final DateTime fetchedAt;
  final String? etag;

}

/// Downloads roll-number indexes.
///
/// The object is a gzip archive (`application/gzip`), **not** a
/// `Content-Encoding: gzip` response — that distinction is what stops the socket
/// layer from decompressing it twice and handing the isolate garbage.
class ResultIndexRepository {
  ResultIndexRepository({required CdnClient cdn}) : _cdn = cdn;

  final CdnClient _cdn;

  /// examId -> bundle, so re-tapping "Check" never re-downloads.
  final Map<String, IndexBundle> _memo = {};

  Future<IndexBundle> load({
    required String examId,
    String? userRollForDemo,
    bool force = false,
  }) async {
    if (!force) {
      final memo = _memo[examId];
      if (memo != null) return memo;
    }

    try {
      final payload = await _cdn.get(
        AppConfig.rollIndexPath(examId),
        freshWindow: AppConfig.rollIndexFreshWindow,
        bypassCache: force,
      );

      final bundle = IndexBundle(
        bytes: payload.bytes,
        source: payload.fromCache ? IndexSource.cache : IndexSource.edge,
        fetchedAt: payload.fetchedAt,
        etag: payload.etag,
      );
      _memo[examId] = bundle;
      return bundle;
    } on CdnException catch (e) {
      // 404 means "not published yet" — that is a normal state at 09:11, not an
      // error. Anything else is worth logging.
      if (e.statusCode != 404) {
        AppLogger.w('index', 'edge miss for $examId: ${e.message}');
      }
      final demo = IndexBundle(
        bytes: await MockRollIndex.generate(
          examId: examId,
          includeRoll: userRollForDemo,
        ),
        source: IndexSource.demo,
        fetchedAt: DateTime.now(),
      );
      _memo[examId] = demo;
      return demo;
    } catch (e) {
      AppLogger.w('index', 'unexpected failure for $examId: $e');
      final demo = IndexBundle(
        bytes: await MockRollIndex.generate(
          examId: examId,
          includeRoll: userRollForDemo,
        ),
        source: IndexSource.demo,
        fetchedAt: DateTime.now(),
      );
      _memo[examId] = demo;
      return demo;
    }
  }

  Future<Uint8List> pdfBytes(String examId) async {
    final payload = await _cdn.get(
      AppConfig.resultPdfPath(examId),
      freshWindow: const Duration(days: 1),
    );
    return payload.bytes;
  }

  String pdfUrl(String examId) => '${AppConfig.cdnBase}${AppConfig.resultPdfPath(examId)}';

  String shareUrl(String examId) => '${AppConfig.webBase}/r/$examId';

  void clearMemo() => _memo.clear();
}
