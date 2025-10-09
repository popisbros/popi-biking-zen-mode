import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_data.dart';
import '../services/location_service.dart';
import '../utils/app_logger.dart';
import 'debug_provider.dart';

/// Provider for location service
final locationServiceProvider = Provider<LocationService>((ref) {
  AppLogger.location('Creating LocationService instance');
  return LocationService();
});

/// Provider for current location
final currentLocationProvider = StreamProvider<LocationData?>((ref) {
  AppLogger.location('Setting up current location stream provider');
  final locationService = ref.watch(locationServiceProvider);
  return locationService.locationStream;
});

/// Provider for location permission status
final locationPermissionProvider = FutureProvider<LocationPermission>((ref) async {
  AppLogger.location('Checking location permission');
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.checkPermission();
});

/// Provider for location service enabled status
final locationServiceEnabledProvider = FutureProvider<bool>((ref) async {
  AppLogger.location('Checking if location service is enabled');
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.isLocationServiceEnabled();
});

/// Notifier for managing location state
class LocationNotifier extends Notifier<AsyncValue<LocationData?>> {
  late final LocationService _locationService;
  StreamSubscription<LocationData>? _locationSubscription;

  @override
  AsyncValue<LocationData?> build() {
    AppLogger.location('Build called, initializing...');
    _locationService = ref.watch(locationServiceProvider);
    _initializeLocation();
    return const AsyncValue.loading();
  }

