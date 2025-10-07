import 'dart:math';
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
          'Response: ${responseBody.length > 500 ? responseBody.substring(0, 500) + "..." : responseBody}',
          'Error: ${error ?? "none"}',
          'Duration: ${durationMs ?? 0}ms',
        ],
        fatal: false,
      );
    }

    // 3. Log to Firestore (always for API calls, even in production)
    await _logToFirestore(
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
            ? responseBody.substring(0, 1000) + '...(truncated)'
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
  static Future<void> logDebug(String message, {String? tag, Map<String, dynamic>? data}) async {
    if (kDebugMode) {
      await _logToFirestore(
        type: 'debug',
        level: 'debug',
        message: message,
        tag: tag,
        data: data,
        timestamp: DateTime.now(),
      );
    }
  }

  static Future<void> logInfo(String message, {String? tag, Map<String, dynamic>? data}) async {
    if (kDebugMode) {
      await _logToFirestore(
        type: 'info',
        level: 'info',
        message: message,
        tag: tag,
        data: data,
        timestamp: DateTime.now(),
      );
    }
  }

  static Future<void> logWarning(String message, {String? tag, Map<String, dynamic>? data}) async {
    if (kDebugMode) {
      await _logToFirestore(
        type: 'warning',
        level: 'warning',
        message: message,
        tag: tag,
        data: data,
        timestamp: DateTime.now(),
      );
    }
  }

  static Future<void> logError(String message, {String? tag, Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) async {
    // Always log errors to Crashlytics
    if (error != null) {
      await _crashlytics.recordError(
        error,
        stackTrace,
        reason: '[$tag] $message',
        fatal: false,
      );
    }

    // In debug mode, also log to Firestore
    if (kDebugMode) {
      await _logToFirestore(
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
  static Future<void> _logToFirestore({
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

      await _firestore.collection('logs').add({
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
      });
    } catch (e) {
      // Silently fail - don't break app for logging
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
}
