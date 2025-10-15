import 'package:latlong2/latlong.dart';
import '../models/community_warning.dart';
import '../utils/app_logger.dart';

/// Represents a hazard detected on or near the route
class RouteHazard {
  final CommunityWarning warning;
  final double distanceAlongRoute; // meters from route start
  final double distanceFromRouteLine; // perpendicular distance from route
  final LatLng closestPointOnRoute;

  const RouteHazard({
    required this.warning,
    required this.distanceAlongRoute,
    required this.distanceFromRouteLine,
    required this.closestPointOnRoute,
  });

  /// Get distance from current position to this hazard along the route
  double getDistanceFromPosition(LatLng currentPosition, double currentDistanceAlongRoute) {
    return distanceAlongRoute - currentDistanceAlongRoute;
  }

  @override
  String toString() {
    return 'RouteHazard(${warning.type}, distance: ${distanceAlongRoute.toStringAsFixed(0)}m, '
        'offset: ${distanceFromRouteLine.toStringAsFixed(0)}m)';
  }
}

/// Service for detecting community hazards on or near a route
class RouteHazardDetector {
  static const Distance _distance = Distance();

  /// Buffer distance from route line to consider hazards (meters)
  static const double defaultBufferMeters = 75.0; // 75m corridor on each side

  /// Detect hazards that are on or near the route
  ///
  /// Returns list of RouteHazard sorted by distance along route
  static List<RouteHazard> detectHazardsOnRoute({
    required List<LatLng> routePoints,
    required List<CommunityWarning> allHazards,
    double bufferMeters = defaultBufferMeters,
  }) {
    if (routePoints.isEmpty || allHazards.isEmpty) {
      return [];
    }

    AppLogger.debug('Detecting hazards on route', tag: 'HAZARDS', data: {
      'routePoints': routePoints.length,
      'totalHazards': allHazards.length,
      'buffer': '${bufferMeters}m',
    });

    final detectedHazards = <RouteHazard>[];

    // Pre-filter: Get route bounding box for quick filtering
    final bounds = _getRouteBounds(routePoints);
    final candidateHazards = allHazards.where((hazard) {
      return hazard.latitude >= bounds.minLat &&
             hazard.latitude <= bounds.maxLat &&
             hazard.longitude >= bounds.minLon &&
             hazard.longitude <= bounds.maxLon;
    }).toList();

    AppLogger.debug('Candidate hazards in bounds', tag: 'HAZARDS', data: {
      'candidates': candidateHazards.length,
    });

    // For each hazard, find closest point on route
    for (final hazard in candidateHazards) {
      final hazardPos = LatLng(hazard.latitude, hazard.longitude);

      // Find closest segment and point on route
      final result = _findClosestPointOnRoute(hazardPos, routePoints);

      if (result.distanceFromRoute <= bufferMeters) {
        detectedHazards.add(RouteHazard(
          warning: hazard,
          distanceAlongRoute: result.distanceAlongRoute,
          distanceFromRouteLine: result.distanceFromRoute,
          closestPointOnRoute: result.closestPoint,
        ));
      }
    }

    // Sort by distance along route
    detectedHazards.sort((a, b) => a.distanceAlongRoute.compareTo(b.distanceAlongRoute));

    AppLogger.success('Hazards detected on route', tag: 'HAZARDS', data: {
      'count': detectedHazards.length,
    });

    for (final hazard in detectedHazards) {
      AppLogger.debug('  - ${hazard.warning.type}: ${hazard.warning.title}',
        tag: 'HAZARDS',
        data: {
          'distanceAlongRoute': '${hazard.distanceAlongRoute.toStringAsFixed(0)}m',
          'offsetFromRoute': '${hazard.distanceFromRouteLine.toStringAsFixed(0)}m',
        }
      );
    }

    return detectedHazards;
  }

