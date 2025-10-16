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
    AppLogger.location('Location services enabled', data: {'enabled': enabled});
    return enabled;
  }

  /// Check location permission status
  Future<LocationPermission> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    AppLogger.location('Current permission', data: {'permission': permission.toString()});
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
      AppLogger.separator('Starting getCurrentPosition');
      AppLogger.location('Timestamp', data: {'time': DateTime.now().toIso8601String()});

      final permission = await checkPermission();
      AppLogger.location('Initial permission check', data: {'permission': permission.toString()});

      if (permission == LocationPermission.denied) {
        AppLogger.location('Permission denied, requesting');
        final newPermission = await requestPermission();
        AppLogger.location('Permission after request', data: {'permission': newPermission.toString()});
        if (newPermission == LocationPermission.denied) {
          AppLogger.error('Permission still DENIED after request', tag: 'LOCATION');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.error('Permission DENIED FOREVER - User must enable in Settings', tag: 'LOCATION');
        return null;
      }

      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.error('Location services are DISABLED on device', tag: 'LOCATION');
        return null;
      }

      AppLogger.location('Calling Geolocator.getCurrentPosition', data: {
        'accuracy': 'HIGH',
        'timeout': '10s',
      });

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      AppLogger.success('Got GPS position', tag: 'LOCATION', data: {
        'lat': position.latitude,
        'lng': position.longitude,
        'altitude': '${position.altitude}m',
        'accuracy': '${position.accuracy}m',
        'speed': '${position.speed}m/s',
        'heading': '${position.heading}°',
        'timestamp': position.timestamp.toString(),
      });

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
      AppLogger.success('Location data cached in service', tag: 'LOCATION');
      AppLogger.separator();

      return locationData;
    } catch (e, stackTrace) {
      AppLogger.separator('ERROR in getCurrentPosition');
      AppLogger.error('getCurrentPosition failed', tag: 'LOCATION', error: e, stackTrace: stackTrace);
      AppLogger.separator();
      return null;
    }
  }

  /// Start continuous location tracking
  Future<void> startLocationTracking() async {
    try {
      AppLogger.separator('Starting continuous location tracking');

      // Check if already tracking
      if (_positionStream != null) {
        AppLogger.warning('Position stream already running, skipping startLocationTracking', tag: 'LOCATION');
        return;
      }

      final permission = await checkPermission();
      AppLogger.debug('Current permission status', tag: 'LOCATION', data: {'permission': permission.name});

      if (permission == LocationPermission.denied) {
        AppLogger.location('Permission denied, requesting');
        final newPermission = await requestPermission();
        AppLogger.debug('New permission status', tag: 'LOCATION', data: {'permission': newPermission.name});
        if (newPermission == LocationPermission.denied) {
          AppLogger.error('Cannot start tracking - permission denied', tag: 'LOCATION');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.error('Cannot start tracking - permission denied forever', tag: 'LOCATION');
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // 0 = update continuously regardless of movement
        timeLimit: Duration(seconds: 3), // Update at least every 3 seconds
      );

      AppLogger.location('Starting position stream', data: {
        'distanceFilter': '0m (continuous updates)',
        'timeLimit': '3 seconds',
        'note': 'Will update every 3 seconds even if stationary',
      });

      print('[LOCATION SERVICE] About to call Geolocator.getPositionStream()...');

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          print('[LOCATION SERVICE] ✅ Position update received from Geolocator! lat=${position.latitude}, lon=${position.longitude}');

          AppLogger.location('Position update received', data: {
            'lat': position.latitude,
            'lng': position.longitude,
            'accuracy': '${position.accuracy}m',
          });

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
          print('[LOCATION SERVICE] Broadcast location to ${_locationController.hasListener ? "active" : "NO"} listeners');
          AppLogger.location('Location data broadcast to listeners');
        },
        onError: (error, stackTrace) {
          print('[LOCATION SERVICE] ❌ Stream ERROR: $error');
          AppLogger.error('Position stream error', tag: 'LOCATION', error: error, stackTrace: stackTrace);
          AppLogger.debug('Error type', tag: 'LOCATION', data: {
            'errorType': error.runtimeType.toString(),
            'errorMessage': error.toString(),
          });
        },
        onDone: () {
          print('[LOCATION SERVICE] ⚠️ Stream DONE/COMPLETED');
          AppLogger.warning('Position stream completed unexpectedly', tag: 'LOCATION');
          AppLogger.debug('Stream ended - this should not happen unless tracking was stopped', tag: 'LOCATION');
        },
      );

      print('[LOCATION SERVICE] getPositionStream().listen() completed, subscription active');
      AppLogger.success('Location tracking started successfully', tag: 'LOCATION');
    } catch (e) {
      AppLogger.error('Error starting tracking', tag: 'LOCATION', error: e);
    }
  }

  /// Stop location tracking
  Future<void> stopLocationTracking() async {
    AppLogger.debug('Stopping location tracking', tag: 'LOCATION');
    await _positionStream?.cancel();
    _positionStream = null;
    AppLogger.success('Location tracking stopped', tag: 'LOCATION');
  }

  /// Calculate distance between two points in meters
  double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final distance = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    AppLogger.debug('Distance calculated', tag: 'LOCATION', data: {
      'distance': '${distance.toStringAsFixed(2)}m',
    });
    return distance;
  }

  /// Calculate bearing between two points
  double calculateBearing(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final bearing = Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
    AppLogger.debug('Bearing calculated', tag: 'LOCATION', data: {
      'bearing': '${bearing.toStringAsFixed(2)}°',
    });
    return bearing;
  }

  /// Dispose resources
  void dispose() {
    AppLogger.debug('Disposing location service', tag: 'LOCATION');
    stopLocationTracking();
    _locationController.close();
  }
}
