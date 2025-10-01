import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralized error handling service
///
/// This service provides consistent error handling across the app:
/// - Logs errors to console in debug mode
/// - Reports to crash analytics in production (TODO: Firebase Crashlytics)
/// - Shows user-friendly error messages
class ErrorService {
  ErrorService._();

  static final ErrorService _instance = ErrorService._();
  static ErrorService get instance => _instance;

  /// Log an error with context
  void logError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (kDebugMode) {
      debugPrint('❌ ERROR: $message');
      if (error != null) debugPrint('   Error: $error');
      if (context != null) debugPrint('   Context: $context');
      if (stackTrace != null) debugPrint('   Stack: $stackTrace');
    }

    // TODO: Report to Firebase Crashlytics in production
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, context: context);
  }

  /// Log a warning
  void logWarning(
    String message, {
    Map<String, dynamic>? context,
  }) {
    if (kDebugMode) {
      debugPrint('⚠️ WARNING: $message');
      if (context != null) debugPrint('   Context: $context');
    }
  }

  /// Log info for debugging
  void logInfo(
    String message, {
    Map<String, dynamic>? context,
  }) {
    if (kDebugMode) {
      debugPrint('ℹ️ INFO: $message');
      if (context != null) debugPrint('   Context: $context');
    }
  }

  /// Show user-friendly error message
  void showErrorSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: duration,
        action: action,
      ),
    );
  }

  /// Show success message
  void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: duration,
      ),
    );
  }

  /// Show info message
  void showInfoSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: Colors.blue[700],
        duration: duration,
      ),
    );
  }

  /// Handle common errors with user-friendly messages
  String getUserFriendlyMessage(Object error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('socket')) {
      return 'Network error. Please check your connection.';
    }

    if (errorString.contains('permission')) {
      return 'Permission denied. Please check app settings.';
    }

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    if (errorString.contains('firebase') || errorString.contains('firestore')) {
      return 'Database error. Please try again later.';
    }

    if (errorString.contains('not found') || errorString.contains('404')) {
      return 'Resource not found.';
    }

    if (errorString.contains('unauthorized') || errorString.contains('401')) {
      return 'Authentication required. Please sign in.';
    }

    // Generic fallback
    return 'Something went wrong. Please try again.';
  }
}

/// Extension for easy error handling in async operations
extension ErrorHandlerExtension on Future {
  /// Handle errors with automatic logging and user notification
  Future<T?> handleError<T>(
    BuildContext context, {
    String? customMessage,
    bool showSnackBar = true,
  }) async {
    try {
      return await this;
    } catch (error, stackTrace) {
      final errorService = ErrorService.instance;
      errorService.logError(
        customMessage ?? 'Operation failed',
        error: error,
        stackTrace: stackTrace,
      );

      if (showSnackBar && context.mounted) {
        final message = customMessage ?? errorService.getUserFriendlyMessage(error);
        errorService.showErrorSnackBar(context, message);
      }

      return null;
    }
  }
}