import 'dart:io';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../utils/app_logger.dart';

/// Service for iOS native navigation using Mapbox Navigation SDK
/// This service is only available on iOS platform
class IOSNavigationService {
  static const _channel = MethodChannel('com.popi.biking/navigation');

  /// Check if native navigation is available (iOS only)
  static bool get isAvailable => Platform.isIOS;

  /// Start native navigation with given route
  ///
  /// Parameters:
  /// - [routePoints]: List of coordinates forming the route
  /// - [destinationName]: Name of the destination for display
  ///
  /// Throws [PlatformException] if navigation fails
  Future<void> startNavigation({
    required List<LatLng> routePoints,
    required String destinationName,
  }) async {
    if (!isAvailable) {
      AppLogger.warning('Native navigation only available on iOS');
      return;
    }

    try {
      AppLogger.map('Starting iOS native navigation', data: {
        'points': routePoints.length,
        'destination': destinationName,
      });

      final result = await _channel.invokeMethod('startNavigation', {
        'points': routePoints.map((p) => {
          'latitude': p.latitude,
          'longitude': p.longitude,
        }).toList(),
        'destination': destinationName,
      });

      AppLogger.success('Navigation started: $result');
    } on PlatformException catch (e) {
      AppLogger.error('Navigation platform error', error: e);
      rethrow;
    } catch (e) {
      AppLogger.error('Navigation error', error: e);
      rethrow;
    }
  }

  /// Stop active navigation
  Future<void> stopNavigation() async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('stopNavigation');
      AppLogger.map('Navigation stopped');
    } catch (e) {
      AppLogger.error('Failed to stop navigation', error: e);
    }
  }
}
