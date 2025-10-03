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
  // UNIFIED CIRCLE MARKER SIZES (2D & 3D Maps)
  // ============================================================================

  /// Standard size for all POI circles (both 2D and 3D maps)
  static const double poiCircleRadius = 20.0;

  /// User location marker size (both 2D and 3D maps)
  static const double userLocationSize = 12.0;

  /// Circle stroke width (outline)
  static const double circleStrokeWidth = 2.0;

  // ============================================================================
  // UNIFIED COLORS (2D & 3D Maps)
  // ============================================================================

  /// OSM POI colors (bike shops, water, toilets, etc.)
  static const Color osmPoiFillColor = Colors.blue;
  static const Color osmPoiBorderColor = Colors.blue;

  /// Community POI colors (user-created points of interest)
  static const Color communityPoiFillColor = Color(0xFFC8E6C9); // green.shade100
  static const Color communityPoiBorderColor = Colors.green;

  /// Warning/Hazard colors (reported dangers, road closures, etc.)
  static const Color warningFillColor = Color(0xFFFFCDD2); // red.shade100
  static const Color warningBorderColor = Colors.red;

  /// User location marker colors
  static const Color userLocationFillColor = Color(0x33448AFF); // blue.withOpacity(0.2)
  static const Color userLocationBorderColor = Color(0xFF2196F3); // Colors.blue

  /// Circle stroke color (outline) - white for better visibility
  static const Color circleStrokeColor = Colors.white;

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Get fill color for POI type
  static Color getFillColorForType(POIMarkerType type) {
    switch (type) {
      case POIMarkerType.osmPOI:
        return osmPoiFillColor;
      case POIMarkerType.communityPOI:
        return communityPoiFillColor;
      case POIMarkerType.warning:
        return warningFillColor;
      case POIMarkerType.userLocation:
        return userLocationFillColor;
    }
  }

  /// Get border color for POI type
  static Color getBorderColorForType(POIMarkerType type) {
    switch (type) {
      case POIMarkerType.osmPOI:
        return osmPoiBorderColor;
      case POIMarkerType.communityPOI:
        return communityPoiBorderColor;
      case POIMarkerType.warning:
        return warningBorderColor;
      case POIMarkerType.userLocation:
        return userLocationBorderColor;
    }
  }

  /// Get circle radius for POI type
  static double getRadiusForType(POIMarkerType type) {
    if (type == POIMarkerType.userLocation) {
      return userLocationSize;
    }
    return poiCircleRadius; // All POI types use same size
  }

  /// Get fill color value (int) for Mapbox
  static int getFillColorValueForType(POIMarkerType type) {
    return getFillColorForType(type).value;
  }

  /// Get border color value (int) for Mapbox
  static int getBorderColorValueForType(POIMarkerType type) {
    return getBorderColorForType(type).value;
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
// 3D Map (Mapbox) - Circle markers:
// ```dart
// CircleAnnotationOptions(
//   geometry: Point(coordinates: Position(lng, lat)),
//   circleRadius: MarkerConfig.getRadiusForType(POIMarkerType.osmPOI),
//   circleColor: MarkerConfig.getFillColorValueForType(POIMarkerType.osmPOI),
//   circleStrokeWidth: MarkerConfig.circleStrokeWidth,
//   circleStrokeColor: MarkerConfig.getBorderColorValueForType(POIMarkerType.osmPOI),
// )
// ```
//
// 2D Map (flutter_map) - Circle markers:
// ```dart
// Marker(
//   point: LatLng(lat, lng),
//   width: MarkerConfig.getRadiusForType(POIMarkerType.communityPOI) * 2,
//   height: MarkerConfig.getRadiusForType(POIMarkerType.communityPOI) * 2,
//   child: Container(
//     decoration: BoxDecoration(
//       color: MarkerConfig.getFillColorForType(POIMarkerType.communityPOI),
//       shape: BoxShape.circle,
//       border: Border.all(
//         color: MarkerConfig.getBorderColorForType(POIMarkerType.communityPOI),
//         width: MarkerConfig.circleStrokeWidth,
//       ),
//     ),
//   ),
// )
// ```
//
// ============================================================================
