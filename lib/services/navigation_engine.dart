import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/maneuver_instruction.dart';
import '../utils/app_logger.dart';

/// Engine for calculating navigation instructions and tracking position along route
class NavigationEngine {
  static const Distance _distance = Distance();

  // Thresholds
  static const double _offRouteThresholdMeters = 50.0; // 50m off route = alert
  static const double _sharpTurnAngle = 120.0; // degrees
  static const double _mediumTurnAngle = 45.0; // degrees
  static const double _slightTurnAngle = 20.0; // degrees
  static const double _minSegmentLengthMeters = 10.0; // ignore very short segments

  /// Find the closest point index on route to current position
  /// Returns the index of the route point that is closest
  static int findClosestPointIndex(LatLng current, List<LatLng> route) {
    if (route.isEmpty) return 0;

    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < route.length; i++) {
      final distance = _distance.as(
        LengthUnit.Meter,
        current,
        route[i],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  /// Find the closest segment on route to current position
  /// Returns the index of the starting point of the closest segment
  static int findClosestSegment(LatLng current, List<LatLng> route) {
    if (route.length < 2) return 0;

    double minDistance = double.infinity;
    int closestSegment = 0;

    for (int i = 0; i < route.length - 1; i++) {
      final distance = _distanceToSegment(
        current,
        route[i],
        route[i + 1],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestSegment = i;
      }
    }

    return closestSegment;
  }

  /// Calculate perpendicular distance from point to line segment
  static double _distanceToSegment(LatLng point, LatLng segmentStart, LatLng segmentEnd) {
    final distanceToStart = _distance.as(LengthUnit.Meter, point, segmentStart);
    final distanceToEnd = _distance.as(LengthUnit.Meter, point, segmentEnd);
    final segmentLength = _distance.as(LengthUnit.Meter, segmentStart, segmentEnd);

    // If segment is very short, return distance to start
    if (segmentLength < 1.0) return distanceToStart;

    // Use closest endpoint if point is before/after segment
    final minEndpointDistance = math.min(distanceToStart, distanceToEnd);

    // Calculate perpendicular distance using cross product
    final lat1 = segmentStart.latitude;
    final lon1 = segmentStart.longitude;
    final lat2 = segmentEnd.latitude;
    final lon2 = segmentEnd.longitude;
    final latP = point.latitude;
    final lonP = point.longitude;

    final numerator = ((lat2 - lat1) * (lon1 - lonP) - (lon2 - lon1) * (lat1 - latP)).abs();
    final denominator = math.sqrt(math.pow(lat2 - lat1, 2) + math.pow(lon2 - lon1, 2));

    if (denominator < 0.0000001) return distanceToStart;

    final perpDistance = (numerator / denominator) * 111320; // degrees to meters

    return math.min(perpDistance, minEndpointDistance);
  }

  /// Check if current position is off the route
  static bool isOffRoute(LatLng current, List<LatLng> route) {
    if (route.isEmpty) return false;

    final closestSegment = findClosestSegment(current, route);
    final distance = _distanceToSegment(
      current,
      route[closestSegment],
      route[math.min(closestSegment + 1, route.length - 1)],
    );

    return distance > _offRouteThresholdMeters;
  }

  /// Calculate total remaining distance from current position to end
  static double calculateRemainingDistance(
    LatLng current,
    List<LatLng> route,
    int currentSegmentIndex,
  ) {
    if (route.isEmpty || currentSegmentIndex >= route.length) return 0;

    // Distance to next route point
    double remaining = _distance.as(
      LengthUnit.Meter,
      current,
      route[currentSegmentIndex],
    );

    // Add distances for all remaining segments
    for (int i = currentSegmentIndex; i < route.length - 1; i++) {
      remaining += _distance.as(
        LengthUnit.Meter,
        route[i],
        route[i + 1],
      );
    }

    return remaining;
  }

  /// Detect all maneuvers along the route
  /// Analyzes route geometry to identify turns
  static List<ManeuverInstruction> detectManeuvers(List<LatLng> route) {
    if (route.length < 3) {
      // Not enough points for maneuver detection
      if (route.length == 2) {
        return [
          ManeuverInstruction(
            type: ManeuverType.depart,
            instruction: 'Start your route',
            distanceMeters: 0,
            location: route[0],
            routePointIndex: 0,
          ),
          ManeuverInstruction(
            type: ManeuverType.arrive,
            instruction: 'You have arrived at your destination',
            distanceMeters: 0,
            location: route[1],
            routePointIndex: 1,
          ),
        ];
      }
      return [];
    }

    final maneuvers = <ManeuverInstruction>[];

    // Add departure maneuver
    maneuvers.add(
      ManeuverInstruction(
        type: ManeuverType.depart,
        instruction: 'Start your route',
        distanceMeters: 0,
        location: route[0],
        routePointIndex: 0,
      ),
    );

    // Analyze route geometry for turns
    for (int i = 1; i < route.length - 1; i++) {
      final before = route[i - 1];
      final current = route[i];
      final after = route[i + 1];

      // Skip if segments are too short
      final segmentBefore = _distance.as(LengthUnit.Meter, before, current);
      final segmentAfter = _distance.as(LengthUnit.Meter, current, after);

      if (segmentBefore < _minSegmentLengthMeters || segmentAfter < _minSegmentLengthMeters) {
        continue;
      }

      // Calculate bearing change
      final bearingIn = _calculateBearing(before, current);
      final bearingOut = _calculateBearing(current, after);
      final bearingChange = _normalizeBearing(bearingOut - bearingIn);

      // Detect maneuver type based on angle
      final maneuverType = _detectManeuverType(bearingChange);

      if (maneuverType != ManeuverType.straight) {
        // Calculate distance from start to this maneuver
        double distanceFromStart = 0;
        for (int j = 0; j < i; j++) {
          distanceFromStart += _distance.as(LengthUnit.Meter, route[j], route[j + 1]);
        }

        maneuvers.add(
          ManeuverInstruction(
            type: maneuverType,
            instruction: _generateInstruction(maneuverType),
            distanceMeters: distanceFromStart,
            location: current,
            routePointIndex: i,
          ),
        );

        AppLogger.debug('Maneuver detected', tag: 'NAV_ENGINE', data: {
          'type': maneuverType.name,
          'index': i,
          'bearingChange': bearingChange.toStringAsFixed(1),
        });
      }
    }

    // Add arrival maneuver
    final totalDistance = calculateRemainingDistance(route[0], route, 0);
    maneuvers.add(
      ManeuverInstruction(
        type: ManeuverType.arrive,
        instruction: 'You have arrived at your destination',
        distanceMeters: totalDistance,
        location: route.last,
        routePointIndex: route.length - 1,
      ),
    );

    AppLogger.success('Detected ${maneuvers.length} maneuvers', tag: 'NAV_ENGINE');
    return maneuvers;
  }

  /// Calculate bearing between two points (0-360 degrees, 0 = North)
  static double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitudeInRad;
    final lat2 = to.latitudeInRad;
    final dLon = to.longitudeInRad - from.longitudeInRad;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  /// Normalize bearing change to -180 to +180 range
  static double _normalizeBearing(double bearing) {
    while (bearing > 180) {
      bearing -= 360;
    }
    while (bearing < -180) {
      bearing += 360;
    }
    return bearing;
  }

  /// Detect maneuver type from bearing change
  static ManeuverType _detectManeuverType(double bearingChange) {
    final absChange = bearingChange.abs();

    // Straight (minimal direction change)
    if (absChange < _slightTurnAngle) {
      return ManeuverType.straight;
    }

    // U-turn
    if (absChange > 150) {
      return ManeuverType.uTurn;
    }

    // Left turns
    if (bearingChange > 0) {
      if (absChange > _sharpTurnAngle) {
        return ManeuverType.sharpLeft;
      } else if (absChange > _mediumTurnAngle) {
        return ManeuverType.turnLeft;
      } else {
        return ManeuverType.slightLeft;
      }
    }
    // Right turns
    else {
      if (absChange > _sharpTurnAngle) {
        return ManeuverType.sharpRight;
      } else if (absChange > _mediumTurnAngle) {
        return ManeuverType.turnRight;
      } else {
        return ManeuverType.slightRight;
      }
    }
  }

  /// Generate human-readable instruction for maneuver
  static String _generateInstruction(ManeuverType type) {
    switch (type) {
      case ManeuverType.turnLeft:
        return 'Turn left';
      case ManeuverType.turnRight:
        return 'Turn right';
      case ManeuverType.sharpLeft:
        return 'Sharp left turn';
      case ManeuverType.sharpRight:
        return 'Sharp right turn';
      case ManeuverType.slightLeft:
        return 'Keep left';
      case ManeuverType.slightRight:
        return 'Keep right';
      case ManeuverType.straight:
        return 'Continue straight';
      case ManeuverType.uTurn:
        return 'Make a U-turn';
      case ManeuverType.arrive:
        return 'You have arrived at your destination';
      case ManeuverType.depart:
        return 'Start your route';
    }
  }

  /// Find next maneuver from current position
  static ManeuverInstruction? findNextManeuver(
    List<ManeuverInstruction> maneuvers,
    int currentSegmentIndex,
  ) {
    if (maneuvers.isEmpty) return null;

    // Find first maneuver after current segment
    for (final maneuver in maneuvers) {
      if (maneuver.routePointIndex > currentSegmentIndex) {
        return maneuver;
      }
    }

    // If no maneuver found, return arrival (last maneuver)
    return maneuvers.last;
  }

  /// Calculate distance to next maneuver
  static double calculateDistanceToManeuver(
    LatLng current,
    List<LatLng> route,
    int currentSegmentIndex,
    ManeuverInstruction? nextManeuver,
  ) {
    if (nextManeuver == null || route.isEmpty) return 0;

    // Distance from current position to next route point
    double distance = _distance.as(
      LengthUnit.Meter,
      current,
      route[math.min(currentSegmentIndex, route.length - 1)],
    );

    // Add distances for segments between current and maneuver
    for (int i = currentSegmentIndex; i < nextManeuver.routePointIndex && i < route.length - 1; i++) {
      distance += _distance.as(
        LengthUnit.Meter,
        route[i],
        route[i + 1],
      );
    }

    return distance;
  }

  /// Estimate time remaining based on current speed and distance
  static int estimateTimeRemaining(double distanceMeters, double speedMps) {
    if (speedMps < 0.5) {
      // If moving very slowly or stopped, use average biking speed (15 km/h = 4.17 m/s)
      speedMps = 4.17;
    }

    return (distanceMeters / speedMps).round();
  }
}
