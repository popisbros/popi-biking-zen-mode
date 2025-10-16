import 'package:flutter/material.dart';

/// Global toast service for showing quick messages
/// Uses a global navigator key to show toasts without BuildContext
class ToastService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Show a toast message
  static void show(String message, {
    Duration duration = const Duration(seconds: 3),
    Color backgroundColor = const Color(0xFF323232),
    Color textColor = Colors.white,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
          ),
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 10),
      ),
    );
  }

  /// Show success toast (green)
  static void success(String message) {
    show(
      message,
      backgroundColor: const Color(0xFF4CAF50),
    );
  }

  /// Show error toast (red)
  static void error(String message) {
    show(
      message,
      backgroundColor: const Color(0xFFF44336),
    );
  }

  /// Show warning toast (orange)
  static void warning(String message) {
    show(
      message,
      backgroundColor: const Color(0xFFFF9800),
    );
  }

  /// Show info toast (blue)
  static void info(String message) {
    show(
      message,
      backgroundColor: const Color(0xFF2196F3),
    );
  }
}
