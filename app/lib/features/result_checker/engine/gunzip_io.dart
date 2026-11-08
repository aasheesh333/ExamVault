import 'dart:io';
import 'dart:typed_data';

/// Native decompression via zlib.
///
/// `dart:io`'s `gzip` binds straight to the C zlib implementation, which is the
/// fastest option on Android and iOS — and this runs on the critical path of a
/// result-day lookup, so it matters.
Uint8List gunzipBytes(Uint8List input) =>
    Uint8List.fromList(gzip.decode(input));
