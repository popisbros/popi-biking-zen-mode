import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_data.dart';
import '../services/location_service.dart';

/// Provider for location service
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Provider for current location
final currentLocationProvider = StreamProvider<LocationData?>((ref) {
  final locationService = ref.watch(locationServiceProvider);
  return locationService.locationStream;
});

/// Provider for location permission status
final locationPermissionProvider = FutureProvider<LocationPermission>((ref) async {
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.checkPermission();
});

/// Provider for location service enabled status
final locationServiceEnabledProvider = FutureProvider<bool>((ref) async {
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.isLocationServiceEnabled();
});

/// Notifier for managing location state
class LocationNotifier extends StateNotifier<AsyncValue<LocationData?>> {
  final LocationService _locationService;
  StreamSubscription<LocationData>? _locationSubscription;

  LocationNotifier(this._locationService) : super(const AsyncValue.loading()) {
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      // Check if location service is enabled
      final isEnabled = await _locationService.isLocationServiceEnabled();
      if (!isEnabled) {
        state = AsyncValue.error('Location services are disabled', StackTrace.current);
        return;
      }

      // Check permission
      final permission = await _locationService.checkPermission();
      if (permission == LocationPermission.denied) {
        state = AsyncValue.error('Location permission denied', StackTrace.current);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        state = AsyncValue.error('Location permission permanently denied', StackTrace.current);
        return;
      }

      // Get initial location
      final initialLocation = await _locationService.getCurrentPosition();
      if (initialLocation != null) {
        state = AsyncValue.data(initialLocation);
      } else {
        state = AsyncValue.error('Could not get initial location', StackTrace.current);
      }

      // Start listening to location updates
      _locationSubscription = _locationService.locationStream.listen(
        (location) {
          state = AsyncValue.data(location);
        },
        onError: (error, stackTrace) {
          state = AsyncValue.error(error, stackTrace);
        },
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Request location permission
  Future<void> requestPermission() async {
    try {
      state = const AsyncValue.loading();
      final permission = await _locationService.requestPermission();
      
      if (permission == LocationPermission.denied) {
        state = AsyncValue.error('Location permission denied', StackTrace.current);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        state = AsyncValue.error('Location permission permanently denied', StackTrace.current);
        return;
      }

      // Get location after permission granted
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        state = AsyncValue.data(location);
      } else {
        state = AsyncValue.error('Could not get location', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Start location tracking
  Future<void> startTracking() async {
    try {
      await _locationService.startLocationTracking();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    try {
      await _locationService.stopLocationTracking();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Get current location once
  Future<void> getCurrentLocation() async {
    try {
      state = const AsyncValue.loading();
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        state = AsyncValue.data(location);
      } else {
        state = AsyncValue.error('Could not get current location', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}

/// Provider for location notifier
final locationNotifierProvider = StateNotifierProvider<LocationNotifier, AsyncValue<LocationData?>>((ref) {
  final locationService = ref.watch(locationServiceProvider);
  return LocationNotifier(locationService);
});
