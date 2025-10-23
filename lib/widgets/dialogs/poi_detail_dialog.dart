import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cycling_poi.dart';
import '../../config/poi_type_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_visibility_provider.dart';
import '../common_dialog.dart';

/// POI detail dialog widget
///
/// Displays detailed information about an OpenStreetMap POI
/// Consolidates duplicate dialogs from map_screen and mapbox_map_screen_simple
class POIDetailDialog extends ConsumerWidget {
  final OSMPOI poi;
  final VoidCallback onRouteTo;
  final bool compact;

  const POIDetailDialog({
    super.key,
    required this.poi,
    required this.onRouteTo,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeEmoji = POITypeConfig.getOSMPOIEmoji(poi.type);
    final typeLabel = POITypeConfig.getOSMPOILabel(poi.type);

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
                  style: const TextStyle(fontSize: CommonDialog.bodyFontSize),
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
            const SizedBox(height: 8),
            CommonDialog.buildCaptionText(
              'Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}',
            ),

            // Optional fields
            if (poi.description != null && poi.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              CommonDialog.buildBodyText(poi.description!),
            ],

            if (poi.address != null && poi.address!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Address:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              CommonDialog.buildBodyText(poi.address!),
            ],

            if (poi.phone != null && poi.phone!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Phone:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              CommonDialog.buildBodyText(poi.phone!),
            ],

            if (poi.website != null && poi.website!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Website:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              CommonDialog.buildBodyText(poi.website!),
            ],
          ],
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // First row: Route To and Close
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CommonDialog.buildActionButton(
                  label: 'ROUTE TO',
                  icon: const Text('🚴‍♂️', style: TextStyle(fontSize: 18)),
                  onPressed: () {
                    Navigator.pop(context);
                    onRouteTo();
                  },
                ),
                CommonDialog.buildActionButton(
                  label: 'CLOSE',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            // Second row: Add to Favorites (only show if user is logged in)
            if (authUser != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    ref.read(authNotifierProvider.notifier).toggleFavorite(
                      poi.name,
                      poi.latitude,
                      poi.longitude,
                    );
                    // Auto-enable favorites visibility so user can see their new favorite
                    if (!isFavorite) {
                      ref.read(favoritesVisibilityProvider.notifier).state = true;
                    }
                  },
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    size: 18,
                    color: isFavorite ? Colors.amber : Colors.grey,
                  ),
                  label: Text(isFavorite ? 'FAVORITED' : 'ADD TO FAVORITES'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Show POI details dialog
  ///
  /// Convenience method to show the dialog
  ///
  /// Example:
  /// ```dart
  /// POIDetailDialog.show(
  ///   context: context,
  ///   poi: poi,
  ///   onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude),
  ///   compact: true, // For 3D map
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    required OSMPOI poi,
    required VoidCallback onRouteTo,
    bool compact = false,
  }) {
    return showDialog(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => POIDetailDialog(
        poi: poi,
        onRouteTo: onRouteTo,
        compact: compact,
      ),
    );
  }
}
