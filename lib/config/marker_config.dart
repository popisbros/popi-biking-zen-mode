import 'package:flutter/material.dart';

/// Marker Configuration for Maps (2D & 3D)
///
/// This file centralizes all marker/icon configuration for consistency
/// across both 2D (flutter_map) and 3D (Mapbox) map implementations.
///
/// To change marker appearance, edit the values in this file.
class MarkerConfig {
  // Private constructor to prevent instantiation
  MarkerConfig._();

  // ============================================================================
  // CIRCLE MARKER SIZES (3D Map)
  // ============================================================================

  /// Standard size for all POI circles in 3D map
  /// Recommended: 8-12 pixels
  static const double poiCircleRadius = 10.0;

  /// User location marker size in 3D map
  /// Note: Mapbox's built-in puck size is controlled by LocationComponentSettings
  /// This value is for reference/documentation only
  static const double userLocationSize = 12.0;

  /// Circle stroke width (outline)
  static const double circleStrokeWidth = 2.0;

  // ============================================================================
  // COLORS
  // ============================================================================

  /// OSM POI color (bike shops, water, toilets, etc.)
  static const Color osmPoiColor = Colors.blue;

  /// Community POI color (user-created points of interest)
  static const Color communityPoiColor = Colors.green;

  /// Warning/Hazard color (reported dangers, road closures, etc.)
  static const Color warningColor = Colors.red;

  /// User location marker color
  static const Color userLocationColor = Color(0xFFFFD700); // Gold/Yellow

  /// Circle stroke color (outline)
  static const Color circleStrokeColor = Colors.white;

  // ============================================================================
  // 2D MAP MARKER SIZES
  // ============================================================================

  /// Marker size for 2D map (flutter_map)
  /// These are dimensions for the marker widget
  static const double marker2DWidth = 30.0;
  static const double marker2DHeight = 40.0;

  /// Icon size inside 2D markers
  static const double marker2DIconSize = 20.0;

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Get color for POI type
  static Color getColorForType(POIMarkerType type) {
    switch (type) {
      case POIMarkerType.osmPOI:
        return osmPoiColor;
      case POIMarkerType.communityPOI:
        return communityPoiColor;
      case POIMarkerType.warning:
        return warningColor;
      case POIMarkerType.userLocation:
        return userLocationColor;
    }
  }

  /// Get circle radius for POI type (3D map)
  static double getRadiusForType(POIMarkerType type) {
    if (type == POIMarkerType.userLocation) {
      return userLocationSize;
    }
    return poiCircleRadius; // All POI types use same size
  }

  /// Get color value (int) for Mapbox
  static int getColorValueForType(POIMarkerType type) {
    return getColorForType(type).value;
  }
}

/// POI Marker Types
enum POIMarkerType {
  osmPOI,
  communityPOI,
  warning,
  userLocation,
}

// ============================================================================
// USAGE EXAMPLES
// ============================================================================
//
// 3D Map (Mapbox):
// ```dart
// CircleAnnotationOptions(
//   geometry: Point(coordinates: Position(lng, lat)),
//   circleRadius: MarkerConfig.poiCircleRadius,
//   circleColor: MarkerConfig.getColorValueForType(POIMarkerType.osmPOI),
//   circleStrokeWidth: MarkerConfig.circleStrokeWidth,
//   circleStrokeColor: MarkerConfig.circleStrokeColor.value,
// )
// ```
//
// 2D Map (flutter_map):
// ```dart
// Marker(
//   point: LatLng(lat, lng),
//   width: MarkerConfig.marker2DWidth,
//   height: MarkerConfig.marker2DHeight,
//   child: Icon(
//     Icons.location_on,
//     size: MarkerConfig.marker2DIconSize,
//     color: MarkerConfig.getColorForType(POIMarkerType.communityPOI),
//   ),
// )
// ```
//
// ============================================================================