  Future<void> _initializeLocation() async {
    try {
      AppLogger.separator('Location Initialization');

      // Check if location service is enabled
      final isEnabled = await _locationService.isLocationServiceEnabled();
      AppLogger.location('Service enabled', data: {'enabled': isEnabled});

      if (!isEnabled) {
        AppLogger.error('Location services DISABLED on device', tag: 'LOCATION');
        state = AsyncValue.error('Location services are disabled. Please enable in Settings.', StackTrace.current);
        return;
      }

      // Try to get location - this will trigger iOS permission dialog automatically
      AppLogger.location('Attempting to get initial location (will trigger iOS permission dialog if needed)');

      final initialLocation = await _locationService.getCurrentPosition();

      if (initialLocation != null) {
        AppLogger.success('Got initial location', tag: 'LOCATION', data: {
          'lat': initialLocation.latitude.toStringAsFixed(6),
          'lng': initialLocation.longitude.toStringAsFixed(6),
          'accuracy': '${initialLocation.accuracy?.toStringAsFixed(1) ?? 'unknown'}m'
        });
        state = AsyncValue.data(initialLocation);

        // Start continuous location tracking
        AppLogger.location('Starting continuous location tracking');
        await _locationService.startLocationTracking();

        // Start listening to location updates
        AppLogger.location('Setting up location stream listener');
        _locationSubscription = _locationService.locationStream.listen(
          (location) {
            AppLogger.debug('Location update received', tag: 'LOCATION', data: {
              'lat': location.latitude.toStringAsFixed(6),
              'lng': location.longitude.toStringAsFixed(6),
              'acc': '${location.accuracy?.toStringAsFixed(1) ?? 'unknown'}m'
            });
            // Visible debug for GPS location
            ref.read(debugProvider.notifier).addDebugMessage(
              'GPS: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)} '
              '±${location.accuracy?.toStringAsFixed(1) ?? '?'}m '
              '${location.speed != null ? "${(location.speed! * 3.6).toStringAsFixed(1)}km/h" : "0km/h"}'
            );
            state = AsyncValue.data(location);
          },
          onError: (error, stackTrace) {
            AppLogger.error('Location stream error', tag: 'LOCATION', error: error, stackTrace: stackTrace);
            state = AsyncValue.error(error, stackTrace);
          },
          onDone: () {
            AppLogger.location('Location stream completed');
          },
        );
        AppLogger.success('Location stream subscription active', tag: 'LOCATION');
      } else {
        AppLogger.error('Could not get initial location (permission likely DENIED)', tag: 'LOCATION');
        state = AsyncValue.error('Location permission required. Please enable in Settings.', StackTrace.current);
      }

      AppLogger.separator();
    } catch (error, stackTrace) {
      AppLogger.error('Exception during location initialization', tag: 'LOCATION', error: error, stackTrace: stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Request location permission
  Future<void> requestPermission() async {
    try {
      AppLogger.separator('Manual Permission Request');
      state = const AsyncValue.loading();

      final permission = await _locationService.requestPermission();
      AppLogger.location('Permission result', data: {'permission': permission.toString()});

      if (permission == LocationPermission.denied) {
        AppLogger.error('Permission DENIED by user', tag: 'LOCATION');
        state = AsyncValue.error('Location permission denied', StackTrace.current);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.error('Permission DENIED FOREVER - User must enable in Settings', tag: 'LOCATION');
        state = AsyncValue.error('Location permission permanently denied. Enable in Settings.', StackTrace.current);
        return;
      }

      AppLogger.success('Permission GRANTED', tag: 'LOCATION');

      // Get location after permission granted
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        AppLogger.success('Got location after permission grant', tag: 'LOCATION', data: {
          'lat': location.latitude.toStringAsFixed(6),
          'lng': location.longitude.toStringAsFixed(6)
        });
        state = AsyncValue.data(location);

        // Start tracking now that we have permission
        AppLogger.location('Starting location tracking stream');
        _locationSubscription = _locationService.locationStream.listen(
          (location) {
            AppLogger.debug('Stream update', tag: 'LOCATION', data: {
              'lat': location.latitude.toStringAsFixed(6),
              'lng': location.longitude.toStringAsFixed(6)
            });
            state = AsyncValue.data(location);
          },
          onError: (error, stackTrace) {
            AppLogger.error('Stream error', tag: 'LOCATION', error: error, stackTrace: stackTrace);
            state = AsyncValue.error(error, stackTrace);
          },
        );
      } else {
        AppLogger.error('Could not get location after permission grant', tag: 'LOCATION');
        state = AsyncValue.error('Could not get location', StackTrace.current);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Exception during permission request', tag: 'LOCATION', error: error, stackTrace: stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Start location tracking
  Future<void> startTracking() async {
    try {
      AppLogger.location('Starting location tracking');
      await _locationService.startLocationTracking();
      AppLogger.success('Location tracking started', tag: 'LOCATION');
    } catch (error, stackTrace) {
      AppLogger.error('Error starting tracking', tag: 'LOCATION', error: error, stackTrace: stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    try {
      AppLogger.location('Stopping location tracking');
      await _locationService.stopLocationTracking();
      AppLogger.success('Location tracking stopped', tag: 'LOCATION');
    } catch (error, stackTrace) {
      AppLogger.error('Error stopping tracking', tag: 'LOCATION', error: error, stackTrace: stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Get current location once
  Future<void> getCurrentLocation() async {
    try {
      AppLogger.location('Getting current location (one-time)');
      state = const AsyncValue.loading();
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        AppLogger.success('Got current location', tag: 'LOCATION', data: {
          'lat': location.latitude.toStringAsFixed(6),
          'lng': location.longitude.toStringAsFixed(6)
        });
        state = AsyncValue.data(location);
      } else {
        AppLogger.error('Could not get current location', tag: 'LOCATION');
        state = AsyncValue.error('Could not get current location', StackTrace.current);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error getting current location', tag: 'LOCATION', error: error, stackTrace: stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  void disposeLocation() {
    AppLogger.location('Disposing LocationNotifier');
    _locationSubscription?.cancel();
    _locationService.dispose();
  }
}

/// Provider for location notifier
final locationNotifierProvider = NotifierProvider<LocationNotifier, AsyncValue<LocationData?>>(LocationNotifier.new);
