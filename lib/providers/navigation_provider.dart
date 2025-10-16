import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_data.dart';
import '../models/navigation_state.dart';
import '../models/maneuver_instruction.dart';
import '../models/community_warning.dart';
import '../services/routing_service.dart';
import '../services/navigation_engine.dart';
import '../services/location_service.dart';
import '../services/toast_service.dart';
import '../services/route_hazard_detector.dart';
import '../utils/app_logger.dart';
import 'community_provider.dart';

/// Provider for navigation state
final navigationProvider = NotifierProvider<NavigationNotifier, NavigationState>(
  NavigationNotifier.new,
);

/// Notifier for managing turn-by-turn navigation state
class NavigationNotifier extends Notifier<NavigationState> {
  StreamSubscription<LocationData>? _locationSubscription;
  List<ManeuverInstruction> _detectedManeuvers = [];
  DateTime? _lastUpdateTime;

  // Rerouting state
  DateTime? _lastRerouteTime;
  LatLng? _lastReroutePosition;
  bool _isRerouting = false;

  // Arrival detection constants
  static const double _arrivalDistanceThreshold = 10.0; // 10 meters to destination
  static const double _arrivalSpeedThreshold = 5.0; // 5 km/h (slow/stopped)
  static const int _arrivalConfirmationSeconds = 3; // Stay in zone for 3 seconds
  static const double _arrivalGpsAccuracyThreshold = 10.0; // GPS accuracy < 10m

  // Rerouting constants
  static const int _rerouteCooldownSeconds = 10; // Minimum 10 seconds between reroutes
  static const double _reroutePositionThreshold = 10.0; // 10 meters from last reroute position

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

    // Detect hazards on route
    // Try bounds provider first (likely loaded), then all warnings provider
    List<CommunityWarning> warnings = [];

    final boundsWarnings = ref.read(communityWarningsBoundsNotifierProvider);
    final allWarnings = ref.read(communityWarningsNotifierProvider);

    print('[HAZARD DEBUG PROVIDER] boundsWarnings.hasValue: ${boundsWarnings.hasValue}, count: ${boundsWarnings.value?.length ?? 0}');
    print('[HAZARD DEBUG PROVIDER] allWarnings.hasValue: ${allWarnings.hasValue}, count: ${allWarnings.value?.length ?? 0}');

    // Prefer all warnings (complete set) if available, otherwise use bounds
    if (allWarnings.hasValue && allWarnings.value != null && allWarnings.value!.isNotEmpty) {
      warnings = allWarnings.value!;
      print('[HAZARD DEBUG PROVIDER] Using ALL warnings: ${warnings.length}');
    } else if (boundsWarnings.hasValue && boundsWarnings.value != null && boundsWarnings.value!.isNotEmpty) {
      warnings = boundsWarnings.value!;
      print('[HAZARD DEBUG PROVIDER] Using BOUNDS warnings: ${warnings.length}');
    } else {
      print('[HAZARD DEBUG PROVIDER] No warnings available from either provider');
    }

    List<RouteHazard> routeHazards = [];

    if (warnings.isNotEmpty) {
      AppLogger.debug('Detecting hazards on route', tag: 'NAVIGATION', data: {
        'totalWarnings': warnings.length,
      });

      routeHazards = RouteHazardDetector.detectHazardsOnRoute(
        routePoints: route.points,
        allHazards: warnings,
      );

      print('[HAZARD DEBUG PROVIDER] Hazards detected: ${routeHazards.length}');

      if (routeHazards.isNotEmpty) {
        AppLogger.success('Found ${routeHazards.length} hazards on route', tag: 'NAVIGATION');
        for (var i = 0; i < routeHazards.length; i++) {
          print('[HAZARD DEBUG PROVIDER] Hazard $i: ${routeHazards[i].warning.title} at ${routeHazards[i].distanceAlongRoute.toStringAsFixed(0)}m');
        }
      } else {
        AppLogger.debug('No hazards found on route', tag: 'NAVIGATION');
      }
    } else {
      AppLogger.warning('No community warnings available for hazard detection', tag: 'NAVIGATION');
    }

