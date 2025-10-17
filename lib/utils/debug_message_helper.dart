import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/debug_provider.dart';
import 'app_logger.dart';

/// Helper for safely adding debug messages to the debug provider
///
/// Consolidates the try-catch pattern used in background loading methods
class DebugMessageHelper {
  /// Safely add a debug message to the debug provider
  ///
  /// If the debug provider fails (e.g., not initialized), logs the error
  /// but doesn't throw, allowing the operation to continue
  ///
  /// Example:
  /// ```dart
  /// DebugMessageHelper.addMessage(
  ///   ref,
  ///   'API: Fetching warnings [bounds]',
  ///   tag: 'COMMUNITY',
  /// );
  /// ```
  static void addMessage(
    Ref ref,
    String message, {
    String tag = 'DEBUG',
  }) {
    try {
      ref.read(debugProvider.notifier).addDebugMessage(message);
    } catch (e) {
      AppLogger.debug(
        'Debug message failed',
        tag: tag,
        data: {'message': message, 'error': e.toString()},
      );
    }
  }
}
