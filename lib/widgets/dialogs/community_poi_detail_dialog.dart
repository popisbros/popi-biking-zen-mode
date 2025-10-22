import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cycling_poi.dart';
import '../../config/poi_type_config.dart';
import '../../providers/community_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';
import '../../screens/community/poi_management_screen.dart';

/// Community POI detail dialog widget
///
/// Displays detailed information about a user-created POI with edit/delete capabilities
/// Consolidates duplicate dialogs from map_screen and mapbox_map_screen_simple
class CommunityPOIDetailDialog extends ConsumerWidget {
  final CyclingPOI poi;
  final VoidCallback onRouteTo;
  final VoidCallback onDataChanged;
  final bool compact;

  const CommunityPOIDetailDialog({
    super.key,
    required this.poi,
    required this.onRouteTo,
    required this.onDataChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeEmoji = POITypeConfig.getCommunityPOIEmoji(poi.type);
    final typeLabel = POITypeConfig.getCommunityPOILabel(poi.type);

    // Check if user is logged in and if this POI is favorited
    final authUser = ref.watch(authStateProvider).value;
    final userProfile = ref.watch(userProfileProvider).value;
    final isFavorite = userProfile?.favoriteLocations.any(
      (loc) => loc.latitude == poi.latitude && loc.longitude == poi.longitude
    ) ?? false;

    // Styling based on compact mode
    final backgroundOpacity = compact ? 0.9 : 0.6;
    final titleFontSize = compact ? 14.0 : null;
    final bodyFontSize = compact ? 12.0 : null;
    final titlePadding = compact ? const EdgeInsets.fromLTRB(24, 16, 24, 8) : null;
    final contentPadding = compact ? const EdgeInsets.fromLTRB(24, 0, 24, 8) : null;
    final actionsPadding = compact ? const EdgeInsets.fromLTRB(24, 0, 16, 8) : null;
    final sectionSpacing = compact ? 6.0 : 12.0;

    return AlertDialog(
      backgroundColor: Colors.white.withOpacity(backgroundOpacity),
      titlePadding: titlePadding,
      contentPadding: contentPadding,
      actionsPadding: actionsPadding,
      title: Text(
        poi.name,
        style: titleFontSize != null ? TextStyle(fontSize: titleFontSize) : null,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // POI Type
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
                    fontWeight: FontWeight.w500,
                    fontSize: bodyFontSize,
                  ),
                ),
              ],
            ),

            // Coordinates
            SizedBox(height: compact ? 4 : 4),
            Text(
              'Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}',
              style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
            ),

            // Optional fields
            if (poi.description != null && poi.description!.isNotEmpty) ...[
              SizedBox(height: sectionSpacing),
              Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: bodyFontSize,
                ),
              ),
              Text(
                poi.description!,
                style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
              ),
            ],

            if (poi.address != null && poi.address!.isNotEmpty) ...[
              SizedBox(height: sectionSpacing),
              Text(
                'Address:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: bodyFontSize,
                ),
              ),
              Text(
                poi.address!,
                style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
              ),
            ],

            if (poi.phone != null && poi.phone!.isNotEmpty) ...[
              SizedBox(height: sectionSpacing),
              Text(
                'Phone:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: bodyFontSize,
                ),
              ),
              Text(
                poi.phone!,
                style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
              ),
            ],

            if (poi.website != null && poi.website!.isNotEmpty) ...[
              SizedBox(height: sectionSpacing),
              Text(
                'Website:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: bodyFontSize,
                ),
              ),
              Text(
                poi.website!,
                style: bodyFontSize != null ? TextStyle(fontSize: bodyFontSize) : null,
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Two rows of buttons
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // First row: Route To, Edit, Delete, Close
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onRouteTo();
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🚴‍♂️', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 4),
                      Text('ROUTE TO', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Navigate to edit screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => POIManagementScreenWithLocation(
                          initialLatitude: poi.latitude,
                          initialLongitude: poi.longitude,
                          editingPOIId: poi.id,
                        ),
                      ),
                    ).then((_) {
                      // Reload map data after edit
                      onDataChanged();
                    });
                  },
                  child: const Text('EDIT', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (poi.id != null) {
                      AppLogger.map('Deleting POI', data: {'id': poi.id});
                      await ref.read(cyclingPOIsNotifierProvider.notifier).deletePOI(poi.id!);
                      // Reload map data
                      onDataChanged();
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('DELETE', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            // Second row: Add to Favorites (only show if user is logged in)
            if (authUser != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ref.read(authNotifierProvider.notifier).toggleFavorite(
                      poi.name,
                      poi.latitude,
                      poi.longitude,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        size: 16,
                        color: isFavorite ? Colors.amber : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isFavorite ? 'FAVORITED' : 'ADD TO FAVORITES',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Show Community POI details dialog
  ///
  /// Convenience method to show the dialog
  ///
  /// Example:
  /// ```dart
  /// CommunityPOIDetailDialog.show(
  ///   context: context,
  ///   ref: ref,
  ///   poi: poi,
  ///   onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude),
  ///   onDataChanged: () {
  ///     if (mounted && _isMapReady) {
  ///       _loadAllMapDataWithBounds(forceReload: true);
  ///     }
  ///   },
  ///   compact: false, // For 2D map
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    required CyclingPOI poi,
    required VoidCallback onRouteTo,
    required VoidCallback onDataChanged,
    bool compact = false,
    bool transparentBarrier = false,
  }) {
    return showDialog(
      context: context,
      barrierColor: transparentBarrier ? Colors.transparent : null,
      builder: (context) => CommunityPOIDetailDialog(
        poi: poi,
        onRouteTo: onRouteTo,
        onDataChanged: onDataChanged,
        compact: compact,
      ),
    );
  }
}