    print('[HAZARD DEBUG PROVIDER] Creating route with ${routeHazards.length} hazards');

    // Update route with detected hazards
    final routeWithHazards = route.copyWithHazards(routeHazards);

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
      activeRoute: routeWithHazards,
      currentPosition: initialPosition,
      currentSegmentIndex: 0,
      allManeuvers: _detectedManeuvers,
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

    // Start listening to location updates (fire and forget, don't block navigation start)
    _startLocationTracking().then((_) {
      print('[GPS TRACKING] Location tracking initialization complete');
    }).catchError((error) {
      print('[GPS TRACKING] ERROR starting location tracking: $error');
      AppLogger.error('Failed to start location tracking', tag: 'NAVIGATION', error: error);
    });

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

  /// Dismiss off-route dialog without rerouting
  void dismissOffRouteDialog() {
    AppLogger.debug('Dismissing off-route dialog', tag: 'NAVIGATION');
    state = state.copyWith(
      showingOffRouteDialog: false,
    );
  }

  /// Manually trigger route recalculation from current position
  Future<void> recalculateRoute() async {
    AppLogger.debug('Manual route recalculation requested', tag: 'NAVIGATION');

    if (!state.isNavigating || state.currentPosition == null) {
      AppLogger.warning('Cannot recalculate - not navigating or no position', tag: 'NAVIGATION');
      ToastService.warning('Cannot recalculate route - no current position');
      return;
    }

    // Dismiss dialog first
    state = state.copyWith(
      showingOffRouteDialog: false,
    );

    // Trigger rerouting
    await _handleAutomaticRerouting(state.currentPosition!);
  }

  /// Start listening to location updates from LocationService
  Future<void> _startLocationTracking() async {
    final locationService = LocationService();

    AppLogger.debug('Starting location tracking for navigation', tag: 'NAVIGATION');

    // IMPORTANT: Start the GPS position stream in LocationService (await it!)
    print('[GPS TRACKING] About to call startLocationTracking()...');
    await locationService.startLocationTracking();
    print('[GPS TRACKING] startLocationTracking() completed');
    AppLogger.debug('Called LocationService.startLocationTracking()', tag: 'NAVIGATION');

    _locationSubscription = locationService.locationStream.listen(
      (locationData) {
        _onLocationUpdate(locationData);
      },
      onError: (error) {
        AppLogger.error('Location stream error during navigation', tag: 'NAVIGATION', error: error);
        print('[GPS TRACKING] Stream error: $error');
      },
      onDone: () {
        AppLogger.debug('Location stream completed', tag: 'NAVIGATION');
        print('[GPS TRACKING] Stream completed/done');
      },
    );

    AppLogger.success('Location tracking active', tag: 'NAVIGATION');
    print('[GPS TRACKING] Subscribed to location stream');
  }

