import 'package:latlong2/latlong.dart';
import '../models/map_models.dart';
import '../models/location_data.dart';
import 'geo_utils.dart';
import 'app_logger.dart';

/// Navigation tracking utility for GPS breadcrumb management
///
/// Provides shared navigation tracking functionality for both 2D and 3D maps:
/// - GPS breadcrumb collection
/// - Travel direction calculation with smoothing
/// - Movement-based map rotation
class MapNavigationTracker {
  // Constants
  static const int maxBreadcrumbs = 5;
  static const double minBreadcrumbDistance = 5.0; // meters - responsive at cycling speeds
  static const Duration breadcrumbMaxAge = Duration(seconds: 20); // 20s window for stable tracking
  static const double minTravelDistance = 8.0; // meters - need at least 8m total movement

  // State
  final List<LocationBreadcrumb> _breadcrumbs = [];
  double? _lastBearing;

  /// Add a GPS location breadcrumb if it meets distance threshold
  ///
  /// Parameters:
  /// - location: Current GPS location data
  ///
  /// Returns: true if breadcrumb was added, false if skipped
  bool addBreadcrumb(LocationData location) {
    final now = DateTime.now();
    final newPosition = LatLng(location.latitude, location.longitude);

    // Remove old breadcrumbs
    _breadcrumbs.removeWhere((b) => now.difference(b.timestamp) > breadcrumbMaxAge);

    // Only add if moved significant distance from last breadcrumb
    if (_breadcrumbs.isNotEmpty) {
      final lastPos = _breadcrumbs.last.position;
      final distance = GeoUtils.calculateDistance(
        lastPos.latitude, lastPos.longitude,
        newPosition.latitude, newPosition.longitude,
      );
      if (distance < minBreadcrumbDistance) return false; // Too close, skip
    }

    _breadcrumbs.add(LocationBreadcrumb(
      position: newPosition,
      timestamp: now,
      speed: location.speed,
    ));

    // Keep only recent breadcrumbs
    if (_breadcrumbs.length > maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }

    return true;
  }

  /// Calculate travel direction from breadcrumb trail
  ///
  /// Parameters:
  /// - smoothingRatio: How much to blend with previous bearing (0.0-1.0)
  ///   - 0.7 = 70% new, 30% old (more responsive, used in 2D)
  ///   - 0.9 = 90% new, 10% old (very responsive, used in 3D)
  /// - enableLogging: Whether to log bearing calculations (for debugging)
  ///
  /// Returns: Bearing in degrees (0-360), or null if insufficient data
  double? calculateTravelDirection({
    double smoothingRatio = 0.7,
    bool enableLogging = false,
  }) {
    if (_breadcrumbs.length < 2) return null;

    final start = _breadcrumbs.first.position;
    final end = _breadcrumbs.last.position;

    final totalDistance = GeoUtils.calculateDistance(
      start.latitude, start.longitude,
      end.latitude, end.longitude,
    );

    // Need minimum movement to avoid GPS noise
    if (totalDistance < minTravelDistance) return null;

    final bearing = GeoUtils.calculateBearing(start, end);

    if (enableLogging) {
      AppLogger.debug('Bearing calculation', tag: 'BEARING', data: {
        'startLat': start.latitude.toStringAsFixed(6),
        'startLon': start.longitude.toStringAsFixed(6),
        'endLat': end.latitude.toStringAsFixed(6),
        'endLon': end.longitude.toStringAsFixed(6),
        'calculatedBearing': '${bearing.toStringAsFixed(1)}°',
        'direction': GeoUtils.formatBearing(bearing),
      });
    }

    // Smooth bearing with last value
    double finalBearing = bearing;
    if (_lastBearing != null) {
      final diff = (bearing - _lastBearing!).abs();
      if (diff < 180) {
        finalBearing = bearing * smoothingRatio + _lastBearing! * (1 - smoothingRatio);

        if (enableLogging) {
          AppLogger.debug('Bearing smoothed', tag: 'BEARING', data: {
            'oldBearing': '${_lastBearing!.toStringAsFixed(1)}°',
            'newBearing': '${bearing.toStringAsFixed(1)}°',
            'smoothedBearing': '${finalBearing.toStringAsFixed(1)}°',
            'smoothingRatio': smoothingRatio,
          });
        }
      }
    } else if (enableLogging) {
      AppLogger.debug('First bearing (no smoothing)', tag: 'BEARING', data: {
        'bearing': '${finalBearing.toStringAsFixed(1)}°',
      });
    }

    _lastBearing = finalBearing;
    return finalBearing;
  }

  /// Clear all breadcrumbs and reset state
  void clear() {
    _breadcrumbs.clear();
    _lastBearing = null;
  }

  /// Get number of breadcrumbs currently tracked
  int get breadcrumbCount => _breadcrumbs.length;

  /// Get current breadcrumb list (read-only)
  List<LocationBreadcrumb> get breadcrumbs => List.unmodifiable(_breadcrumbs);

  /// Get last calculated bearing (or null if none)
  double? get lastBearing => _lastBearing;
}
