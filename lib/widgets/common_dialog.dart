import 'package:flutter/material.dart';

/// Common dialog wrapper for consistent styling across the app
///
/// Provides unified:
/// - Background opacity (60%)
/// - Barrier color (semi-transparent grey overlay)
/// - Font sizes (title, body)
/// - Padding (title, content, actions)
///
/// Usage:
/// ```dart
/// CommonDialog.show(
///   context: context,
///   title: 'My Title',
///   content: MyContentWidget(),
///   actions: [MyActions()],
/// );
/// ```
class CommonDialog {
  // Private constructor to prevent instantiation
  CommonDialog._();

  // Consistent styling constants
  static const double backgroundOpacity = 0.6;
  static const Color barrierColor = Colors.black54; // Semi-transparent grey overlay
  static const double titleFontSize = 16.0; // Consistent title size
  static const double bodyFontSize = 14.0; // Consistent body size
  static const double smallFontSize = 12.0; // For secondary text
  static const EdgeInsets titlePadding = EdgeInsets.fromLTRB(24, 20, 24, 8);
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(24, 0, 24, 16);
  static const EdgeInsets actionsPadding = EdgeInsets.fromLTRB(24, 0, 16, 16);

  /// Show a standard dialog with consistent styling
  ///
  /// Parameters:
  /// - context: BuildContext for showing dialog
  /// - title: Title widget (usually Text or Row with emoji)
  /// - content: Main content widget
  /// - actions: Action buttons (optional)
  /// - barrierDismissible: Whether tapping outside closes dialog (default: true)
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget title,
    required Widget content,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: backgroundOpacity),
          titlePadding: titlePadding,
          contentPadding: contentPadding,
          actionsPadding: actions != null ? actionsPadding : EdgeInsets.zero,
          title: title,
          content: content,
          actions: actions,
        );
      },
    );
  }

  /// Create a standard title with emoji and text
  ///
  /// Parameters:
  /// - emoji: Emoji icon (e.g., '⭐', '📍', '⚠️')
  /// - text: Title text
  /// - maxLines: Maximum lines for text (default: 2)
  static Widget buildTitle({
    required String emoji,
    required String text,
    int maxLines = 2,
  }) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Create standard body text
  ///
  /// Parameters:
  /// - text: Body text
  /// - style: Optional custom TextStyle (defaults to bodyFontSize)
  static Widget buildBodyText(String text, {TextStyle? style}) {
    return Text(
      text,
      style: style ?? const TextStyle(fontSize: bodyFontSize),
    );
  }

  /// Create standard secondary/caption text
  ///
  /// Parameters:
  /// - text: Caption text
  /// - color: Text color (default: grey)
  static Widget buildCaptionText(String text, {Color color = Colors.grey}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: smallFontSize,
        color: color,
      ),
    );
  }

  /// Create a standard action button
  ///
  /// Parameters:
  /// - label: Button label
  /// - onPressed: Callback when pressed
  /// - icon: Optional icon widget (emoji Text or Icon)
  static Widget buildActionButton({
    required String label,
    required VoidCallback onPressed,
    Widget? icon,
  }) {
    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      );
    }
    return TextButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }

  /// Create a standard destructive action button (red)
  ///
  /// Parameters:
  /// - label: Button label
  /// - onPressed: Callback when pressed
  /// - icon: Optional icon (default: delete icon)
  static Widget buildDestructiveButton({
    required String label,
    required VoidCallback onPressed,
    Widget? icon,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon ?? const Icon(Icons.delete, color: Colors.red, size: 18),
      label: Text(
        label,
        style: const TextStyle(color: Colors.red),
      ),
    );
  }
}
