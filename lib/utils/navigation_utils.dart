/// Navigation-specific utility functions
///
/// Consolidates duplicated navigation calculations from map screens
class NavigationUtils {
  // Private constructor to prevent instantiation
  NavigationUtils._();

  /// Calculate dynamic zoom level based on current speed
  ///
  /// Optimized for walking/biking with 0.5 zoom increments
  /// Higher zoom (closer view) for slower speeds, lower zoom (wider view) for faster speeds
  ///
  /// Parameters:
  /// - speedMps: Speed in meters per second (null or negative values treated as stationary)
  ///
  /// Returns: Zoom level (15.0 - 19.0)
  ///
  /// Speed ranges:
  /// - Stationary (< 1 km/h): 19.0 - Very close view
  /// - Walking (1-5 km/h): 18.5
  /// - Slow biking (5-10 km/h): 18.0
  /// - Normal biking (10-15 km/h): 17.5
  /// - Fast biking (15-20 km/h): 17.0
  /// - Very fast (20-25 km/h): 16.5
  /// - Racing (25-30 km/h): 16.0
  /// - Electric bike (30-40 km/h): 15.5
  /// - Crazy fast! (40+ km/h): 15.0 - Wide view
  ///
  /// Example:
  /// ```dart
  /// final speedMps = 5.5; // ~20 km/h
  /// final zoom = NavigationUtils.calculateNavigationZoom(speedMps);
  /// mapController.move(position, zoom);
  /// ```
  static double calculateNavigationZoom(double? speedMps) {
    if (speedMps == null || speedMps < 0.28) {
      return 19.0; // Stationary (< 1 km/h) - closer view
    }
    if (speedMps < 1.39) return 18.5; // 1-5 km/h (walking) - closer view
    if (speedMps < 2.78) return 18.0; // 5-10 km/h (slow biking) - closer view
    if (speedMps < 4.17) return 17.5; // 10-15 km/h (normal biking) - closer view
    if (speedMps < 5.56) return 17.0; // 15-20 km/h (fast biking) - closer view
    if (speedMps < 6.94) return 16.5; // 20-25 km/h (very fast) - closer view
    if (speedMps < 8.33) return 16.0; // 25-30 km/h (racing) - closer view
    if (speedMps < 11.11) return 15.5; // 30-40 km/h (electric bike) - closer view
    return 15.0; // 40+ km/h (crazy fast!) - closer view
  }

  /// Convert speed from meters per second to kilometers per hour
  ///
  /// Example:
  /// ```dart
  /// final speedKmh = NavigationUtils.mpsToKmh(5.5); // 19.8 km/h
  /// ```
  static double mpsToKmh(double speedMps) {
    return speedMps * 3.6;
  }

  /// Convert speed from kilometers per hour to meters per second
  ///
  /// Example:
  /// ```dart
  /// final speedMps = NavigationUtils.kmhToMps(20); // 5.56 m/s
  /// ```
  static double kmhToMps(double speedKmh) {
    return speedKmh / 3.6;
  }

  /// Format speed for display
  ///
  /// Converts meters per second to human-readable km/h
  ///
  /// Example:
  /// ```dart
  /// print(NavigationUtils.formatSpeed(5.5)); // "20 km/h"
  /// ```
  static String formatSpeed(double speedMps, {int decimals = 0}) {
    final speedKmh = mpsToKmh(speedMps);
    return '${speedKmh.toStringAsFixed(decimals)} km/h';
  }

  /// Calculate estimated time of arrival (ETA)
  ///
  /// Parameters:
  /// - distanceMeters: Remaining distance in meters
  /// - speedMps: Current speed in meters per second
  /// - averageSpeedMps: Optional fallback speed if current speed is too low (default: 4.17 m/s = 15 km/h)
  ///
  /// Returns: Duration until arrival
  ///
  /// Example:
  /// ```dart
  /// final eta = NavigationUtils.calculateETA(5000, 5.5);
  /// print('Arrive in ${eta.inMinutes} minutes');
  /// ```
  static Duration calculateETA(
    double distanceMeters,
    double? speedMps, {
    double averageSpeedMps = 4.17, // 15 km/h default
  }) {
    final effectiveSpeed = (speedMps != null && speedMps > 1.0) ? speedMps : averageSpeedMps;
    final secondsToArrival = distanceMeters / effectiveSpeed;
    return Duration(seconds: secondsToArrival.round());
  }

  /// Format duration for display
  ///
  /// Converts duration to human-readable format
  ///
  /// Examples:
  /// - 30 seconds: "< 1 min"
  /// - 90 seconds: "2 min"
  /// - 3700 seconds: "1h 2min"
  ///
  /// ```dart
  /// final eta = Duration(seconds: 3700);
  /// print(NavigationUtils.formatDuration(eta)); // "1h 2min"
  /// ```
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}min';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '< 1 min';
    }
  }

  /// Check if speed is valid for navigation
  ///
  /// Returns true if speed is reasonable for cycling/walking (< 60 km/h)
  /// GPS can sometimes report erroneous high speeds
  static bool isValidSpeed(double? speedMps) {
    if (speedMps == null) return false;
    final speedKmh = mpsToKmh(speedMps);
    return speedKmh >= 0 && speedKmh < 60; // Max 60 km/h for cycling
  }
}
