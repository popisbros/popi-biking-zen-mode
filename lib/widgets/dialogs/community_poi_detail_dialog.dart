import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cycling_poi.dart';
import '../../config/poi_type_config.dart';
import '../../providers/community_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_visibility_provider.dart';
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
    // Theme detection
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBgColor = isDark
        ? const Color(0xFF2C2C2C).withValues(alpha: CommonDialog.backgroundOpacity)
        : Colors.white.withValues(alpha: CommonDialog.backgroundOpacity);
    final textColor = isDark ? Colors.white : Colors.black;

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
      backgroundColor: dialogBgColor,
      titlePadding: CommonDialog.titlePadding,
      contentPadding: CommonDialog.contentPadding,
      actionsPadding: CommonDialog.actionsPadding,
      title: Text(
        poi.name,
        style: TextStyle(
          fontSize: CommonDialog.titleFontSize,
          fontWeight: FontWeight.bold,
          color: textColor,
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
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                    color: textColor,
                  ),
                ),
                Text(
                  typeEmoji,
                  style: const TextStyle(fontSize: CommonDialog.titleFontSize),
                ),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                    color: textColor,
                  ),
                ),
              ],
            ),

            // Coordinates
            const SizedBox(height: 4),
            CommonDialog.buildCaptionText(
              'Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}',
              context: context,
            ),

            // Optional fields
            if (poi.description != null && poi.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                  color: textColor,
                ),
              ),
              Text(
                poi.description!,
                style: TextStyle(fontSize: CommonDialog.bodyFontSize, color: textColor),
              ),
            ],

            if (poi.address != null && poi.address!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Address:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                  color: textColor,
                ),
              ),
              Text(
                poi.address!,
                style: TextStyle(fontSize: CommonDialog.bodyFontSize, color: textColor),
              ),
            ],

            if (poi.phone != null && poi.phone!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Phone:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                  color: textColor,
                ),
              ),
              Text(
                poi.phone!,
                style: TextStyle(fontSize: CommonDialog.bodyFontSize, color: textColor),
              ),
            ],

            if (poi.website != null && poi.website!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Website:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                  color: textColor,
                ),
              ),
              Text(
                poi.website!,
                style: TextStyle(fontSize: CommonDialog.bodyFontSize, color: textColor),
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
            // Route To button
            CommonDialog.buildBorderedTextButton(
              label: 'ROUTE TO',
              icon: const Text('🚴‍♂️', style: TextStyle(fontSize: 18)),
              onPressed: () {
                Navigator.pop(context);
                onRouteTo();
              },
            ),
            const SizedBox(height: 8),
            // Add to Favorites button (only show if user is logged in)
            if (authUser != null)
              CommonDialog.buildBorderedTextButton(
                label: isFavorite ? 'FAVORITED' : 'ADD TO FAVORITES',
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  size: 18,
                  color: isFavorite ? Colors.amber : Colors.grey,
                ),
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
              ),
            if (authUser != null)
              const SizedBox(height: 8),
            // Edit button (only show if user is logged in)
            if (authUser != null)
              CommonDialog.buildBorderedTextButton(
                label: 'EDIT',
                textColor: Colors.blue,
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
              ),
            if (authUser != null)
              const SizedBox(height: 8),
            // Delete button (only show if user is logged in)
            if (authUser != null)
              CommonDialog.buildBorderedTextButton(
                label: 'DELETE',
                textColor: Colors.red,
                borderColor: Colors.red.withValues(alpha: 0.5),
                onPressed: () async {
                  Navigator.pop(context);
                  if (poi.id != null) {
                    AppLogger.map('Deleting POI', data: {'id': poi.id});
                    await ref.read(cyclingPOIsNotifierProvider.notifier).deletePOI(poi.id!);
                    // Reload map data
                    onDataChanged();
                  }
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
