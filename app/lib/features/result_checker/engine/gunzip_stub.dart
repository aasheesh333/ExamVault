/// Decompresses a gzip payload.
///
/// Declared once and selected at compile time (see `gunzip.dart`). The native
/// build uses `dart:io`'s zlib binding, which is C and fast; the web build uses
/// the pure-Dart implementation from `package:archive`, because `dart:io` is a
/// throwing stub on dart2js.
///
/// This split is not cosmetic: `gzip.decode` on the web throws
/// `Unsupported operation`, so a single implementation would quietly break the
/// result checker in the browser.
library;

import 'dart:typed_data';

/// Platform implementation, resolved by conditional import.
Uint8List gunzipBytes(Uint8List input) =>
    throw UnsupportedError('No gunzip implementation was linked in.');
