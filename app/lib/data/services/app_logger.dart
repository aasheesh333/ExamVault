import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Namespaced logger.
///
/// What actually ships, stated precisely because the previous doc here was
/// wrong (it claimed `dart:developer` is tree-shaken out of release builds —
/// it cannot be, since [e] keeps the library reachable from `main.dart`'s
/// crash guards):
///
/// * [d] and [w] are gated on [kDebugMode]. In a release build the
///   `developer.log` call is never made. (Callers still build their message
///   strings — Dart evaluates arguments at the call site — but nothing is
///   logged or formatted here.)
/// * [e] is deliberately NOT gated: `main.dart`'s crash guards
///   (`FlutterError.onError`, `PlatformDispatcher.onError`) route every
///   uncaught error here, in release included, and a guard that goes quiet in
///   release would blind the only diagnostics the app has.
///
/// Where the output goes: `developer.log` is an `external` function whose only
/// sink is the Dart VM service (the DevTools logging view / `flutter logs`).
/// A product-mode AOT build — which is what `flutter build --release` ships —
/// has no VM service, so the call is inert: verified empirically with
/// `dart compile exe` (same product mode), a release binary calling `log()`
/// emits nothing on any stream and performs no I/O. "Inert sink" is the honest
/// claim, not "stripped": the call and its already-formatted arguments still
/// execute, they just go nowhere.
///
/// Nothing here is ever written to disk or transmitted, so the privacy
/// policy's "no crash reports" holds in release builds.
abstract final class AppLogger {
  static void d(String scope, String message) {
    if (kDebugMode) developer.log(message, name: 'EV/$scope');
  }

  static void w(String scope, String message) {
    if (kDebugMode) developer.log(message, name: 'EV/$scope', level: 900);
  }

  static void e(
    String scope,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    developer.log(
      message,
      name: 'EV/$scope',
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }
}
