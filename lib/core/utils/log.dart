// lib/core/utils/log.dart
//
// Debug-only logging wrapper. All output is suppressed in release builds.
// Replace every bare `print()` call with `log()` from this file.

import 'package:flutter/foundation.dart';

/// Prints [message] only in debug mode. Silent in release builds.
void log(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
