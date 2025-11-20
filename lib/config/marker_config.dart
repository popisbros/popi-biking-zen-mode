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
  static const double poiCircleRadius = 10.0;

  /// User location marker size (both 2D and 3D maps)
  static const double userLocationSize = 12.0;

  /// Circle stroke width (outline)
  static const double circleStrokeWidth = 2.0;

  // ============================================================================
  // UNIFIED COLORS (2D & 3D Maps)
  // ============================================================================

  /// OSM POI colors (bike shops, water, toilets, etc.)
  static const Color osmPoiFillColor = Color(0xE6BBDEFB); // blue.shade100 with ~90% opacity
  static const Color osmPoiBorderColor = Colors.blue;

  /// Warning/Hazard colors (reported dangers, road closures, etc.)
  static const Color warningFillColor = Color(0xE6FFCDD2); // red.shade100 with ~90% opacity
  static const Color warningBorderColor = Colors.red;

  /// User location marker colors
  static const Color userLocationFillColor = Color(0xE6CE93D8); // purple with ~90% opacity
  static const Color userLocationBorderColor = Color(0xFF9C27B0); // Colors.purple

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
    final color = getFillColorForType(type);
    return ((color.a * 255).toInt() << 24) |
           ((color.r * 255).toInt() << 16) |
           ((color.g * 255).toInt() << 8) |
           (color.b * 255).toInt();
  }

  /// Get border color value (int) for Mapbox
  static int getBorderColorValueForType(POIMarkerType type) {
    final color = getBorderColorForType(type);
    return ((color.a * 255).toInt() << 24) |
           ((color.r * 255).toInt() << 16) |
           ((color.g * 255).toInt() << 8) |
           (color.b * 255).toInt();
  }
}

/// POI Marker Types
enum POIMarkerType {
  osmPOI,
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
//   width: MarkerConfig.getRadiusForType(POIMarkerType.osmPOI) * 2,
//   height: MarkerConfig.getRadiusForType(POIMarkerType.osmPOI) * 2,
//   child: Container(
//     decoration: BoxDecoration(
//       color: MarkerConfig.getFillColorForType(POIMarkerType.osmPOI),
//       shape: BoxShape.circle,
//       border: Border.all(
//         color: MarkerConfig.getBorderColorForType(POIMarkerType.osmPOI),
//         width: MarkerConfig.circleStrokeWidth,
//       ),
//     ),
//   ),
// )
// ```
//
// ============================================================================
