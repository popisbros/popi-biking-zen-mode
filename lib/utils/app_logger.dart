import 'package:flutter/foundation.dart';

/// Production-ready logging utility
///
/// In DEBUG mode: Prints all logs with emojis and formatting
/// In RELEASE mode: Completely removed by tree-shaking (zero overhead)
///
/// Usage:
/// AppLogger.info('User logged in');
/// AppLogger.debug('Loading POIs', data: {'count': 42});
/// AppLogger.error('Failed to load', error: e);
class AppLogger {
  // Private constructor to prevent instantiation
  AppLogger._();

  /// Log levels
  static const String _infoIcon = 'ℹ️';
  static const String _debugIcon = '🔍';
  static const String _warningIcon = '⚠️';
  static const String _errorIcon = '❌';
  static const String _successIcon = '✅';
  static const String _mapIcon = '🗺️';
  static const String _locationIcon = '📍';
  static const String _firebaseIcon = '🔥';
  static const String _apiIcon = '🌐';

  /// Info log - general information
  static void info(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_infoIcon, tag ?? 'INFO', message, data);
    }
  }

  /// Debug log - detailed debugging information
  static void debug(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_debugIcon, tag ?? 'DEBUG', message, data);
    }
  }

  /// Warning log - potential issues
  static void warning(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_warningIcon, tag ?? 'WARNING', message, data);
    }
  }

  /// Error log - errors and exceptions
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_errorIcon, tag ?? 'ERROR', message, data);
      if (error != null) {
        debugPrint('  ↳ Error: $error');
      }
      if (stackTrace != null) {
        debugPrint('  ↳ Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      }
    }
  }

  /// Success log - successful operations
  static void success(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_successIcon, tag ?? 'SUCCESS', message, data);
    }
  }

  // Domain-specific loggers for better categorization

  /// Map-related logs
  static void map(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_mapIcon, 'MAP', message, data);
    }
  }

  /// Location-related logs
  static void location(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_locationIcon, 'LOCATION', message, data);
    }
  }

  /// Firebase-related logs
  static void firebase(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_firebaseIcon, 'FIREBASE', message, data);
      if (error != null) {
        debugPrint('  ↳ Error: $error');
      }
      if (stackTrace != null) {
        debugPrint('  ↳ Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      }
    }
  }

  /// API/Network-related logs
  static void api(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_apiIcon, 'API', message, data);
      if (error != null) {
        debugPrint('  ↳ Error: $error');
      }
      if (stackTrace != null) {
        debugPrint('  ↳ Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      }
    }
  }

  /// iOS-specific debug logs (maintains compatibility with existing iOS DEBUG logs)
  static void ios(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _log(_debugIcon, 'iOS DEBUG', message, data);
    }
  }

  /// Internal logging method
  static void _log(String icon, String tag, String message, Map<String, dynamic>? data) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    final buffer = StringBuffer();
    buffer.write('$icon [$tag] $message');

    if (data != null && data.isNotEmpty) {
      buffer.write(' | ');
      buffer.write(data.entries.map((e) => '${e.key}: ${e.value}').join(', '));
    }

    debugPrint('[$timestamp] ${buffer.toString()}');
  }

  /// Performance timing utility
  static Stopwatch startTimer(String operation) {
    if (kDebugMode) {
      debug('⏱️ Starting: $operation');
      return Stopwatch()..start();
    }
    return Stopwatch(); // Return dummy stopwatch in release mode
  }

  /// End performance timing
  static void endTimer(Stopwatch stopwatch, String operation) {
    if (kDebugMode) {
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final icon = elapsed < 100 ? '⚡' : elapsed < 500 ? '⏱️' : '🐌';
      debug('$icon Finished: $operation (${elapsed}ms)');
    }
  }

  /// Log a section separator (useful for grouping logs)
  static void separator([String? title]) {
    if (kDebugMode) {
      if (title != null) {
        debugPrint('\n${'=' * 60}');
        debugPrint('  $title');
        debugPrint('${'=' * 60}\n');
      } else {
        debugPrint('${'─' * 60}');
      }
    }
  }
}
