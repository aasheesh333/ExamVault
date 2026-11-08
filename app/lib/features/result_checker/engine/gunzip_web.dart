import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;

/// Web decompression.
///
/// `dart:io` is a throwing stub under dart2js, so the browser cannot use zlib.
/// `package:archive` is pure Dart and produces the same bytes. It is slower, but
/// the web build exists for demos and smoke tests — the shipped app is native,
/// where `gunzip_io.dart` is linked instead.
Uint8List gunzipBytes(Uint8List input) {
  final decoded = const arc.GZipDecoder().decodeBytes(input);
  return Uint8List.fromList(decoded);
}
