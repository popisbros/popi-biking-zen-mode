import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/location_data.dart';

/// Service for handling GPS location tracking and permissions
/// Enhanced with comprehensive logging for iOS testing
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  final StreamController<LocationData> _locationController =
      StreamController<LocationData>.broadcast();

  /// Stream of location updates
  Stream<LocationData> get locationStream => _locationController.stream;

  /// Current location
  LocationData? _currentLocation;
  LocationData? get currentLocation => _currentLocation;

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    print('📍 iOS DEBUG [LocationService]: Location services enabled = $enabled');
    return enabled;
  }

  /// Check location permission status
  Future<LocationPermission> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    print('📍 iOS DEBUG [LocationService]: Current permission = $permission');
    return permission;
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    print('📍 iOS DEBUG [LocationService]: ========== Requesting location permission ==========');
    print('📍 iOS DEBUG [LocationService]: Using ONLY Geolocator (removed permission_handler)');

    // Use ONLY geolocator to request permission - this will show iOS dialog
    final permission = await Geolocator.requestPermission();
    print('📍 iOS DEBUG [LocationService]: Geolocator.requestPermission() result = $permission');

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      print('✅ iOS DEBUG [LocationService]: Permission GRANTED ($permission)');
    } else {
      print('❌ iOS DEBUG [LocationService]: Permission DENIED ($permission)');
    }

    print('📍 iOS DEBUG [LocationService]: ========== End permission request ==========');
    return permission;
  }

  /// Get current position once
  Future<LocationData?> getCurrentPosition() async {
    try {
      print('🔍 iOS DEBUG [LocationService]: ========== Starting getCurrentPosition ==========');
      print('🔍 iOS DEBUG [LocationService]: Timestamp = ${DateTime.now().toIso8601String()}');

      final permission = await checkPermission();
      print('🔍 iOS DEBUG [LocationService]: Initial permission check = $permission');

      if (permission == LocationPermission.denied) {
        print('🔍 iOS DEBUG [LocationService]: Permission denied, requesting...');
        final newPermission = await requestPermission();
        print('🔍 iOS DEBUG [LocationService]: Permission after request = $newPermission');
        if (newPermission == LocationPermission.denied) {
          print('❌ iOS DEBUG [LocationService]: Permission still DENIED after request');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ iOS DEBUG [LocationService]: Permission DENIED FOREVER - User must enable in Settings');
        return null;
      }

      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ iOS DEBUG [LocationService]: Location services are DISABLED on device');
        return null;
      }

      print('🔍 iOS DEBUG [LocationService]: Calling Geolocator.getCurrentPosition...');
      print('🔍 iOS DEBUG [LocationService]: Using accuracy=HIGH, timeout=10s');

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('✅ iOS DEBUG [LocationService]: SUCCESS! Got GPS position:');
      print('   📍 Latitude  = ${position.latitude}');
      print('   📍 Longitude = ${position.longitude}');
      print('   📍 Altitude  = ${position.altitude}m');
      print('   📍 Accuracy  = ${position.accuracy}m');
      print('   📍 Speed     = ${position.speed}m/s');
      print('   📍 Heading   = ${position.heading}°');
      print('   📍 Timestamp = ${position.timestamp}');

      final locationData = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );

      _currentLocation = locationData;
      print('✅ iOS DEBUG [LocationService]: Location data cached in service');
      print('🔍 iOS DEBUG [LocationService]: ========== End getCurrentPosition ==========');

      return locationData;
    } catch (e, stackTrace) {
      print('❌ iOS DEBUG [LocationService]: ========== ERROR in getCurrentPosition ==========');
      print('❌ iOS DEBUG [LocationService]: Error type: ${e.runtimeType}');
      print('❌ iOS DEBUG [LocationService]: Error message: $e');
      print('❌ iOS DEBUG [LocationService]: Stack trace:');
      print(stackTrace.toString().split('\n').take(10).join('\n'));
      print('❌ iOS DEBUG [LocationService]: ========== End ERROR ==========');
      return null;
    }
  }

  /// Start continuous location tracking
  Future<void> startLocationTracking() async {
    try {
      print('🔄 iOS DEBUG [LocationService]: ========== Starting continuous location tracking ==========');

      final permission = await checkPermission();
      if (permission == LocationPermission.denied) {
        print('🔄 iOS DEBUG [LocationService]: Permission denied, requesting...');
        final newPermission = await requestPermission();
        if (newPermission == LocationPermission.denied) {
          print('❌ iOS DEBUG [LocationService]: Cannot start tracking - permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ iOS DEBUG [LocationService]: Cannot start tracking - permission denied forever');
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      print('🔄 iOS DEBUG [LocationService]: Starting position stream (distanceFilter=10m)');

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          print('📍 iOS DEBUG [LocationService]: Position update received:');
          print('   Lat=${position.latitude}, Lng=${position.longitude}, Acc=${position.accuracy}m');

          final locationData = LocationData(
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude,
            accuracy: position.accuracy,
            speed: position.speed,
            heading: position.heading,
            timestamp: position.timestamp,
          );

          _currentLocation = locationData;
          _locationController.add(locationData);
          print('📍 iOS DEBUG [LocationService]: Location data broadcast to listeners');
        },
        onError: (error) {
          print('❌ iOS DEBUG [LocationService]: Position stream error: $error');
        },
        onDone: () {
          print('🔄 iOS DEBUG [LocationService]: Position stream completed');
        },
      );

      print('✅ iOS DEBUG [LocationService]: Location tracking started successfully');
    } catch (e) {
      print('❌ iOS DEBUG [LocationService]: Error starting tracking: $e');
    }
  }

  /// Stop location tracking
  Future<void> stopLocationTracking() async {
    print('🛑 iOS DEBUG [LocationService]: Stopping location tracking');
    await _positionStream?.cancel();
    _positionStream = null;
    print('✅ iOS DEBUG [LocationService]: Location tracking stopped');
  }

  /// Calculate distance between two points in meters
  double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final distance = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    print('📏 iOS DEBUG [LocationService]: Distance calculated = ${distance.toStringAsFixed(2)}m');
    return distance;
  }

  /// Calculate bearing between two points
  double calculateBearing(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final bearing = Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
    print('🧭 iOS DEBUG [LocationService]: Bearing calculated = ${bearing.toStringAsFixed(2)}°');
    return bearing;
  }

  /// Dispose resources
  void dispose() {
    print('🗑️ iOS DEBUG [LocationService]: Disposing location service');
    stopLocationTracking();
    _locationController.close();
  }
}
