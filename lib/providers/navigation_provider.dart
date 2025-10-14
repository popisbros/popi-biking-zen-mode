import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_data.dart';
import '../models/navigation_state.dart';
import '../models/maneuver_instruction.dart';
import '../services/routing_service.dart';
import '../services/navigation_engine.dart';
import '../services/location_service.dart';
import '../utils/app_logger.dart';

/// Provider for navigation state
final navigationProvider = NotifierProvider<NavigationNotifier, NavigationState>(
  NavigationNotifier.new,
);

/// Notifier for managing turn-by-turn navigation state
class NavigationNotifier extends Notifier<NavigationState> {
  StreamSubscription<LocationData>? _locationSubscription;
  List<ManeuverInstruction> _detectedManeuvers = [];
  DateTime? _lastUpdateTime;

  @override
  NavigationState build() {
    // Clean up subscription when provider is disposed
    ref.onDispose(() {
      _locationSubscription?.cancel();
      _locationSubscription = null;
    });

    return NavigationState.initial();
  }

  /// Start turn-by-turn navigation with given route
  void startNavigation(RouteResult route) {
    AppLogger.separator('Starting Turn-by-Turn Navigation');
    AppLogger.success('Starting navigation', tag: 'NAVIGATION', data: {
      'routeType': route.type.name,
      'points': route.points.length,
      'distance': route.distanceKm,
      'duration': route.durationMin,
    });

    // Detect all maneuvers in the route
    _detectedManeuvers = NavigationEngine.detectManeuvers(route.points);
    AppLogger.debug('Maneuvers detected', tag: 'NAVIGATION', data: {
      'count': _detectedManeuvers.length,
    });

    // Initialize navigation state
    final initialPosition = route.points.first;
    final nextManeuver = NavigationEngine.findNextManeuver(_detectedManeuvers, 0);

    state = NavigationState(
      isNavigating: true,
      activeRoute: route,
      currentPosition: initialPosition,
      currentSegmentIndex: 0,
      nextManeuver: nextManeuver,
      distanceToNextManeuver: nextManeuver != null
          ? NavigationEngine.calculateDistanceToManeuver(
              initialPosition,
              route.points,
              0,
              nextManeuver,
            )
          : 0,
      totalDistanceRemaining: route.distanceMeters,
      estimatedTimeRemaining: route.durationMillis ~/ 1000,
      isOffRoute: false,
      showingOffRouteDialog: false,
      lastUpdateTime: DateTime.now(),
    );

    // Start listening to location updates
    _startLocationTracking();

    AppLogger.success('Navigation started', tag: 'NAVIGATION');
    AppLogger.separator();
  }

  /// Stop navigation
  void stopNavigation() {
    AppLogger.debug('Stopping navigation', tag: 'NAVIGATION');

    _locationSubscription?.cancel();
    _locationSubscription = null;
    _detectedManeuvers = [];

    state = NavigationState.initial();

    AppLogger.success('Navigation stopped', tag: 'NAVIGATION');
  }

  /// Start listening to location updates from LocationService
  void _startLocationTracking() {
    final locationService = LocationService();

    AppLogger.debug('Starting location tracking for navigation', tag: 'NAVIGATION');

    _locationSubscription = locationService.locationStream.listen(
      (locationData) {
        _onLocationUpdate(locationData);
      },
      onError: (error) {
        AppLogger.error('Location stream error during navigation', tag: 'NAVIGATION', error: error);
      },
      onDone: () {
        AppLogger.debug('Location stream completed', tag: 'NAVIGATION');
      },
    );

    AppLogger.success('Location tracking active', tag: 'NAVIGATION');
  }

