import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';

/// Turns a `RepaintBoundary` into a PNG and hands it to the system share sheet.
///
/// The image is written to the app's **cache** directory, not documents: on
/// Android the cache is auto-pruned, so a viral card shared 40 times does not
/// quietly accumulate 40 × 2 MB of storage the user never asked for.
class ShareService {
  /// Rasterises [key]'s subtree. Returns null when the boundary has not been
  /// laid out yet (a real possibility if the user taps during the first frame).
  Future<Uint8List?> capturePng(
    GlobalKey key, {
    double pixelRatio = 3.0,
  }) async {
    try {
      final context = key.currentContext;
      final ctx = context;
      if (ctx == null) return null;

      final boundary = ctx.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e, st) {
      AppLogger.e('share', 'capture failed', e, st);
      return null;
    }
  }

  /// Shares a PNG plus a caption. WhatsApp reads `text` as the message body and
  /// shows the image as an attachment, which is what makes the card feel native
  /// inside a study group rather than a forwarded file.
  Future<ShareResult> shareCardImage({
    required Uint8List png,
    required String caption,
    required String subject,
    Rect? origin,
    String fileName = 'examvault_result.png',
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);

    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: caption,
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  /// Text-only share — the fallback when capture fails, so the CTA never dies.
  Future<ShareResult> shareText({
    required String caption,
    required String subject,
    Rect? origin,
  }) {
    return SharePlus.instance.share(
      ShareParams(text: caption, subject: subject, sharePositionOrigin: origin),
    );
  }

  /// Best-effort cleanup so the cache never grows unbounded.
  Future<void> clearCache() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.png')) {
          await entity.delete();
        }
      }
    } catch (e) {
      if (kDebugMode) AppLogger.w('share', 'cache cleanup failed: $e');
    }
  }
}
