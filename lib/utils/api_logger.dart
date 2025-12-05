import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// API Logger for tracking API calls and responses in production
///
/// Logs to:
/// - Crashlytics: Always (breadcrumbs + errors)
/// - Firestore: API calls in production, ALL logs in debug
class ApiLogger {
  static final _firestore = FirebaseFirestore.instance;
  static final _crashlytics = FirebaseCrashlytics.instance;

  /// Log an API call with full details
  ///
  /// Always logged to Crashlytics and Firestore (even in production)
  static Future<void> logApiCall({
    required String endpoint,
    required String method,
    required String url,
    Map<String, dynamic>? parameters,
    required int statusCode,
    required String responseBody,
    String? error,
    int? durationMs,
  }) async {
    final timestamp = DateTime.now();
    final isError = statusCode >= 400 || error != null;

    // 1. Log to Crashlytics (always)
    final logMessage = '[${timestamp.toIso8601String().substring(11, 23)}] $method $endpoint - Status: $statusCode${durationMs != null ? " (${durationMs}ms)" : ""}';
    _crashlytics.log(logMessage);

    // 2. If error, record as non-fatal with full details
    if (isError) {
      await _crashlytics.recordError(
        Exception('API Error: $statusCode'),
        null,
        reason: '$method $endpoint failed',
        information: [
          'URL: $url',
          'Parameters: ${parameters?.toString() ?? "none"}',
          'Status: $statusCode',
          'Response: ${responseBody.length > 500 ? "${responseBody.substring(0, 500)}..." : responseBody}',
          'Error: ${error ?? "none"}',
          'Duration: ${durationMs ?? 0}ms',
        ],
        fatal: false,
      );
    }

    // 3. Log to Firestore (fire-and-forget, don't block API calls)
    _logToFirestore(
      type: 'api',
      level: isError ? 'error' : 'info',
      message: '$method $endpoint',
      data: {
        'endpoint': endpoint,
        'method': method,
        'url': url,
        'parameters': parameters,
        'statusCode': statusCode,
        'responseBody': responseBody.length > 1000
            ? '${responseBody.substring(0, 1000)}...(truncated)'
            : responseBody,
        'error': error,
        'durationMs': durationMs,
        'isError': isError,
      },
      timestamp: timestamp,
    );
  }