  /// Handle location update from GPS
  void _onLocationUpdate(LocationData locationData) {
    print('[GPS RAW] Location update received: lat=${locationData.latitude}, lon=${locationData.longitude}');

    if (!state.isNavigating || state.activeRoute == null) {
      print('[GPS RAW] Skipping - not navigating or no route');
      return;
    }

    // Throttle updates to max once per 3 seconds
    final now = DateTime.now();
    if (_lastUpdateTime != null && now.difference(_lastUpdateTime!).inSeconds < 3) {
      print('[GPS RAW] Throttled - too soon (${now.difference(_lastUpdateTime!).inSeconds}s since last)');
      return; // Skip this update
    }
    _lastUpdateTime = now;

    print('[NAV UPDATE] === Processing navigation update at ${now.toIso8601String()} ===');

    final currentPos = LatLng(locationData.latitude, locationData.longitude);
    final route = state.activeRoute!;

    // Find closest segment on route
    final closestSegment = NavigationEngine.findClosestSegment(currentPos, route.points);

    // Check if off route and get distance
    final isOffRoute = NavigationEngine.isOffRoute(currentPos, route.points);
    final offRouteDistance = NavigationEngine.getDistanceToRoute(currentPos, route.points);

    // Debug: Log off-route status every update
    print('[OFF-ROUTE DEBUG] Distance to route: ${offRouteDistance.toStringAsFixed(1)}m, isOffRoute: $isOffRoute (threshold: 10m)');

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

    // Enhanced arrival detection
    final distanceToDestination = remainingDistance;
    final speedKmh = speed * 3.6; // Convert m/s to km/h
    final gpsAccuracy = locationData.accuracy ?? 999;

    // Check arrival conditions
    final bool withinArrivalZone = distanceToDestination < _arrivalDistanceThreshold;
    final bool movingSlowly = speedKmh < _arrivalSpeedThreshold;
    final bool goodGpsAccuracy = gpsAccuracy < _arrivalGpsAccuracyThreshold;

    // Determine arrival states
    bool isApproaching = false;
    bool hasArrived = false;
    DateTime? arrivalZoneEntry = state.arrivalZoneEntryTime;

    if (withinArrivalZone && goodGpsAccuracy) {
      // User is in arrival zone with good GPS
      if (arrivalZoneEntry == null) {
        // Just entered arrival zone
        arrivalZoneEntry = DateTime.now();
        isApproaching = true;
        AppLogger.success('Approaching destination...', tag: 'NAVIGATION', data: {
          'distance': '${distanceToDestination.toStringAsFixed(1)}m',
          'speed': '${speedKmh.toStringAsFixed(1)}km/h',
        });
      } else {
        // Already in arrival zone - check if confirmed
        final timeInZone = DateTime.now().difference(arrivalZoneEntry).inSeconds;

        if (timeInZone >= _arrivalConfirmationSeconds && movingSlowly) {
          // Confirmed arrival: in zone for 3+ seconds AND moving slowly/stopped
          hasArrived = true;
          AppLogger.success('ARRIVED at destination!', tag: 'NAVIGATION', data: {
            'timeInZone': '${timeInZone}s',
            'finalDistance': '${distanceToDestination.toStringAsFixed(1)}m',
          });
        } else {
          // Still approaching
          isApproaching = true;
        }
      }
    } else {
      // Outside arrival zone or poor GPS - reset
      arrivalZoneEntry = null;
      isApproaching = false;
    }

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
      isApproachingDestination: isApproaching,
      hasArrived: hasArrived,
      arrivalZoneEntryTime: arrivalZoneEntry,
    );

    // Log navigation update (every update for debugging)
    AppLogger.debug('Navigation update', tag: 'NAVIGATION', data: {
      'segment': closestSegment,
      'nextManeuver': nextManeuver?.type.name ?? 'none',
      'distanceToNext': '${distanceToManeuver.toStringAsFixed(0)}m',
      'remaining': '${(remainingDistance / 1000).toStringAsFixed(2)}km',
      'speed': '${speedKmh.toStringAsFixed(1)}km/h',
      'offRoute': isOffRoute,
      'approaching': isApproaching,
      'arrived': hasArrived,
    });

    // Handle arrival
    if (hasArrived && !state.hasArrived) {
      // First time arrival detected
      _onArrival();
    }

