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

  /// Project a point onto a line segment (snap to closest point on segment)
  ///
  /// Calculates the closest point on the line segment from [segmentStart] to [segmentEnd]
  /// to the given [point]. This is used for map matching / snap-to-route.
  ///
  /// Returns the closest point on the segment (may be start, end, or anywhere in between)
  ///
  /// Example:
  /// ```dart
  /// final point = LatLng(48.8566, 2.3522);
  /// final segStart = LatLng(48.8550, 2.3500);
  /// final segEnd = LatLng(48.8580, 2.3550);
  /// final snapped = GeoUtils.projectPointOnSegment(point, segStart, segEnd);
  /// ```
  static LatLng projectPointOnSegment(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    // Vector from segment start to point
    final dx = point.latitude - segmentStart.latitude;
    final dy = point.longitude - segmentStart.longitude;

    // Vector from segment start to segment end
    final sx = segmentEnd.latitude - segmentStart.latitude;
    final sy = segmentEnd.longitude - segmentStart.longitude;

    // Calculate dot product and segment length squared
    final dotProduct = dx * sx + dy * sy;
    final segmentLengthSquared = sx * sx + sy * sy;

    // Handle degenerate case (segment has zero length)
    if (segmentLengthSquared == 0) {
      return segmentStart;
    }

    // Calculate parameter t (0 to 1) representing position on segment
    // t = 0 means closest point is segmentStart
    // t = 1 means closest point is segmentEnd
    // 0 < t < 1 means closest point is somewhere in between
    final t = (dotProduct / segmentLengthSquared).clamp(0.0, 1.0);

    // Calculate the projected point
    final projectedLat = segmentStart.latitude + t * sx;
    final projectedLon = segmentStart.longitude + t * sy;

    return LatLng(projectedLat, projectedLon);
  }

  /// Snap GPS position to the nearest point on a route
  ///
  /// Finds the closest point on the route polyline to the given GPS position.
  /// Only searches within a window of route points around [currentSegmentIndex]
  /// for performance optimization.
  ///
  /// Parameters:
  /// - gpsPosition: Current GPS position
  /// - routePoints: Full route polyline
  /// - currentSegmentIndex: Current position on route (for performance)
  /// - maxSnapDistanceMeters: Maximum distance to snap (default 20m)
  /// - searchWindowSize: Number of points to search before/after current (default 50)
  ///
  /// Returns the snapped position, or null if GPS is too far from route
  ///
  /// Example:
  /// ```dart
  /// final snapped = GeoUtils.snapToRoute(
  ///   gpsPosition,
  ///   routePoints,
  ///   currentSegmentIndex: 100,
  ///   maxSnapDistanceMeters: 20,
  /// );
  /// ```
  static LatLng? snapToRoute(
    LatLng gpsPosition,
    List<LatLng> routePoints,
    int currentSegmentIndex, {
    double maxSnapDistanceMeters = 20.0,
    int searchWindowSize = 50,
  }) {
    if (routePoints.length < 2) return null;

    // Define search window (current segment ± windowSize points)
    final startIdx = math.max(0, currentSegmentIndex - searchWindowSize);
    final endIdx = math.min(routePoints.length - 1, currentSegmentIndex + searchWindowSize);

    LatLng? closestPoint;
    double minDistance = double.infinity;

    // Check each segment in the search window
    for (int i = startIdx; i < endIdx; i++) {
      final segmentStart = routePoints[i];
      final segmentEnd = routePoints[i + 1];

      // Project GPS position onto this segment
      final projected = projectPointOnSegment(gpsPosition, segmentStart, segmentEnd);

      // Calculate distance from GPS to projected point
      final distance = calculateDistanceLatLng(gpsPosition, projected);

      if (distance < minDistance) {
        minDistance = distance;
        closestPoint = projected;
      }
    }

    // Only return snapped position if within threshold
    if (minDistance <= maxSnapDistanceMeters) {
      return closestPoint;
    }

    return null; // Too far from route, don't snap
  }
}