  /// Get upcoming hazards from current position
  static List<RouteHazard> getUpcomingHazards({
    required List<RouteHazard> allRouteHazards,
    required LatLng currentPosition,
    required List<LatLng> routePoints,
    int maxHazards = 5,
  }) {
    if (allRouteHazards.isEmpty) return [];

    // Calculate current distance along route
    final currentResult = _findClosestPointOnRoute(currentPosition, routePoints);
    final currentDistanceAlongRoute = currentResult.distanceAlongRoute;

    // Filter to upcoming hazards only
    final upcoming = allRouteHazards
        .where((hazard) => hazard.distanceAlongRoute > currentDistanceAlongRoute)
        .take(maxHazards)
        .toList();

    return upcoming;
  }

  /// Find closest point on route to given position
  static _ClosestPointResult _findClosestPointOnRoute(
    LatLng point,
    List<LatLng> routePoints,
  ) {
    double minDistance = double.infinity;
    LatLng closestPoint = routePoints.first;
    double distanceAlongRoute = 0.0;
    double accumulatedDistance = 0.0;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final segmentStart = routePoints[i];
      final segmentEnd = routePoints[i + 1];
      final segmentLength = _distance.as(LengthUnit.Meter, segmentStart, segmentEnd);

      // Find closest point on this segment
      final result = _closestPointOnSegment(point, segmentStart, segmentEnd);

      if (result.distance < minDistance) {
        minDistance = result.distance;
        closestPoint = result.point;

        // Calculate distance along route to this closest point
        final distanceToPointOnSegment = _distance.as(
          LengthUnit.Meter,
          segmentStart,
          result.point,
        );
        distanceAlongRoute = accumulatedDistance + distanceToPointOnSegment;
      }

      accumulatedDistance += segmentLength;
    }

    return _ClosestPointResult(
      closestPoint: closestPoint,
      distanceFromRoute: minDistance,
      distanceAlongRoute: distanceAlongRoute,
    );
  }

  /// Find closest point on a line segment
  static _PointOnSegment _closestPointOnSegment(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    // Vector from segment start to end
    final dx = segmentEnd.longitude - segmentStart.longitude;
    final dy = segmentEnd.latitude - segmentStart.latitude;

    // If segment is a point
    if (dx == 0 && dy == 0) {
      return _PointOnSegment(
        point: segmentStart,
        distance: _distance.as(LengthUnit.Meter, point, segmentStart),
      );
    }

    // Vector from segment start to point
    final px = point.longitude - segmentStart.longitude;
    final py = point.latitude - segmentStart.latitude;

    // Project point onto segment line (parametric t)
    final t = ((px * dx + py * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);

    // Closest point on segment
    final closestLat = segmentStart.latitude + t * dy;
    final closestLon = segmentStart.longitude + t * dx;
    final closestPoint = LatLng(closestLat, closestLon);

    return _PointOnSegment(
      point: closestPoint,
      distance: _distance.as(LengthUnit.Meter, point, closestPoint),
    );
  }

  /// Get bounding box for route
  static _RouteBounds _getRouteBounds(List<LatLng> routePoints) {
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLon = routePoints.first.longitude;
    double maxLon = routePoints.first.longitude;

    for (final point in routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    // Add small buffer to bounds
    const buffer = 0.01; // ~1km buffer
    return _RouteBounds(
      minLat: minLat - buffer,
      maxLat: maxLat + buffer,
      minLon: minLon - buffer,
      maxLon: maxLon + buffer,
    );
  }
}

/// Internal result classes
class _ClosestPointResult {
  final LatLng closestPoint;
  final double distanceFromRoute;
  final double distanceAlongRoute;

  _ClosestPointResult({
    required this.closestPoint,
    required this.distanceFromRoute,
    required this.distanceAlongRoute,
  });
}

class _PointOnSegment {
  final LatLng point;
  final double distance;

  _PointOnSegment({required this.point, required this.distance});
}

class _RouteBounds {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  _RouteBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });
}
