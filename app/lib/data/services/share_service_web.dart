import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// Web share-file operations.
///
/// There is no filesystem under dart2js — `dart:io` and `path_provider` are
/// throwing stubs there, which is exactly why this split exists.
/// `XFile.fromData` keeps the PNG in memory and wraps it in a blob URL;
/// share_plus's web implementation hands that to the Web Share API (or falls
/// back to a download). `name:` is honoured by cross_file only on web, so the
/// downloaded file still gets a sensible filename.
///
/// Note: `Share.shareXFiles` — the API the native path historically used — is
/// deprecated in share_plus 13.x; `ShareParams(files:)` via
/// `SharePlus.instance.share` is its replacement on every platform.
Future<ShareResult> sharePngBytes({
  required Uint8List png,
  required String caption,
  required String subject,
  required String fileName,
  Rect? origin,
}) {
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
      text: caption,
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );
}

/// Nothing was ever written to disk, so there is nothing to clean up.
Future<void> clearPngCache() async {}
