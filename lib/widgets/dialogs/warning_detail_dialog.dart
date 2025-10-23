import 'package:flutter/material.dart';
import '../../models/community_warning.dart';
import '../../config/poi_type_config.dart';
import '../../constants/app_colors.dart';

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

    // Styling based on compact mode
    final backgroundOpacity = compact ? 0.9 : 0.6;
    final titleFontSize = compact ? 14.0 : null;
    final bodyFontSize = compact ? 12.0 : null;
    final titlePadding = compact ? const EdgeInsets.fromLTRB(24, 16, 24, 8) : null;
    final contentPadding = compact ? const EdgeInsets.fromLTRB(24, 0, 24, 8) : null;
    final actionsPadding = compact ? const EdgeInsets.fromLTRB(24, 0, 16, 8) : null;
    final sectionSpacing = compact ? 6.0 : 12.0;
    final topSpacing = compact ? 4.0 : 8.0;

    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: backgroundOpacity),
      titlePadding: titlePadding,
      contentPadding: contentPadding,
      actionsPadding: actionsPadding,
      title: Text(
        warning.title,
        style: titleFontSize != null ? TextStyle(fontSize: titleFontSize) : null,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type with icon
            Row(
              children: [
                Text(
                  'Type: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: bodyFontSize,
                  ),
                ),
                Text(
                  typeEmoji,
                  style: TextStyle(fontSize: compact ? 14 : 16),
                ),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: bodyFontSize,
                  ),
                ),
              ],
            ),

            SizedBox(height: topSpacing),

            // Severity with colored badge
            Row(
              children: [
                Text(
                  'Severity: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: bodyFontSize,
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

            SizedBox(height: compact ? 4 : 4),

            // Coordinates
            Text(
              'Coordinates: ${warning.latitude.toStringAsFixed(6)}, ${warning.longitude.toStringAsFixed(6)}',
              style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
            ),

            // Description
            if (warning.description.isNotEmpty) ...[
              SizedBox(height: sectionSpacing),
              Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: bodyFontSize,
                ),
              ),
              Text(
                warning.description,
                style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onEdit();
          },
          child: Text(
            'EDIT',
            style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onDelete();
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(
            'DELETE',
            style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CLOSE',
            style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
          ),
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
    bool transparentBarrier = false,
  }) {
    return showDialog(
      context: context,
      barrierColor: transparentBarrier ? Colors.transparent : null,
      builder: (context) => WarningDetailDialog(
        warning: warning,
        onEdit: onEdit,
        onDelete: onDelete,
        compact: compact,
      ),
    );
  }
}