  /// Handle location update from GPS
  void _onLocationUpdate(LocationData locationData) {
    if (!state.isNavigating || state.activeRoute == null) {
      return;
    }

    // Throttle updates to max once per 1 second for performance
    final now = DateTime.now();
    if (_lastUpdateTime != null && now.difference(_lastUpdateTime!).inSeconds < 1) {
      return; // Skip this update
    }
    _lastUpdateTime = now;

    final currentPos = LatLng(locationData.latitude, locationData.longitude);
    final route = state.activeRoute!;

    // Find closest segment on route
    final closestSegment = NavigationEngine.findClosestSegment(currentPos, route.points);

    // Check if off route and get distance
    final isOffRoute = NavigationEngine.isOffRoute(currentPos, route.points);
    final offRouteDistance = NavigationEngine.getDistanceToRoute(currentPos, route.points);

    // Calculate remaining distance
    final remainingDistance = NavigationEngine.calculateRemainingDistance(
      currentPos,
      route.points,
      closestSegment,
    );

    // Find next maneuver
    final nextManeuver = NavigationEngine.findNextManeuver(
      _detectedManeuvers,
      closestSegment,
    );

    // Calculate distance to next maneuver
    final distanceToManeuver = nextManeuver != null
        ? NavigationEngine.calculateDistanceToManeuver(
            currentPos,
            route.points,
            closestSegment,
            nextManeuver,
          )
        : 0;

    // Estimate time remaining
    final speed = locationData.speed ?? 0.0;
    final timeRemaining = NavigationEngine.estimateTimeRemaining(
      remainingDistance,
      speed,
    );

    // Check if arrived (within 20m of destination)
    final distanceToEnd = NavigationEngine.calculateRemainingDistance(
      currentPos,
      route.points,
      route.points.length - 2,
    );
    final hasArrived = distanceToEnd < 20;

    // Update state
    state = state.copyWith(
      currentPosition: currentPos,
      currentSpeed: speed.toDouble(),
      currentHeading: locationData.heading,
      currentSegmentIndex: closestSegment,
      nextManeuver: nextManeuver,
      distanceToNextManeuver: distanceToManeuver.toDouble(),
      totalDistanceRemaining: remainingDistance.toDouble(),
      estimatedTimeRemaining: timeRemaining,
      isOffRoute: isOffRoute,
      offRouteDistanceMeters: offRouteDistance,
      lastUpdateTime: DateTime.now(),
    );

    // Log navigation update (every update for debugging)
    AppLogger.debug('Navigation update', tag: 'NAVIGATION', data: {
      'segment': closestSegment,
      'nextManeuver': nextManeuver?.type.name ?? 'none',
      'distanceToNext': '${distanceToManeuver.toStringAsFixed(0)}m',
      'remaining': '${(remainingDistance / 1000).toStringAsFixed(2)}km',
      'speed': '${(speed * 3.6).toStringAsFixed(1)}km/h',
      'offRoute': isOffRoute,
    });

    // Handle arrival
    if (hasArrived) {
      AppLogger.success('Arrived at destination!', tag: 'NAVIGATION');
      _onArrival();
    }

    // Show off-route dialog if needed
    if (isOffRoute && !state.showingOffRouteDialog) {
      _showOffRouteAlert();
    }
  }

  /// Handle arrival at destination
  void _onArrival() {
    // Keep navigation active but mark as arrived
    // User can manually stop navigation
    AppLogger.success('Arrived at destination', tag: 'NAVIGATION');
  }

  /// Show off-route alert (state flag for UI to show dialog)
  void _showOffRouteAlert() {
    AppLogger.warning('User went off route', tag: 'NAVIGATION');
    state = state.copyWith(showingOffRouteDialog: true);
  }

  /// User dismissed off-route dialog without recalculating
  void dismissOffRouteDialog() {
    AppLogger.debug('Off-route dialog dismissed', tag: 'NAVIGATION');
    state = state.copyWith(
      showingOffRouteDialog: false,
      isOffRoute: false, // Reset off-route flag
    );
  }

  /// Recalculate route from current position
  Future<void> recalculateRoute() async {
    if (!state.isNavigating || state.activeRoute == null || state.currentPosition == null) {
      return;
    }

    AppLogger.separator('Recalculating Route');
    AppLogger.debug('Recalculating from current position', tag: 'NAVIGATION');

    final currentPos = state.currentPosition!;
    final destination = state.activeRoute!.points.last;
    final routeType = state.activeRoute!.type;

    // Dismiss dialog immediately
    state = state.copyWith(showingOffRouteDialog: false);

    try {
      final routingService = RoutingService();

      // Calculate new route based on original route type
      final routes = await routingService.calculateMultipleRoutes(
        startLat: currentPos.latitude,
        startLon: currentPos.longitude,
        endLat: destination.latitude,
        endLon: destination.longitude,
      );

      if (routes == null || routes.isEmpty) {
        AppLogger.error('Failed to recalculate route', tag: 'NAVIGATION');
        state = state.copyWith(isOffRoute: false); // Reset flag
        return;
      }

      // Find route matching original type, or use first available
      final newRoute = routes.firstWhere(
        (r) => r.type == routeType,
        orElse: () => routes.first,
      );

      AppLogger.success('Route recalculated', tag: 'NAVIGATION', data: {
        'type': newRoute.type.name,
        'distance': newRoute.distanceKm,
        'duration': newRoute.durationMin,
      });

      // Restart navigation with new route
      stopNavigation();
      startNavigation(newRoute);

      AppLogger.separator();
    } catch (e, stackTrace) {
      AppLogger.error('Route recalculation failed', tag: 'NAVIGATION', error: e, stackTrace: stackTrace);
      state = state.copyWith(
        showingOffRouteDialog: false,
        isOffRoute: false,
      );
    }
  }

  /// Get formatted instruction for voice guidance
  String? getVoiceInstruction() {
    if (!state.isNavigating || state.nextManeuver == null) {
      return null;
    }

    final maneuver = state.nextManeuver!;
    final distance = state.distanceToNextManeuver;

    // Format distance for voice
    String distanceText;
    if (distance < 50) {
      distanceText = 'now';
    } else if (distance < 100) {
      distanceText = 'in 50 meters';
    } else if (distance < 500) {
      distanceText = 'in ${(distance / 100).round() * 100} meters';
    } else if (distance < 1000) {
      distanceText = 'in ${(distance / 100).round() * 100} meters';
    } else {
      distanceText = 'in ${(distance / 1000).toStringAsFixed(1)} kilometers';
    }

    return '$distanceText, ${maneuver.voiceInstruction}';
  }
}
