import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cycling_poi.dart';
import '../../config/poi_type_config.dart';
import '../../providers/community_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';
import '../../screens/community/poi_management_screen.dart';
import '../common_dialog.dart';

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

    // Use CommonDialog styling for consistency
    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
      titlePadding: CommonDialog.titlePadding,
      contentPadding: CommonDialog.contentPadding,
      actionsPadding: CommonDialog.actionsPadding,
      title: Text(
        poi.name,
        style: const TextStyle(
          fontSize: CommonDialog.titleFontSize,
          fontWeight: FontWeight.bold,
        ),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
                Text(
                  typeEmoji,
                  style: const TextStyle(fontSize: compact ? 14 : 16),
                ),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
              ],
            ),

            // Coordinates
            SizedBox(height: compact ? 4 : 4),
            Text(
              'Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}',
              style: bodyFontSize != null ? TextStyle(fontSize: CommonDialog.bodyFontSize) : null,
            ),

            // Optional fields
            if (poi.description != null && poi.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Description:',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              Text(
                poi.description!,
                style: bodyFontSize != null ? TextStyle(fontSize: CommonDialog.bodyFontSize) : null,
              ),
            ],

            if (poi.address != null && poi.address!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Address:',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              Text(
                poi.address!,
                style: bodyFontSize != null ? TextStyle(fontSize: CommonDialog.bodyFontSize) : null,
              ),
            ],

            if (poi.phone != null && poi.phone!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Phone:',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              Text(
                poi.phone!,
                style: bodyFontSize != null ? TextStyle(fontSize: CommonDialog.bodyFontSize) : null,
              ),
            ],

            if (poi.website != null && poi.website!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Website:',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              Text(
                poi.website!,
                style: bodyFontSize != null ? TextStyle(fontSize: CommonDialog.bodyFontSize) : null,
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
                      Text('🚴‍♂️', style: const TextStyle(fontSize: 14)),
                      SizedBox(width: 4),
                      Text('ROUTE TO', style: const TextStyle(fontSize: 12)),
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
                  child: const Text('EDIT', style: const TextStyle(fontSize: 12)),
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
                  child: const Text('DELETE', style: const TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            // Second row: Add to Favorites (only show if user is logged in)
            if (authUser != null)
              Align(
                alignment: Alignment.centerLeft,
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
  }) {
    return showDialog(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => CommunityPOIDetailDialog(
        poi: poi,
        onRouteTo: onRouteTo,
        onDataChanged: onDataChanged,
        compact: compact,
      ),
    );
  }
}
