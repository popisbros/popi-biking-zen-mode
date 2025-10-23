import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../config/poi_type_config.dart';
import '../config/marker_config.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../utils/poi_utils.dart';
import '../utils/mapbox_marker_utils.dart';
import '../utils/app_logger.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_visibility_provider.dart';

/// Helper class for managing Mapbox annotations (markers) on the 3D map
/// Handles adding POIs, warnings, favorites, and route hazards as markers
class MapboxAnnotationHelper {
  /// Add OSM POIs as emoji icon markers
  static Future<void> addOSMPOIsAsIcons({
    required WidgetRef ref,
    required PointAnnotationManager pointAnnotationManager,
    required Map<String, OSMPOI> osmPoiById,
    required dynamic mapState,
  }) async {
    if (!mapState.showOSMPOIs) return;

    final osmPOIs = ref.read(osmPOIsNotifierProvider).value ?? [];

    // Filter POIs based on selected types using shared utility
    final filteredPOIs = POIUtils.filterPOIsByType(osmPOIs, mapState.selectedOSMPOITypes);

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding OSM POIs as icons', tag: 'MAP', data: {
      'total': osmPOIs.length,
      'filtered': filteredPOIs.length,
      'selectedTypes': mapState.selectedOSMPOITypes?.join(', ') ?? 'all',
    });

    for (var poi in filteredPOIs) {
      final id = 'osm_${poi.latitude}_${poi.longitude}';
      osmPoiById[id] = poi;

      // Get emoji for this POI type
      final emoji = POITypeConfig.getOSMPOIEmoji(poi.type);

      // Create icon image from emoji with proper colors
      final iconImage = await MapboxMarkerUtils.createEmojiIcon(emoji, POIMarkerType.osmPOI);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
          image: iconImage,
          iconSize: 1.5, // Optimized icon size
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await pointAnnotationManager.createMulti(pointOptions);
      AppLogger.success('Added OSM POI icons', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Add Community POIs as emoji icon markers
  static Future<void> addCommunityPOIsAsIcons({
    required WidgetRef ref,
    required PointAnnotationManager pointAnnotationManager,
    required Map<String, CyclingPOI> communityPoiById,
    required dynamic mapState,
  }) async {
    if (!mapState.showPOIs) return;

    final allCommunityPOIs = ref.read(cyclingPOIsBoundsNotifierProvider).value ?? [];

    // Filter out deleted POIs
    final communityPOIs = allCommunityPOIs.where((poi) => !poi.isDeleted).toList();

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding Community POIs as icons', tag: 'MAP', data: {
      'total': allCommunityPOIs.length,
      'visible': communityPOIs.length,
      'deleted': allCommunityPOIs.length - communityPOIs.length,
    });

    for (var poi in communityPOIs) {
      final id = 'community_${poi.latitude}_${poi.longitude}';
      communityPoiById[id] = poi;

      // Get emoji for this POI type
      final emoji = POITypeConfig.getCommunityPOIEmoji(poi.type);

      // Create icon image from emoji with proper colors
      final iconImage = await MapboxMarkerUtils.createEmojiIcon(emoji, POIMarkerType.communityPOI);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
          image: iconImage,
          iconSize: 1.5, // Optimized icon size
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await pointAnnotationManager.createMulti(pointOptions);
      AppLogger.success('Added Community POI icons', tag: 'MAP', data: {'count': pointOptions.length});
    } else {
      AppLogger.warning('No Community POI icons to add', tag: 'MAP');
    }
  }

  /// Add Warnings as emoji icon markers
  static Future<void> addWarningsAsIcons({
    required WidgetRef ref,
    required PointAnnotationManager pointAnnotationManager,
    required Map<String, CommunityWarning> warningById,
    required dynamic mapState,
  }) async {
    if (!mapState.showWarnings) return;

    final allWarnings = ref.read(communityWarningsBoundsNotifierProvider).value ?? [];

    // Filter out deleted warnings
    final warnings = allWarnings.where((warning) => !warning.isDeleted).toList();

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding Warnings as icons', tag: 'MAP', data: {
      'total': allWarnings.length,
      'visible': warnings.length,
      'deleted': allWarnings.length - warnings.length,
    });

    for (var warning in warnings) {
      final id = 'warning_${warning.latitude}_${warning.longitude}';
      warningById[id] = warning;

      // Get emoji for this warning type
      final emoji = POITypeConfig.getWarningEmoji(warning.type);

      // Create icon image from emoji with proper colors
      final iconImage = await MapboxMarkerUtils.createEmojiIcon(emoji, POIMarkerType.warning);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(warning.longitude, warning.latitude)),
          image: iconImage,
          iconSize: 1.5, // Optimized icon size
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await pointAnnotationManager.createMulti(pointOptions);
      AppLogger.success('Added Warning icons', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Add route hazards as warning markers (only during turn-by-turn navigation)
  static Future<void> addRouteHazards({
    required WidgetRef ref,
    required PointAnnotationManager pointAnnotationManager,
    required Map<String, CommunityWarning> warningById,
  }) async {
    final navState = ref.read(navigationProvider);
    if (!navState.isNavigating || navState.activeRoute?.routeHazards == null) {
      return;
    }

    final routeHazards = navState.activeRoute!.routeHazards!;
    if (routeHazards.isEmpty) return;

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding route hazards as markers', tag: 'MAP', data: {'count': routeHazards.length});
    for (var hazard in routeHazards) {
      final warning = hazard.warning;
      final id = 'route_hazard_${warning.latitude}_${warning.longitude}';
      warningById[id] = warning;

      // Get emoji for this warning type
      final emoji = POITypeConfig.getWarningEmoji(warning.type);

      // Create icon image from emoji with warning colors (red circle)
      final iconImage = await MapboxMarkerUtils.createEmojiIcon(emoji, POIMarkerType.warning);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(warning.longitude, warning.latitude)),
          image: iconImage,
          iconSize: 1.5, // Same size as regular warnings
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await pointAnnotationManager.createMulti(pointOptions);
      AppLogger.success('Added route hazard markers', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Add favorites and destinations markers to map
  static Future<void> addFavoritesAndDestinations({
    required WidgetRef ref,
    required PointAnnotationManager pointAnnotationManager,
    required Map<String, ({double lat, double lng, String name})> destinationsById,
    required Map<String, ({double lat, double lng, String name})> favoritesById,
  }) async {
    final favoritesVisible = ref.read(favoritesVisibilityProvider);
    if (!favoritesVisible) return;

    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) return;

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding favorites and destinations as markers', tag: 'MAP', data: {
      'destinations': userProfile.recentDestinations.length,
      'favorites': userProfile.favoriteLocations.length,
    });

    // Add destination markers (orange teardrop)
    for (var destination in userProfile.recentDestinations) {
      final id = 'destination_${destination.latitude}_${destination.longitude}';
      destinationsById[id] = (lat: destination.latitude, lng: destination.longitude, name: destination.name);

      final iconImage = await MapboxMarkerUtils.createFavoritesIcon(isDestination: true);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(destination.longitude, destination.latitude)),
          image: iconImage,
          iconSize: 1.5,
          iconAnchor: IconAnchor.CENTER,
        ),
      );
    }

    // Add favorite markers (yellow star)
    for (var favorite in userProfile.favoriteLocations) {
      final id = 'favorite_${favorite.latitude}_${favorite.longitude}';
      favoritesById[id] = (lat: favorite.latitude, lng: favorite.longitude, name: favorite.name);

      final iconImage = await MapboxMarkerUtils.createFavoritesIcon(isDestination: false);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(favorite.longitude, favorite.latitude)),
          image: iconImage,
          iconSize: 1.5,
          iconAnchor: IconAnchor.CENTER,
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await pointAnnotationManager.createMulti(pointOptions);
      AppLogger.success('Added favorites/destinations markers', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }
}
