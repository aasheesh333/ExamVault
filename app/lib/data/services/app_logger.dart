import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Namespaced logger.
///
/// Kept deliberately dumb: `dart:developer` is stripped from release output when
/// the tree-shaker sees the tag unused, and every call is gated on [kDebugMode]
/// so nothing is formatted in release builds.
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
