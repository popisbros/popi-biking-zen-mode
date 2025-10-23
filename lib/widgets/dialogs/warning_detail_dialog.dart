import 'package:flutter/material.dart';
import '../../models/community_warning.dart';
import '../../config/poi_type_config.dart';
import '../../constants/app_colors.dart';
import '../common_dialog.dart';

/// Warning detail dialog widget
///
/// Displays detailed information about a community warning/hazard
/// Consolidates duplicate dialogs from map_screen and mapbox_map_screen_simple
class WarningDetailDialog extends StatelessWidget {
  final CommunityWarning warning;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool compact;

  const WarningDetailDialog({
    super.key,
    required this.warning,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Get warning type emoji and label
    final typeEmoji = POITypeConfig.getWarningEmoji(warning.type);
    final typeLabel = POITypeConfig.getWarningLabel(warning.type);

    // Get severity color
    final severityColors = {
      'low': AppColors.successGreen,
      'medium': Colors.yellow[700],
      'high': Colors.orange[700],
      'critical': AppColors.dangerRed,
    };
    final severityColor = severityColors[warning.severity] ?? Colors.yellow[700];

    // Use CommonDialog styling for consistency
    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
      titlePadding: CommonDialog.titlePadding,
      contentPadding: CommonDialog.contentPadding,
      actionsPadding: CommonDialog.actionsPadding,
      title: Text(
        warning.title,
        style: const TextStyle(fontSize: CommonDialog.titleFontSize, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type with icon
            Row(
              children: [
                const Text(
                  'Type: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
                Text(
                  typeEmoji,
                  style: const TextStyle(fontSize: CommonDialog.titleFontSize),
                ),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Severity with colored badge
            Row(
              children: [
                const Text(
                  'Severity: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 12,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    warning.severity.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.surface,
                      fontWeight: FontWeight.bold,
                      fontSize: compact ? 12 : 14,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Coordinates
            CommonDialog.buildCaptionText(
              'Coordinates: ${warning.latitude.toStringAsFixed(6)}, ${warning.longitude.toStringAsFixed(6)}',
            ),

            // Description
            if (warning.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              Text(
                warning.description,
                style: const TextStyle(fontSize: CommonDialog.bodyFontSize),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Edit button
            CommonDialog.buildBorderedTextButton(
              label: 'EDIT',
              textColor: Colors.blue,
              onPressed: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            const SizedBox(height: 8),
            // Delete button
            CommonDialog.buildBorderedTextButton(
              label: 'DELETE',
              textColor: Colors.red,
              borderColor: Colors.red.withValues(alpha: 0.5),
              onPressed: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
            // Close button
            CommonDialog.buildBorderedTextButton(
              label: 'CLOSE',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ],
    );
  }

  /// Show warning details dialog
  ///
  /// Convenience method to show the dialog
  ///
  /// Example:
  /// ```dart
  /// WarningDetailDialog.show(
  ///   context: context,
  ///   warning: warning,
  ///   onEdit: () { /* navigate to edit screen */ },
  ///   onDelete: () async { /* delete warning */ },
  ///   compact: true, // For 3D map
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    required CommunityWarning warning,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    bool compact = false,
  }) {
    return showDialog(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => WarningDetailDialog(
        warning: warning,
        onEdit: onEdit,
        onDelete: onDelete,
        compact: compact,
      ),
    );
  }
}
