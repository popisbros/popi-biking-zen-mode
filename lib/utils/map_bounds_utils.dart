import 'package:flutter_map/flutter_map.dart';
import '../providers/osm_poi_provider.dart';
import 'app_logger.dart';

/// Map bounds calculation utilities
///
/// Provides smart reload logic for efficient map data loading:
/// - Extended bounds (3x3 area) for smooth panning
/// - Reload trigger bounds (10% buffer) to avoid excessive reloads
/// - Smart reload decision based on visible area
class MapBoundsUtils {
  // Private constructor to prevent instantiation
  MapBoundsUtils._();

  /// Calculate extended bounds (3x3 of visible area) for smooth panning
  ///
  /// Loads data for a larger area than visible to prevent constant reloading
  /// as the user pans around. The extended area is 3x the visible area in
  /// both dimensions (9x total area).
  ///
  /// Parameters:
  /// - visibleBounds: Current visible map bounds
  ///
  /// Returns: Extended bounding box for data loading
  static BoundingBox calculateExtendedBounds(LatLngBounds visibleBounds) {
    final latDiff = visibleBounds.north - visibleBounds.south;
    final lngDiff = visibleBounds.east - visibleBounds.west;

    final latExtension = latDiff;
    final lngExtension = lngDiff;

    final bbox = BoundingBox(
      south: visibleBounds.south - latExtension,
      west: visibleBounds.west - lngExtension,
      north: visibleBounds.north + latExtension,
      east: visibleBounds.east + lngExtension,
    );

    AppLogger.map('Extended bounds calculated', data: {
      'visible_S': visibleBounds.south.toStringAsFixed(4),
      'visible_N': visibleBounds.north.toStringAsFixed(4),
      'visible_W': visibleBounds.west.toStringAsFixed(4),
      'visible_E': visibleBounds.east.toStringAsFixed(4),
      'extended_S': bbox.south.toStringAsFixed(4),
      'extended_N': bbox.north.toStringAsFixed(4),
      'extended_W': bbox.west.toStringAsFixed(4),
      'extended_E': bbox.east.toStringAsFixed(4),
    });

    return bbox;
  }

  /// Calculate reload trigger bounds (10% buffer zone)
  ///
  /// Creates an inner buffer zone. When the visible area moves outside
  /// this zone, it triggers a reload. The 10% buffer prevents reloads
  /// from happening too frequently.
  ///
  /// Parameters:
  /// - loadedBounds: The bounds that were used for the last data load
  ///
  /// Returns: Inner trigger bounds (10% smaller on each side)
  static BoundingBox calculateReloadTriggerBounds(BoundingBox loadedBounds) {
    final latDiff = loadedBounds.north - loadedBounds.south;
    final lngDiff = loadedBounds.east - loadedBounds.west;

    final latBuffer = latDiff * 0.1;
    final lngBuffer = lngDiff * 0.1;

    return BoundingBox(
      south: loadedBounds.south + latBuffer,
      west: loadedBounds.west + lngBuffer,
      north: loadedBounds.north - latBuffer,
      east: loadedBounds.east - lngBuffer,
    );
  }

  /// Check if we should reload data (smart reload logic)
  ///
  /// Determines if the visible area has moved far enough to warrant
  /// reloading map data. Returns true if:
  /// - No data has been loaded yet (reloadTriggerBounds is null)
  /// - Visible area extends beyond the reload trigger bounds
  ///
  /// Parameters:
  /// - visibleBounds: Current visible map bounds
  /// - reloadTriggerBounds: Inner buffer zone (null if no data loaded)
  ///
  /// Returns: true if data should be reloaded, false to use cached data
  static bool shouldReloadData(LatLngBounds visibleBounds, BoundingBox? reloadTriggerBounds) {
    if (reloadTriggerBounds == null) {
      AppLogger.map('First load - should reload = TRUE');
      return true;
    }

    final shouldReload = visibleBounds.south < reloadTriggerBounds.south ||
        visibleBounds.north > reloadTriggerBounds.north ||
        visibleBounds.west < reloadTriggerBounds.west ||
        visibleBounds.east > reloadTriggerBounds.east;

    AppLogger.map('Should reload check', data: {'shouldReload': shouldReload});
    if (!shouldReload) {
      AppLogger.debug('Still within buffer zone, skipping reload', tag: 'MAP');
    }

    return shouldReload;
  }
}