  /// Log general application logs (only in debug mode)
  ///
  /// In debug mode: logs to Firestore
  /// In production: only uses existing AppLogger (debugPrint)
  static void logDebug(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _logToFirestore(
        type: 'debug',
        level: 'debug',
        message: message,
        tag: tag,
        data: data,
        timestamp: DateTime.now(),
      );
    }
  }

  static void logInfo(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _logToFirestore(
        type: 'info',
        level: 'info',
        message: message,
        tag: tag,
        data: data,
        timestamp: DateTime.now(),
      );
    }
  }

  static void logWarning(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _logToFirestore(
        type: 'warning',
        level: 'warning',
        message: message,
        tag: tag,
        data: data,
        timestamp: DateTime.now(),
      );
    }
  }

  static void logError(String message, {String? tag, Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    // Always log errors to Crashlytics (fire-and-forget)
    if (error != null) {
      _crashlytics.recordError(
        error,
        stackTrace,
        reason: '[$tag] $message',
        fatal: false,
      );
    }

    // In debug mode, also log to Firestore (fire-and-forget)
    if (kDebugMode) {
      _logToFirestore(
        type: 'error',
        level: 'error',
        message: message,
        tag: tag,
        data: {
          ...?data,
          'error': error?.toString(),
          'stackTrace': stackTrace?.toString().split('\n').take(5).join('\n'),
        },
        timestamp: DateTime.now(),
      );
    }
  }

  /// Internal method to log to Firestore
  /// This method is fire-and-forget to avoid blocking the main thread
  static void _logToFirestore({
    required String type,
    required String level,
    required String message,
    String? tag,
    Map<String, dynamic>? data,
    required DateTime timestamp,
  }) {
    // Fire-and-forget: Don't await Firestore writes to avoid blocking UI
    _writeLogAsync(
      type: type,
      level: level,
      message: message,
      tag: tag,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Async helper that actually writes to Firestore (non-blocking)
  static Future<void> _writeLogAsync({
    required String type,
    required String level,
    required String message,
    String? tag,
    Map<String, dynamic>? data,
    required DateTime timestamp,
  }) async {
    try {
      // Get current user ID (or anonymous)
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

      final logData = {
        'type': type,
        'level': level,
        'message': message,
        'tag': tag,
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': timestamp.toIso8601String(),
        'userId': userId,
        'platform': defaultTargetPlatform.name,
        'mode': kDebugMode ? 'debug' : (kReleaseMode ? 'release' : 'profile'),
      };

      print('📝 [FIRESTORE DEBUG] Attempting to write log to Firestore: $type/$level - $message');
      await _firestore.collection('logs').add(logData);
      print('✅ [FIRESTORE DEBUG] Successfully wrote log to Firestore');
    } catch (e) {
      // Print error to console (works in all build modes)
      print('❌ [FIRESTORE DEBUG] Failed to log to Firestore: $e');

      // Also use debugPrint in debug mode for more details
      if (kDebugMode) {
        debugPrint('❌ Failed to log to Firestore: $e');
      }
    }
  }

  /// Get recent API logs for debugging (only in debug mode)
  static Future<List<Map<String, dynamic>>> getRecentApiLogs({int limit = 50}) async {
    if (!kDebugMode) return [];

    try {
      final snapshot = await _firestore
          .collection('logs')
          .where('type', isEqualTo: 'api')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch logs: $e');
      return [];
    }
  }

  /// Clean up old logs (older than specified duration)
  ///
  /// Should be called on app startup to prevent Firestore from growing indefinitely.
  /// Deletes logs in batches to respect Firestore limits.
  static Future<void> cleanupOldLogs({Duration age = const Duration(hours: 2)}) async {
    try {
      final cutoffTime = DateTime.now().subtract(age);
      final cutoffTimestamp = Timestamp.fromDate(cutoffTime);

      debugPrint('🧹 Cleaning up logs older than ${age.inHours}h (before ${cutoffTime.toIso8601String()})');

      // Query logs older than cutoff time
      // Note: We use clientTimestamp as a fallback since timestamp is server-generated
      final snapshot = await _firestore
          .collection('logs')
          .where('timestamp', isLessThan: cutoffTimestamp)
          .limit(500) // Batch limit
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('✅ No old logs to clean up');
        return;
      }

      // Delete in batch (max 500 operations per batch)
      final batch = _firestore.batch();
      int deleteCount = 0;

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
        deleteCount++;
      }

      await batch.commit();
      debugPrint('✅ Deleted $deleteCount old log entries');

      // If we deleted 500, there might be more - recursively clean
      if (snapshot.docs.length == 500) {
        debugPrint('🔄 More logs to clean, continuing...');
        await cleanupOldLogs(age: age);
      }
    } catch (e) {
      // Silently fail - don't break app for cleanup
      if (kDebugMode) {
        debugPrint('❌ Failed to cleanup old logs: $e');
      }
    }
  }

  /// Schedule periodic cleanup (call this on app startup)
  ///
  /// Runs cleanup immediately and then sets up periodic cleanup.
  /// In production, consider using Cloud Functions scheduled trigger instead.
  static Future<void> initializeLogCleanup({Duration age = const Duration(hours: 2)}) async {
    // Run initial cleanup
    await cleanupOldLogs(age: age);

    // Note: For continuous cleanup, you should use Cloud Functions with a scheduled trigger
    // This client-side approach only cleans on app startup
    debugPrint('✅ Log cleanup initialized (runs on app startup)');
  }
}
