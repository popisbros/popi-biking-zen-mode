import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../widgets/dialogs/poi_detail_dialog.dart';
import '../widgets/dialogs/warning_detail_dialog.dart';
import '../widgets/dialogs/community_poi_detail_dialog.dart';
import '../providers/community_provider.dart';
import '../screens/community/hazard_report_screen.dart';
import 'app_logger.dart';

/// Utility class for showing POI-related dialogs with consistent behavior
///
/// Consolidates duplicate dialog handling logic from map screens
class POIDialogHandler {
  /// Show OSM POI details dialog
  static void showPOIDetails({
    required BuildContext context,
    required OSMPOI poi,
    required VoidCallback onRouteTo,
    bool compact = false,
  }) {
    POIDetailDialog.show(
      context: context,
      poi: poi,
      onRouteTo: onRouteTo,
      compact: compact,
    );
  }

  /// Show warning details dialog with edit/delete callbacks
  static void showWarningDetails({
    required BuildContext context,
    required WidgetRef ref,
    required CommunityWarning warning,
    required VoidCallback onDataChanged,
    bool compact = false,
  }) {
    WarningDetailDialog.show(
      context: context,
      warning: warning,
      compact: compact,
      onEdit: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HazardReportScreenWithLocation(
              initialLatitude: warning.latitude,
              initialLongitude: warning.longitude,
              editingWarningId: warning.id,
            ),
          ),
        ).then((_) => onDataChanged());
      },
      onDelete: () async {
        if (warning.id != null) {
          AppLogger.map('Deleting warning', data: {'id': warning.id});
          await ref.read(communityWarningsNotifierProvider.notifier)
              .deleteWarning(warning.id!);
          onDataChanged();
        }
      },
    );
  }

  /// Show Community POI details dialog
  static void showCommunityPOIDetails({
    required BuildContext context,
    required WidgetRef ref,
    required CyclingPOI poi,
    required VoidCallback onRouteTo,
    required VoidCallback onDataChanged,
    bool compact = false,
  }) {
    CommunityPOIDetailDialog.show(
      context: context,
      ref: ref,
      poi: poi,
      onRouteTo: onRouteTo,
      onDataChanged: onDataChanged,
      compact: compact,
    );
  }
}
