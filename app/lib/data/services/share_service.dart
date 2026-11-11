import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';

// Native builds link `share_service_io.dart` (temp dir + `dart:io` File), web
// builds link `share_service_web.dart` (`XFile.fromData`, no filesystem) —
// same compile-time selection pattern as `result_checker/engine/gunzip.dart`.
// The dart:io/path_provider imports this file used to carry unconditionally
// are throwing stubs under dart2js, so they broke `flutter build web` before
// a single frame could render.
import 'share_service_stub.dart'
    if (dart.library.io) 'share_service_io.dart'
    if (dart.library.js_interop) 'share_service_web.dart'
    as impl;

/// Turns a `RepaintBoundary` into a PNG and hands it to the system share sheet.
///
/// The rasterisation and text-share halves are platform-agnostic; only the
/// PNG handoff touches the filesystem, and that part lives behind the
/// conditional import above.
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
  ///
  /// Throws when the platform refuses the handoff; callers must not silently
  /// discard an already-captured PNG — fall back to [shareText].
  Future<ShareResult> shareCardImage({
    required Uint8List png,
    required String caption,
    required String subject,
    Rect? origin,
    String fileName = 'examvault_result.png',
  }) => impl.sharePngBytes(
    png: png,
    caption: caption,
    subject: subject,
    fileName: fileName,
    origin: origin,
  );

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
  ///
  /// A no-op on web (nothing is written to disk there); never throws, so it is
  /// safe to call from a `finally`.
  Future<void> clearCache() async {
    try {
      await impl.clearPngCache();
    } catch (e) {
      if (kDebugMode) AppLogger.w('share', 'cache cleanup failed: $e');
    }
  }
}
