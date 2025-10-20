import 'package:latlong2/latlong.dart';
import '../models/route_warning.dart';
import '../services/routing_service.dart';
import '../utils/app_logger.dart';

/// Analyzes road surface data from GraphHopper pathDetails
/// and generates warnings for poor or unknown surfaces
class RoadSurfaceAnalyzer {
  static const Distance _distance = Distance();

  /// Extract road surface warnings from route pathDetails
  ///
  /// Returns list of RouteWarning sorted by distance along route
  static List<RouteWarning> analyzeRouteSurface({
    required RouteResult route,
    LatLng? currentPosition,
  }) {
    final pathDetails = route.pathDetails;
    if (pathDetails == null || !pathDetails.containsKey('surface')) {
      AppLogger.debug('No surface data available in pathDetails', tag: 'SURFACE');
      return [];
    }

    final surfaceData = pathDetails['surface'] as List<dynamic>;
    if (surfaceData.isEmpty) {
      AppLogger.debug('Surface data is empty', tag: 'SURFACE');
      return [];
    }

    AppLogger.debug('Analyzing surface data', tag: 'SURFACE', data: {
      'segments': surfaceData.length,
    });

    final List<RouteWarning> warnings = [];
    final routePoints = route.points;

    // Calculate current distance along route if position provided
    double currentDistanceAlongRoute = 0.0;
    if (currentPosition != null) {
      for (int i = 0; i < routePoints.length - 1; i++) {
        final distToSegment = _distance.as(
          LengthUnit.Meter,
          routePoints[i],
          currentPosition,
        );
        final segmentLength = _distance.as(
          LengthUnit.Meter,
          routePoints[i],
          routePoints[i + 1],
        );

        if (distToSegment < segmentLength) {
          currentDistanceAlongRoute += distToSegment;
          break;
        }
        currentDistanceAlongRoute += segmentLength;
      }
    }

    // Each surface entry: [startIndex, endIndex, surfaceType]
    for (final entry in surfaceData) {
      if (entry is! List || entry.length < 3) continue;

      final startIndex = entry[0] as int;
      final endIndex = entry[1] as int;
      final surfaceType = entry[2] as String;

      // Skip if indices are invalid
      if (startIndex >= routePoints.length || endIndex >= routePoints.length) {
        continue;
      }

      // Classify surface quality
      final quality = _classifySurfaceQuality(surfaceType);
      if (quality == null) {
        // Good surface, no warning needed
        continue;
      }

      // Calculate distance along route to segment start
      double distanceAlongRoute = 0.0;
      for (int i = 0; i < startIndex && i < routePoints.length - 1; i++) {
        distanceAlongRoute += _distance.as(
          LengthUnit.Meter,
          routePoints[i],
          routePoints[i + 1],
        );
      }

      // Calculate segment length
      double segmentLength = 0.0;
      for (int i = startIndex; i < endIndex && i < routePoints.length - 1; i++) {
        segmentLength += _distance.as(
          LengthUnit.Meter,
          routePoints[i],
          routePoints[i + 1],
        );
      }

      // Calculate distance from current position
      final distanceFromUser = distanceAlongRoute - currentDistanceAlongRoute;

      // Only include warnings ahead of user
      if (currentPosition != null && distanceFromUser <= 0) {
        continue;
      }

      warnings.add(RouteWarning(
        type: RouteWarningType.roadSurface,
        distanceAlongRoute: distanceAlongRoute,
        distanceFromUser: distanceFromUser.abs(),
        surfaceQuality: quality,
        surfaceLength: segmentLength,
        surfaceType: surfaceType,
      ));

      AppLogger.debug('Surface warning detected', tag: 'SURFACE', data: {
        'type': surfaceType,
        'quality': quality.name,
        'distance': '${distanceAlongRoute.toStringAsFixed(0)}m',
        'length': '${segmentLength.toStringAsFixed(0)}m',
      });
    }

    AppLogger.success('Surface analysis complete', tag: 'SURFACE', data: {
      'warnings': warnings.length,
    });

    return warnings;
  }

  /// Classify surface type into quality category
  /// Returns null for good surfaces (no warning needed)
  static RoadSurfaceQuality? _classifySurfaceQuality(String surfaceType) {
    final surface = surfaceType.toLowerCase();

    // Excellent surfaces (no warning)
    if (surface.contains('asphalt') ||
        surface.contains('concrete') ||
        surface.contains('paved')) {
      return null;
    }

    // Good surfaces (no warning)
    if (surface.contains('compacted') || surface.contains('fine_gravel')) {
      return null;
    }

    // Poor surfaces (warning needed)
    if (surface.contains('gravel') ||
        surface.contains('unpaved') ||
        surface.contains('dirt') ||
        surface.contains('sand') ||
        surface.contains('grass') ||
        surface.contains('mud') ||
        surface.contains('cobble') ||
        surface.contains('sett')) {
      return RoadSurfaceQuality.poor;
    }

    // Unknown/unspecified surfaces
    if (surface.contains('unknown') || surface.isEmpty) {
      return RoadSurfaceQuality.unknown;
    }

    // Default: treat as unknown
    return RoadSurfaceQuality.unknown;
  }
}
