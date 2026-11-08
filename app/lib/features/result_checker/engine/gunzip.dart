/// Decompresses a gzip payload, choosing the implementation at compile time.
///
/// Native builds link `gunzip_io.dart` (zlib via `dart:io`), web builds link
/// `gunzip_web.dart` (`package:archive`). `dart:io`'s codec is a throwing stub
/// under dart2js, so a single implementation would silently break the result
/// checker in a browser.
library;

export 'gunzip_stub.dart'
    if (dart.library.io) 'gunzip_io.dart'
    if (dart.library.js_interop) 'gunzip_web.dart';
