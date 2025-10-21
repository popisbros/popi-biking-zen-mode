import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/location_data.dart';
import '../utils/app_logger.dart';

/// Service for handling GPS location tracking and permissions
/// Enhanced with comprehensive logging for iOS testing
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _pollTimer;
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
    return enabled;
  }

  /// Check location permission status
  Future<LocationPermission> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission;
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    AppLogger.separator('Requesting location permission');
    AppLogger.location('Using ONLY Geolocator (removed permission_handler)');

    // Use ONLY geolocator to request permission - this will show iOS dialog
    final permission = await Geolocator.requestPermission();
    AppLogger.location('Geolocator.requestPermission() result', data: {
      'permission': permission.toString(),
    });

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      AppLogger.success('Permission GRANTED', tag: 'LOCATION', data: {
        'permission': permission.toString(),
      });
    } else {
      AppLogger.error('Permission DENIED', tag: 'LOCATION', data: {
        'permission': permission.toString(),
      });
    }

    AppLogger.separator();
    return permission;
  }

  /// Get current position once
  Future<LocationData?> getCurrentPosition() async {
    try {
      final permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        final newPermission = await requestPermission();
        if (newPermission == LocationPermission.denied) {
          AppLogger.error('Permission denied after request', tag: 'LOCATION');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.error('Permission denied forever - enable in Settings', tag: 'LOCATION');
        return null;
      }

      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.error('Location services disabled', tag: 'LOCATION');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
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
    } catch (e, stackTrace) {
      AppLogger.error('getCurrentPosition failed', tag: 'LOCATION', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Start continuous location tracking with timer-based polling
  Future<void> startLocationTracking() async {
    try {
      // Check if already tracking
      if (_pollTimer != null) {
        AppLogger.warning('Location tracking already running', tag: 'LOCATION');
        return;
      }

      // Check if location services are enabled on device
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.error('Cannot start tracking - location services disabled', tag: 'LOCATION');
        return;
      }

      final permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        final newPermission = await requestPermission();
        if (newPermission == LocationPermission.denied) {
          AppLogger.error('Cannot start tracking - permission denied', tag: 'LOCATION');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.error('Cannot start tracking - permission denied forever', tag: 'LOCATION');
        return;
      }

      // Get initial position immediately
      await _pollPosition();

      // Start timer to poll every 3 seconds
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        await _pollPosition();
      });

      AppLogger.success('Location tracking started', tag: 'LOCATION');
    } catch (e) {
      AppLogger.error('Error starting tracking', tag: 'LOCATION', error: e);
    }
  }

  /// Poll GPS position once
  Future<void> _pollPosition() async {
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        // No distanceFilter or timeLimit - just get current position
      );

      final position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
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
      _locationController.add(locationData);
    } catch (e, stackTrace) {
      AppLogger.error('Error polling position', tag: 'LOCATION', error: e, stackTrace: stackTrace);
    }
  }

  /// Stop location tracking
  Future<void> stopLocationTracking() async {
    // Cancel timer if running
    _pollTimer?.cancel();
    _pollTimer = null;

    // Cancel stream subscription if exists
    await _positionStream?.cancel();
    _positionStream = null;

    AppLogger.success('Location tracking stopped', tag: 'LOCATION');
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
