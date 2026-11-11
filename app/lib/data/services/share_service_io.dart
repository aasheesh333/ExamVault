import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native share-file operations.
///
/// The PNG is written to the app's **cache** directory, not documents: on
/// Android the cache is auto-pruned, so a viral card shared 40 times does not
/// quietly accumulate 40 × 2 MB of storage the user never asked for.
Future<ShareResult> sharePngBytes({
  required Uint8List png,
  required String caption,
  required String subject,
  required String fileName,
  Rect? origin,
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

/// Deletes the PNGs this service wrote into the temp dir. Throws on I/O
/// failure; the caller (`ShareService.clearCache`) treats cleanup as
/// best-effort.
Future<void> clearPngCache() async {
  final dir = await getTemporaryDirectory();
  if (!await dir.exists()) return;
  await for (final entity in dir.list()) {
    if (entity is File && entity.path.endsWith('.png')) {
      await entity.delete();
    }
  }
}
