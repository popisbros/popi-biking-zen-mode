import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_data.dart';
import '../services/location_service.dart';

/// Provider for location service
final locationServiceProvider = Provider<LocationService>((ref) {
  print('📍 iOS DEBUG [Provider]: Creating LocationService instance');
  return LocationService();
});

/// Provider for current location
final currentLocationProvider = StreamProvider<LocationData?>((ref) {
  print('📍 iOS DEBUG [Provider]: Setting up current location stream provider');
  final locationService = ref.watch(locationServiceProvider);
  return locationService.locationStream;
});

/// Provider for location permission status
final locationPermissionProvider = FutureProvider<LocationPermission>((ref) async {
  print('📍 iOS DEBUG [Provider]: Checking location permission');
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.checkPermission();
});

/// Provider for location service enabled status
final locationServiceEnabledProvider = FutureProvider<bool>((ref) async {
  print('📍 iOS DEBUG [Provider]: Checking if location service is enabled');
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.isLocationServiceEnabled();
});

/// Notifier for managing location state
class LocationNotifier extends StateNotifier<AsyncValue<LocationData?>> {
  final LocationService _locationService;
  StreamSubscription<LocationData>? _locationSubscription;

  LocationNotifier(this._locationService) : super(const AsyncValue.loading()) {
    print('📍 iOS DEBUG [LocationNotifier]: Constructor called, initializing...');
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      print('🔍 iOS DEBUG [LocationNotifier]: ========== Starting initialization ==========');
      print('🔍 iOS DEBUG [LocationNotifier]: Timestamp = ${DateTime.now().toIso8601String()}');

      // Check if location service is enabled
      final isEnabled = await _locationService.isLocationServiceEnabled();
      print('🔍 iOS DEBUG [LocationNotifier]: Service enabled = $isEnabled');

      if (!isEnabled) {
        print('❌ iOS DEBUG [LocationNotifier]: Location services DISABLED on device');
        state = AsyncValue.error('Location services are disabled. Please enable in Settings.', StackTrace.current);
        return;
      }

      // Try to get location - this will trigger iOS permission dialog automatically
      print('🔍 iOS DEBUG [LocationNotifier]: Attempting to get initial location...');
      print('🔍 iOS DEBUG [LocationNotifier]: This will trigger iOS permission dialog if not already granted');

      final initialLocation = await _locationService.getCurrentPosition();

      if (initialLocation != null) {
        print('✅ iOS DEBUG [LocationNotifier]: SUCCESS! Got initial location:');
        print('   Lat=${initialLocation.latitude}, Lng=${initialLocation.longitude}');
        print('   Accuracy=${initialLocation.accuracy}m');
        state = AsyncValue.data(initialLocation);

        // Start continuous location tracking
        print('🔍 iOS DEBUG [LocationNotifier]: Starting continuous location tracking...');
        await _locationService.startLocationTracking();

        // Start listening to location updates
        print('🔍 iOS DEBUG [LocationNotifier]: Setting up location stream listener...');
        _locationSubscription = _locationService.locationStream.listen(
          (location) {
            print('📍 iOS DEBUG [LocationNotifier]: Location update received from stream:');
            print('   Lat=${location.latitude}, Lng=${location.longitude}, Acc=${location.accuracy}m');
            state = AsyncValue.data(location);
          },
          onError: (error, stackTrace) {
            print('❌ iOS DEBUG [LocationNotifier]: Stream error: $error');
            state = AsyncValue.error(error, stackTrace);
          },
          onDone: () {
            print('🔄 iOS DEBUG [LocationNotifier]: Location stream completed');
          },
        );
        print('✅ iOS DEBUG [LocationNotifier]: Location stream subscription active');
      } else {
        print('❌ iOS DEBUG [LocationNotifier]: Could not get initial location');
        print('   This usually means permission was DENIED by user');
        state = AsyncValue.error('Location permission required. Please enable in Settings.', StackTrace.current);
      }

      print('🔍 iOS DEBUG [LocationNotifier]: ========== End initialization ==========');
    } catch (error, stackTrace) {
      print('❌ iOS DEBUG [LocationNotifier]: ========== Exception during initialization ==========');
      print('❌ iOS DEBUG [LocationNotifier]: Error type: ${error.runtimeType}');
      print('❌ iOS DEBUG [LocationNotifier]: Error: $error');
      print('❌ iOS DEBUG [LocationNotifier]: Stack trace:');
      print(stackTrace.toString().split('\n').take(10).join('\n'));
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Request location permission
  Future<void> requestPermission() async {
    try {
      print('🔍 iOS DEBUG [LocationNotifier]: ========== Manual permission request ==========');
      state = const AsyncValue.loading();

      final permission = await _locationService.requestPermission();
      print('🔍 iOS DEBUG [LocationNotifier]: Permission result = $permission');

      if (permission == LocationPermission.denied) {
        print('❌ iOS DEBUG [LocationNotifier]: Permission DENIED by user');
        state = AsyncValue.error('Location permission denied', StackTrace.current);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ iOS DEBUG [LocationNotifier]: Permission DENIED FOREVER');
        print('   User must enable in Settings app');
        state = AsyncValue.error('Location permission permanently denied. Enable in Settings.', StackTrace.current);
        return;
      }

      print('✅ iOS DEBUG [LocationNotifier]: Permission GRANTED! Getting location...');

      // Get location after permission granted
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        print('✅ iOS DEBUG [LocationNotifier]: Got location after permission grant:');
        print('   Lat=${location.latitude}, Lng=${location.longitude}');
        state = AsyncValue.data(location);

        // Start tracking now that we have permission
        print('🔍 iOS DEBUG [LocationNotifier]: Starting location tracking stream...');
        _locationSubscription = _locationService.locationStream.listen(
          (location) {
            print('📍 iOS DEBUG [LocationNotifier]: Stream update:');
            print('   Lat=${location.latitude}, Lng=${location.longitude}');
            state = AsyncValue.data(location);
          },
          onError: (error, stackTrace) {
            print('❌ iOS DEBUG [LocationNotifier]: Stream error: $error');
            state = AsyncValue.error(error, stackTrace);
          },
        );
      } else {
        print('❌ iOS DEBUG [LocationNotifier]: Could not get location after permission grant');
        state = AsyncValue.error('Could not get location', StackTrace.current);
      }
    } catch (error, stackTrace) {
      print('❌ iOS DEBUG [LocationNotifier]: Exception during permission request: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Start location tracking
  Future<void> startTracking() async {
    try {
      print('🔄 iOS DEBUG [LocationNotifier]: Starting location tracking...');
      await _locationService.startLocationTracking();
      print('✅ iOS DEBUG [LocationNotifier]: Location tracking started');
    } catch (error, stackTrace) {
      print('❌ iOS DEBUG [LocationNotifier]: Error starting tracking: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    try {
      print('🛑 iOS DEBUG [LocationNotifier]: Stopping location tracking...');
      await _locationService.stopLocationTracking();
      print('✅ iOS DEBUG [LocationNotifier]: Location tracking stopped');
    } catch (error, stackTrace) {
      print('❌ iOS DEBUG [LocationNotifier]: Error stopping tracking: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Get current location once
  Future<void> getCurrentLocation() async {
    try {
      print('🔍 iOS DEBUG [LocationNotifier]: Getting current location (one-time)...');
      state = const AsyncValue.loading();
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        print('✅ iOS DEBUG [LocationNotifier]: Got current location:');
        print('   Lat=${location.latitude}, Lng=${location.longitude}');
        state = AsyncValue.data(location);
      } else {
        print('❌ iOS DEBUG [LocationNotifier]: Could not get current location');
        state = AsyncValue.error('Could not get current location', StackTrace.current);
      }
    } catch (error, stackTrace) {
      print('❌ iOS DEBUG [LocationNotifier]: Error getting current location: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  @override
  void dispose() {
    print('🗑️ iOS DEBUG [LocationNotifier]: Disposing...');
    _locationSubscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}

/// Provider for location notifier
final locationNotifierProvider = StateNotifierProvider<LocationNotifier, AsyncValue<LocationData?>>((ref) {
  print('📍 iOS DEBUG [Provider]: Creating LocationNotifier instance');
  final locationService = ref.watch(locationServiceProvider);
  return LocationNotifier(locationService);
});
