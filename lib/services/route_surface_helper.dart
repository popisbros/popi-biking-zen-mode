import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Route segment with surface info
class RouteSegment {
  final List<LatLng> points;
  final Color color;
  final String surfaceType;

  RouteSegment({
    required this.points,
    required this.color,
    required this.surfaceType,
  });
}

/// Helper class for route surface visualization
/// Provides surface-based color coding and route segmentation
class RouteSurfaceHelper {
  /// Surface quality color palette
  static const Color excellentSurface = Color(0xFF2E7D32); // Dark Green
  static const Color goodSurface = Color(0xFF7CB342);      // Light Green
  static const Color moderateSurface = Color(0xFFFDD835);  // Yellow
  static const Color poorSurface = Color(0xFFFF8C00);      // Orange
  static const Color specialSurface = Color(0xFF8E24AA);   // Purple
  static const Color unknownSurface = Color(0xFF2196F3);   // Blue (fallback)

  /// Get color for surface type
  static Color getSurfaceColor(dynamic surface) {
    if (surface == null) return unknownSurface;
    final surfaceStr = surface.toString().toLowerCase();

    // Excellent surfaces (dark green)
    if (surfaceStr.contains('asphalt') ||
        surfaceStr.contains('concrete') ||
        surfaceStr.contains('paved')) {
      return excellentSurface;
    }

    // Good surfaces (light green)
    if (surfaceStr.contains('compacted') ||
        surfaceStr.contains('fine_gravel')) {
      return goodSurface;
    }

    // Moderate surfaces (yellow)
    if (surfaceStr.contains('gravel') || surfaceStr.contains('unpaved')) {
      return moderateSurface;
    }

    // Poor surfaces (orange)
    if (surfaceStr.contains('dirt') ||
        surfaceStr.contains('sand') ||
        surfaceStr.contains('grass') ||
        surfaceStr.contains('mud')) {
      return poorSurface;
    }

    // Special surfaces (purple)
    if (surfaceStr.contains('cobble') || surfaceStr.contains('sett')) {
      return specialSurface;
    }

    // Unknown - use blue as fallback
    return unknownSurface;
  }

  /// Parse surface details and create route segments
  /// Returns list of route segments with colors based on surface
  static List<RouteSegment> createSurfaceSegments(
    List<LatLng> routePoints,
    Map<String, dynamic>? pathDetails,
  ) {
    if (pathDetails == null ||
        !pathDetails.containsKey('surface') ||
        routePoints.isEmpty) {
      // No surface data - return single blue segment
      return [
        RouteSegment(
          points: routePoints,
          color: unknownSurface,
          surfaceType: 'unknown',
        )
      ];
    }

    final surfaceList = pathDetails['surface'] as List?;
    if (surfaceList == null || surfaceList.isEmpty) {
      // No surface data - return single blue segment
      return [
        RouteSegment(
          points: routePoints,
          color: unknownSurface,
          surfaceType: 'unknown',
        )
      ];
    }

    final List<RouteSegment> segments = [];

    for (final detail in surfaceList) {
      final detailData = detail as List;
      final start = detailData[0] as int;
      final end = detailData[1] as int;
      final surfaceType = detailData[2];

      // Extract points for this segment
      final segmentPoints = <LatLng>[];
      for (int i = start; i <= end && i < routePoints.length; i++) {
        segmentPoints.add(routePoints[i]);
      }

      if (segmentPoints.isNotEmpty) {
        segments.add(RouteSegment(
          points: segmentPoints,
          color: getSurfaceColor(surfaceType),
          surfaceType: surfaceType.toString(),
        ));
      }
    }

    return segments.isNotEmpty
        ? segments
        : [
            RouteSegment(
              points: routePoints,
              color: unknownSurface,
              surfaceType: 'unknown',
            )
          ];
  }

  /// Check if surface needs warning icon on map
  static bool surfaceNeedsWarning(dynamic surface) {
    if (surface == null) return false;
    final surfaceStr = surface.toString().toLowerCase();

    // Excellent surfaces (no warning)
    if (surfaceStr.contains('asphalt') ||
        surfaceStr.contains('concrete') ||
        surfaceStr.contains('paved')) {
      return false;
    }

    // Good surfaces (no warning)
    if (surfaceStr.contains('compacted') ||
        surfaceStr.contains('fine_gravel')) {
      return false;
    }

    // Everything else needs warning
    return true;
  }

  /// Get surface quality label
  static String getSurfaceQualityLabel(dynamic surface) {
    if (surface == null) return 'Unknown';
    final surfaceStr = surface.toString().toLowerCase();

    if (surfaceStr.contains('asphalt') ||
        surfaceStr.contains('concrete') ||
        surfaceStr.contains('paved')) {
      return 'Excellent';
    }

    if (surfaceStr.contains('compacted') ||
        surfaceStr.contains('fine_gravel')) {
      return 'Good';
    }

    if (surfaceStr.contains('gravel') || surfaceStr.contains('unpaved')) {
      return 'Moderate';
    }

    if (surfaceStr.contains('dirt') ||
        surfaceStr.contains('sand') ||
        surfaceStr.contains('grass') ||
        surfaceStr.contains('mud')) {
      return 'Poor';
    }

    if (surfaceStr.contains('cobble') || surfaceStr.contains('sett')) {
      return 'Special';
    }

    return 'Unknown';
  }

  /// Get positions where surface warnings should be placed
  /// Returns list of LatLng positions at the start of poor/special surface segments
  static List<SurfaceWarningMarker> getSurfaceWarningMarkers(
    List<LatLng> routePoints,
    Map<String, dynamic>? pathDetails,
  ) {
    if (pathDetails == null ||
        !pathDetails.containsKey('surface') ||
        routePoints.isEmpty) {
      return [];
    }

    final surfaceList = pathDetails['surface'] as List?;
    if (surfaceList == null || surfaceList.isEmpty) {
      return [];
    }

    final List<SurfaceWarningMarker> markers = [];

    for (final detail in surfaceList) {
      final detailData = detail as List;
      final start = detailData[0] as int;
      final surfaceType = detailData[2];

      // Only add markers for poor/special surfaces
      if (surfaceNeedsWarning(surfaceType)) {
        if (start < routePoints.length) {
          markers.add(SurfaceWarningMarker(
            position: routePoints[start],
            surfaceType: surfaceType.toString(),
            surfaceQuality: getSurfaceQualityLabel(surfaceType),
          ));
        }
      }
    }

    return markers;
  }
}

/// Surface warning marker data
class SurfaceWarningMarker {
  final LatLng position;
  final String surfaceType;
  final String surfaceQuality;

  SurfaceWarningMarker({
    required this.position,
    required this.surfaceType,
    required this.surfaceQuality,
  });
}
