import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// GPS location breadcrumb for navigation tracking
///
/// Used to track user movement during navigation for:
/// - Travel direction calculation
/// - Map rotation based on movement
/// - Speed-based zoom adjustments
class LocationBreadcrumb {
  final LatLng position;
  final DateTime timestamp;
  final double? speed; // m/s

  LocationBreadcrumb({
    required this.position,
    required this.timestamp,
    this.speed,
  });
}

/// Metadata for route segments in 3D map rendering
///
/// Caches segment information for efficient route updates:
/// - Which polyline segment index range
/// - Original color before dimming (for traveled segments)
class RouteSegmentMetadata {
  final int index;
  final int endIndex;
  final Color originalColor;

  RouteSegmentMetadata({
    required this.index,
    required this.endIndex,
    required this.originalColor,
  });
}
