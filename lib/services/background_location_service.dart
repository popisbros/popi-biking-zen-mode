import 'dart:async';
import 'dart:isolate';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/location_data.dart';
import 'offline_storage_service.dart';

/// Service for background location tracking
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  StreamSubscription<Position>? _positionStream;
  final StreamController<LocationData> _locationController = 
      StreamController<LocationData>.broadcast();
  final OfflineStorageService _offlineStorage = OfflineStorageService();
  
  bool _isTracking = false;
  Timer? _heartbeatTimer;

  /// Stream of location updates
  Stream<LocationData> get locationStream => _locationController.stream;

  /// Check if background tracking is active
  bool get isTracking => _isTracking;

  /// Start background location tracking
  Future<bool> startBackgroundTracking() async {
    try {
      print('BackgroundLocationService.startBackgroundTracking: Starting background tracking');
      
      // Check permissions
      final permission = await _checkPermissions();
      if (!permission) {
        print('BackgroundLocationService.startBackgroundTracking: Permissions not granted');
        return false;
      }

      // Check if location services are enabled
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        print('BackgroundLocationService.startBackgroundTracking: Location services disabled');
        return false;
      }

      // Configure location settings for background tracking
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
        timeLimit: Duration(seconds: 30), // Timeout after 30 seconds
      );

      // Start position stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _onLocationUpdate,
        onError: _onLocationError,
        onDone: _onLocationDone,
      );

      _isTracking = true;
      
      // Start heartbeat timer to ensure service stays alive
      _startHeartbeat();
      
      print('BackgroundLocationService.startBackgroundTracking: Background tracking started');
      return true;
    } catch (e) {
      print('BackgroundLocationService.startBackgroundTracking: Error starting tracking: $e');
      return false;
    }
  }

  /// Stop background location tracking
  Future<void> stopBackgroundTracking() async {
    try {
      print('BackgroundLocationService.stopBackgroundTracking: Stopping background tracking');
      
      await _positionStream?.cancel();
      _positionStream = null;
      _isTracking = false;
      
      _stopHeartbeat();
      
      print('BackgroundLocationService.stopBackgroundTracking: Background tracking stopped');
    } catch (e) {
      print('BackgroundLocationService.stopBackgroundTracking: Error stopping tracking: $e');
    }
  }

  /// Handle location updates
  void _onLocationUpdate(Position position) {
    try {
      final locationData = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );

      // Emit location update
      _locationController.add(locationData);
      
      // Save to offline storage
      _offlineStorage.addLocationToHistory(locationData);
      
      print('BackgroundLocationService._onLocationUpdate: Location updated: ${locationData.latitude}, ${locationData.longitude}');
    } catch (e) {
      print('BackgroundLocationService._onLocationUpdate: Error processing location: $e');
    }
  }

  /// Handle location errors
  void _onLocationError(dynamic error) {
    print('BackgroundLocationService._onLocationError: Location error: $error');
    
    // Try to restart tracking if it's a temporary error
    if (_isTracking) {
      Timer(const Duration(seconds: 5), () {
        if (_isTracking) {
          print('BackgroundLocationService._onLocationError: Attempting to restart tracking');
          startBackgroundTracking();
        }
      });
    }
  }

  /// Handle location stream completion
  void _onLocationDone() {
    print('BackgroundLocationService._onLocationDone: Location stream completed');
    
    // Restart tracking if it was active
    if (_isTracking) {
      Timer(const Duration(seconds: 2), () {
        if (_isTracking) {
          print('BackgroundLocationService._onLocationDone: Restarting tracking');
          startBackgroundTracking();
        }
      });
    }
  }

  /// Check and request necessary permissions
  Future<bool> _checkPermissions() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      // Check background location permission (Android)
      if (await Permission.locationAlways.isDenied) {
        final status = await Permission.locationAlways.request();
        if (status.isDenied) {
          print('BackgroundLocationService._checkPermissions: Background location permission denied');
          // Continue with foreground permission for now
        }
      }

      return true;
    } catch (e) {
      print('BackgroundLocationService._checkPermissions: Error checking permissions: $e');
      return false;
    }
  }

  /// Start heartbeat timer to keep service alive
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isTracking) {
        print('BackgroundLocationService._startHeartbeat: Heartbeat - tracking active');
        // You could send a notification or update a status here
      }
    });
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Get current location once
  Future<LocationData?> getCurrentLocation() async {
    try {
      final permission = await _checkPermissions();
      if (!permission) return null;

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

      // Save to offline storage
      await _offlineStorage.addLocationToHistory(locationData);
      
      return locationData;
    } catch (e) {
      print('BackgroundLocationService.getCurrentLocation: Error getting location: $e');
      return null;
    }
  }

  /// Get location history from offline storage
  Future<List<LocationData>> getLocationHistory() async {
    return await _offlineStorage.getLocationHistory();
  }

  /// Clear location history
  Future<void> clearLocationHistory() async {
    try {
      await _offlineStorage.clearAllCache();
      print('BackgroundLocationService.clearLocationHistory: Location history cleared');
    } catch (e) {
      print('BackgroundLocationService.clearLocationHistory: Error clearing history: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    stopBackgroundTracking();
    _locationController.close();
  }
}
