import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/location_data.dart';

/// Service for handling GPS location tracking and permissions
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
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check location permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    // Request permission using permission_handler
    final status = await Permission.location.request();
    
    if (status.isGranted) {
      return await Geolocator.checkPermission();
    } else {
      return LocationPermission.denied;
    }
  }

  /// Get current position once
  Future<LocationData?> getCurrentPosition() async {
    try {
      final permission = await checkPermission();
      if (permission == LocationPermission.denied) {
        final newPermission = await requestPermission();
        if (newPermission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

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
      return locationData;
    } catch (e) {
      print('LocationService.getCurrentPosition: Error getting location: $e');
      return null;
    }
  }

  /// Start continuous location tracking
  Future<void> startLocationTracking() async {
    try {
      final permission = await checkPermission();
      if (permission == LocationPermission.denied) {
        final newPermission = await requestPermission();
        if (newPermission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
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
        },
        onError: (error) {
          print('LocationService.startLocationTracking: Error: $error');
        },
      );
    } catch (e) {
      print('LocationService.startLocationTracking: Error starting tracking: $e');
    }
  }

  /// Stop location tracking
  Future<void> stopLocationTracking() async {
    await _positionStream?.cancel();
    _positionStream = null;
  }

  /// Calculate distance between two points in meters
  double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Calculate bearing between two points
  double calculateBearing(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    return Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
  }

  /// Dispose resources
  void dispose() {
    stopLocationTracking();
    _locationController.close();
  }
}

