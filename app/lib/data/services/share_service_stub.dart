/// Platform share-file operations, resolved by conditional import.
///
/// Declared once and selected at compile time (see `share_service.dart`). The
/// native build uses `dart:io` (temp dir + `File`), the web build uses
/// `XFile.fromData` — `dart:io` and `path_provider` do not exist under
/// dart2js, so a single implementation would break `flutter build web`.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// Platform implementation, resolved by conditional import.
Future<ShareResult> sharePngBytes({
  required Uint8List png,
  required String caption,
  required String subject,
  required String fileName,
  Rect? origin,
}) => throw UnsupportedError('No share-file implementation was linked in.');

/// Platform implementation, resolved by conditional import.
Future<void> clearPngCache() =>
    throw UnsupportedError('No share-file implementation was linked in.');
