import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Geospatial utility functions for distance and bearing calculations
///
/// Consolidates duplicated geo calculations from map screens
class GeoUtils {
  // Private constructor to prevent instantiation
  GeoUtils._();

  /// Earth's radius in meters
  static const double earthRadiusMeters = 6371000.0;

  /// Calculate distance between two geographic coordinates using Haversine formula
  ///
  /// Returns distance in meters
  ///
  /// Example:
  /// ```dart
  /// final distance = GeoUtils.calculateDistance(48.8566, 2.3522, 51.5074, -0.1278);
  /// print('Paris to London: ${distance / 1000}km');
  /// ```
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // Convert to radians
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;

    // Haversine formula
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Calculate distance between two LatLng points
  ///
  /// Convenience method that accepts LatLng objects instead of separate coordinates
  ///
  /// Returns distance in meters
  static double calculateDistanceLatLng(LatLng point1, LatLng point2) {
    return calculateDistance(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Calculate bearing between two points
  ///
  /// Returns bearing in degrees (0° = North, 90° = East, 180° = South, 270° = West)
  /// Result is normalized to 0-360 range
  ///
  /// Example:
  /// ```dart
  /// final start = LatLng(48.8566, 2.3522); // Paris
  /// final end = LatLng(51.5074, -0.1278);  // London
  /// final bearing = GeoUtils.calculateBearing(start, end);
  /// print('Heading: ${bearing.toStringAsFixed(0)}°');
  /// ```
  static double calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final dLon = (end.longitude - start.longitude) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;

    // Normalize to 0-360
    return (bearing + 360) % 360;
  }

  /// Calculate the bounding box for a given center point and radius
  ///
  /// Returns a map with minLat, maxLat, minLon, maxLon
  /// Useful for API queries that require geographic bounds
  ///
  /// Parameters:
  /// - center: Center point of the bounding box
  /// - radiusMeters: Radius in meters
  ///
  /// Example:
  /// ```dart
  /// final center = LatLng(48.8566, 2.3522);
  /// final bounds = GeoUtils.calculateBounds(center, 5000); // 5km radius
  /// ```
  static Map<String, double> calculateBounds(LatLng center, double radiusMeters) {
    // Approximate degrees per meter (varies by latitude)
    final latDegPerMeter = 1 / 111320.0;
    final lonDegPerMeter = 1 / (111320.0 * math.cos(center.latitude * math.pi / 180));

    final latDelta = radiusMeters * latDegPerMeter;
    final lonDelta = radiusMeters * lonDegPerMeter;

    return {
      'minLat': center.latitude - latDelta,
      'maxLat': center.latitude + latDelta,
      'minLon': center.longitude - lonDelta,
      'maxLon': center.longitude + lonDelta,
    };
  }

  /// Check if a point is within a bounding box
  ///
  /// Returns true if the point is inside the box
  static bool isPointInBounds(
    LatLng point,
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
  ) {
    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLon &&
        point.longitude <= maxLon;
  }

  /// Calculate the midpoint between two geographic coordinates
  ///
  /// Useful for centering map views between two points
  static LatLng calculateMidpoint(LatLng point1, LatLng point2) {
    final lat1 = point1.latitude * math.pi / 180;
    final lon1 = point1.longitude * math.pi / 180;
    final lat2 = point2.latitude * math.pi / 180;
    final dLon = (point2.longitude - point1.longitude) * math.pi / 180;

    final bX = math.cos(lat2) * math.cos(dLon);
    final bY = math.cos(lat2) * math.sin(dLon);

    final lat3 = math.atan2(
      math.sin(lat1) + math.sin(lat2),
      math.sqrt((math.cos(lat1) + bX) * (math.cos(lat1) + bX) + bY * bY),
    );
    final lon3 = lon1 + math.atan2(bY, math.cos(lat1) + bX);

    return LatLng(
      lat3 * 180 / math.pi,
      lon3 * 180 / math.pi,
    );
  }

  /// Format distance for display
  ///
  /// Converts meters to human-readable format:
  /// - < 1000m: "500m"
  /// - >= 1000m: "1.5km"
  ///
  /// Parameters:
  /// - distanceMeters: Distance in meters
  /// - decimals: Number of decimal places for kilometers (default: 1)
  static String formatDistance(double distanceMeters, {int decimals = 1}) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m';
    } else {
      final km = distanceMeters / 1000;
      return '${km.toStringAsFixed(decimals)}km';
    }
  }

  /// Format bearing for display
  ///
  /// Converts degrees to cardinal direction (N, NE, E, SE, S, SW, W, NW)
  ///
  /// Example:
  /// ```dart
  /// print(GeoUtils.formatBearing(45));  // "NE"
  /// print(GeoUtils.formatBearing(180)); // "S"
  /// ```
  static String formatBearing(double bearing) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((bearing + 22.5) / 45).floor() % 8;
    return directions[index];
  }
}