    // Automatic rerouting if off route
    if (isOffRoute && !_isRerouting) {
      print('[REROUTE DEBUG] Off route detected! Distance: ${offRouteDistance.toStringAsFixed(1)}m');
      print('[REROUTE DEBUG] Calling _handleAutomaticRerouting');
      _handleAutomaticRerouting(currentPos);
    } else if (isOffRoute && _isRerouting) {
      print('[REROUTE DEBUG] Off route but already rerouting...');
    }
  }

  /// Handle arrival at destination
  void _onArrival() {
    // Keep navigation active but mark as arrived
    // User can manually stop navigation
    AppLogger.success('Arrived at destination', tag: 'NAVIGATION');
  }

  /// Handle automatic rerouting when off route
  Future<void> _handleAutomaticRerouting(LatLng currentPos) async {
    print('[REROUTE DEBUG] _handleAutomaticRerouting called');

    // Check if we're still navigating
    if (!state.isNavigating || state.activeRoute == null) {
      print('[REROUTE DEBUG] Not navigating or no active route, aborting');
      return;
    }

    // Check cooldown period
    if (_lastRerouteTime != null) {
      final timeSinceLastReroute = DateTime.now().difference(_lastRerouteTime!).inSeconds;
      print('[REROUTE DEBUG] Time since last reroute: ${timeSinceLastReroute}s (cooldown: ${_rerouteCooldownSeconds}s)');
      if (timeSinceLastReroute < _rerouteCooldownSeconds) {
        final remainingSeconds = _rerouteCooldownSeconds - timeSinceLastReroute;
        ToastService.info('Rerouting on cooldown, wait ${remainingSeconds}s');
        AppLogger.debug('Rerouting cooldown active', tag: 'NAVIGATION', data: {
          'timeSince': '${timeSinceLastReroute}s',
          'cooldown': '${_rerouteCooldownSeconds}s',
        });
        print('[REROUTE DEBUG] Cooldown active, aborting');
        return;
      }
    }

    // Check position-based duplicate detection
    if (_lastReroutePosition != null) {
      final distance = const Distance().as(
        LengthUnit.Meter,
        currentPos,
        _lastReroutePosition!,
      );

      print('[REROUTE DEBUG] Distance from last reroute position: ${distance.toStringAsFixed(1)}m (threshold: ${_reroutePositionThreshold}m)');

      if (distance < _reroutePositionThreshold) {
        // Same position as last successful reroute - abort
        final metersNeeded = (_reroutePositionThreshold - distance).toInt();
        ToastService.warning('Rerouting blocked: Move ${metersNeeded}m+ more');
        AppLogger.warning('Rerouting aborted - same position', tag: 'NAVIGATION', data: {
          'distance': '${distance.toStringAsFixed(1)}m',
          'threshold': '${_reroutePositionThreshold}m',
        });

        print('[REROUTE DEBUG] Same position, aborting');

        // Update cooldown to prevent spam
        _lastRerouteTime = DateTime.now();
        return;
      }
    }

    // Start rerouting
    print('[REROUTE DEBUG] Starting reroute process...');
    _isRerouting = true;
    final routeType = state.activeRoute!.type;
    final destination = state.activeRoute!.points.last;

    // Show toast notification
    final routeTypeName = routeType == RouteType.fastest
        ? 'Fastest'
        : routeType == RouteType.safest
            ? 'Safest'
            : 'Shortest';
    print('[REROUTE DEBUG] Showing toast: Calculating new $routeTypeName route...');
    ToastService.info('Calculating new $routeTypeName route...');

    AppLogger.separator('Automatic Rerouting');
    AppLogger.debug('Starting automatic reroute', tag: 'NAVIGATION', data: {
      'routeType': routeType.name,
      'from': '${currentPos.latitude},${currentPos.longitude}',
      'to': '${destination.latitude},${destination.longitude}',
    });
    print('[REROUTE DEBUG] Calling routing service...');

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
        AppLogger.error('Failed to calculate new route', tag: 'NAVIGATION');
        ToastService.error('Failed to recalculate route');

        // Update cooldown even on failure
        _lastRerouteTime = DateTime.now();
        _isRerouting = false;
        return;
      }

      // Find route matching original type, or use first available
      final newRoute = routes.firstWhere(
        (r) => r.type == routeType,
        orElse: () => routes.first,
      );

      AppLogger.success('New route calculated', tag: 'NAVIGATION', data: {
        'type': newRoute.type.name,
        'distance': newRoute.distanceKm,
        'duration': newRoute.durationMin,
      });

      // Show success toast
      ToastService.success('Route recalculated');

      // Record successful reroute position and time
      _lastReroutePosition = currentPos;
      _lastRerouteTime = DateTime.now();

      // Restart navigation with new route
      stopNavigation();
      startNavigation(newRoute);

      AppLogger.separator();
    } catch (e, stackTrace) {
      AppLogger.error('Automatic rerouting failed', tag: 'NAVIGATION', error: e, stackTrace: stackTrace);
      ToastService.error('Rerouting failed');

      // Update cooldown even on failure
      _lastRerouteTime = DateTime.now();
    } finally {
      _isRerouting = false;
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
