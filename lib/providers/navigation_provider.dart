import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/location_data.dart';
import '../models/navigation_state.dart';
import '../models/maneuver_instruction.dart';
import '../models/community_warning.dart';
import '../models/route_warning.dart';
import '../services/routing_service.dart';
import '../services/navigation_engine.dart';
import '../services/location_service.dart';
import '../services/toast_service.dart';
import '../services/route_hazard_detector.dart';
import '../services/road_surface_analyzer.dart';
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
  static const double _arrivalDistanceThreshold = 20.0; // 20 meters to destination
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

    AppLogger.debug('Checking hazard warnings providers', data: {
      'boundsWarnings.hasValue': boundsWarnings.hasValue,
      'boundsWarnings.count': boundsWarnings.value?.length ?? 0,
      'allWarnings.hasValue': allWarnings.hasValue,
      'allWarnings.count': allWarnings.value?.length ?? 0,
    });

    // Prefer all warnings (complete set) if available, otherwise use bounds
    if (allWarnings.hasValue && allWarnings.value != null && allWarnings.value!.isNotEmpty) {
      warnings = allWarnings.value!;
      AppLogger.debug('Using ALL warnings', data: {'count': warnings.length});
    } else if (boundsWarnings.hasValue && boundsWarnings.value != null && boundsWarnings.value!.isNotEmpty) {
      warnings = boundsWarnings.value!;
      AppLogger.debug('Using BOUNDS warnings', data: {'count': warnings.length});
    } else {
      AppLogger.warning('No warnings available from either provider');
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

      AppLogger.debug('Hazards detected', data: {'count': routeHazards.length});

      if (routeHazards.isNotEmpty) {
        AppLogger.success('Found ${routeHazards.length} hazards on route', tag: 'NAVIGATION');
        for (var i = 0; i < routeHazards.length; i++) {
          AppLogger.debug('Hazard $i detected', data: {
            'index': i,
            'title': routeHazards[i].warning.title,
            'distanceAlongRoute': '${routeHazards[i].distanceAlongRoute.toStringAsFixed(0)}m',
          });
        }
      } else {
        AppLogger.debug('No hazards found on route', tag: 'NAVIGATION');
      }
    } else {
      AppLogger.warning('No community warnings available for hazard detection', tag: 'NAVIGATION');
    }

    AppLogger.debug('Creating route with hazards', data: {'hazardCount': routeHazards.length});

    // Update route with detected hazards
    final routeWithHazards = route.copyWithHazards(routeHazards);

    // Detect all maneuvers in the route
    _detectedManeuvers = NavigationEngine.detectManeuvers(route.points);
    AppLogger.debug('Maneuvers detected', tag: 'NAVIGATION', data: {
      'count': _detectedManeuvers.length,
    });

    // Merge community warnings and road surface warnings
    final List<RouteWarning> mergedWarnings = [];

    // 1. Add community warnings (from RouteHazard)
    for (final hazard in routeHazards) {
      mergedWarnings.add(RouteWarning(
        type: RouteWarningType.community,
        distanceAlongRoute: hazard.distanceAlongRoute,
        distanceFromUser: hazard.distanceAlongRoute, // Will be updated on location updates
        communityWarning: hazard.warning,
      ));
    }

    // 2. Add road surface warnings
    final surfaceWarnings = RoadSurfaceAnalyzer.analyzeRouteSurface(
      route: route,
      currentPosition: null, // No position yet at start
    );
    mergedWarnings.addAll(surfaceWarnings);

    // 3. Sort by distance along route
    mergedWarnings.sort((a, b) => a.distanceAlongRoute.compareTo(b.distanceAlongRoute));

    AppLogger.success('Warnings merged', tag: 'NAVIGATION', data: {
      'community': routeHazards.length,
      'surface': surfaceWarnings.length,
      'total': mergedWarnings.length,
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
      routeWarnings: mergedWarnings,
      warningsExpanded: true,
      warningsExpandedAt: DateTime.now(),
    );

    // Enable wakelock to keep screen on during navigation
    WakelockPlus.enable().then((_) {
      AppLogger.success('Screen wakelock enabled - screen will stay on', tag: 'NAVIGATION');
    }).catchError((error) {
      AppLogger.warning('Failed to enable wakelock', tag: 'NAVIGATION', data: {'error': error.toString()});
    });

    // Notify ToastService that navigation is active (adjust toast positioning)
    ToastService.setNavigationActive(true);

    // Start listening to location updates (fire and forget, don't block navigation start)
    _startLocationTracking().then((_) {
      AppLogger.success('Location tracking initialized', tag: 'GPS');
    }).catchError((error) {
      AppLogger.error('Failed to start location tracking', tag: 'GPS', error: error);
    });

    AppLogger.success('Navigation started', tag: 'NAVIGATION');
    AppLogger.separator();
  }

  /// Stop navigation
  void stopNavigation() {
    AppLogger.debug('Stopping navigation', tag: 'NAVIGATION');

    // Disable wakelock to allow screen to sleep
    WakelockPlus.disable().then((_) {
      AppLogger.success('Screen wakelock disabled - screen can sleep', tag: 'NAVIGATION');
    }).catchError((error) {
      AppLogger.warning('Failed to disable wakelock', tag: 'NAVIGATION', data: {'error': error.toString()});
    });

    // Notify ToastService that navigation is no longer active
    ToastService.setNavigationActive(false);

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

  /// Toggle warnings section expanded/collapsed
  void toggleWarningsExpanded() {
    final newExpanded = !state.warningsExpanded;
    AppLogger.debug('Toggling warnings', tag: 'NAVIGATION', data: {
      'expanded': newExpanded,
    });

    state = state.copyWith(
      warningsExpanded: newExpanded,
      warningsExpandedAt: newExpanded ? DateTime.now() : null,
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
    AppLogger.debug('Calling startLocationTracking()', tag: 'GPS');
    await locationService.startLocationTracking();
    AppLogger.debug('startLocationTracking() completed', tag: 'GPS');

    _locationSubscription = locationService.locationStream.listen(
      (locationData) {
        _onLocationUpdate(locationData);
      },
      onError: (error) {
        AppLogger.error('Location stream error during navigation', tag: 'GPS', error: error);
      },
      onDone: () {
        AppLogger.debug('Location stream completed', tag: 'GPS');
      },
    );

    AppLogger.success('Subscribed to location stream - tracking active', tag: 'GPS');
  }

  /// Handle location update from GPS
  void _onLocationUpdate(LocationData locationData) {
    AppLogger.debug('Location update received', tag: 'GPS', data: {
      'latitude': locationData.latitude,
      'longitude': locationData.longitude,
    });

    if (!state.isNavigating || state.activeRoute == null) {
      AppLogger.debug('Skipping location update - not navigating or no route', tag: 'GPS');
      return;
    }

    // Throttle updates to max once per 3 seconds
    final now = DateTime.now();
    if (_lastUpdateTime != null && now.difference(_lastUpdateTime!).inSeconds < 3) {
      AppLogger.debug('Location update throttled', tag: 'GPS', data: {
        'secondsSinceLastUpdate': now.difference(_lastUpdateTime!).inSeconds,
        'throttleLimit': '3s',
      });
      return; // Skip this update
    }
    _lastUpdateTime = now;

    final currentPos = LatLng(locationData.latitude, locationData.longitude);
    final route = state.activeRoute!;

    // Find closest segment on route
    final closestSegment = NavigationEngine.findClosestSegment(currentPos, route.points);

    // Calculate speed early (needed for off-route threshold)
    final speed = locationData.speed ?? 0.0;
    final speedKmh = speed * 3.6; // Convert m/s to km/h

    // Check if off route and get distance (uses speed-based threshold)
    final isOffRoute = NavigationEngine.isOffRoute(currentPos, route.points, speedKmh: speedKmh);
    final offRouteDistance = NavigationEngine.getDistanceToRoute(currentPos, route.points);

    // Calculate remaining distance
    final remainingDistance = NavigationEngine.calculateRemainingDistance(
      currentPos,
      route.points,
      closestSegment,
    );

    // Calculate current distance along route (for warnings)
    final Distance distance = const Distance();
    double currentDistanceAlongRoute = 0.0;
    for (int i = 0; i < closestSegment && i < route.points.length - 1; i++) {
      currentDistanceAlongRoute += distance.as(
        LengthUnit.Meter,
        route.points[i],
        route.points[i + 1],
      );
    }

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

    // Estimate time remaining (speed already calculated above)
    final timeRemaining = NavigationEngine.estimateTimeRemaining(
      remainingDistance,
      speed,
    );

    // Enhanced arrival detection
    final distanceToDestination = remainingDistance;
    // speedKmh already calculated above
    final gpsAccuracy = locationData.accuracy ?? 999;

    // Check arrival conditions (simplified: distance + GPS accuracy only)
    final bool withinArrivalZone = distanceToDestination < _arrivalDistanceThreshold;
    final bool goodGpsAccuracy = gpsAccuracy < _arrivalGpsAccuracyThreshold;

    // Determine arrival state
    bool hasArrived = false;

    if (withinArrivalZone && goodGpsAccuracy) {
      // Immediate arrival: within 20m with good GPS accuracy
      hasArrived = true;
      AppLogger.success('ARRIVED at destination!', tag: 'NAVIGATION', data: {
        'distance': '${distanceToDestination.toStringAsFixed(1)}m',
        'gpsAccuracy': '${gpsAccuracy.toStringAsFixed(1)}m',
      });
    }

    // Calculate speed averages and tracking
    final timeSinceLastUpdate = state.lastUpdateTime != null
        ? now.difference(state.lastUpdateTime!).inSeconds
        : 3;

    // Calculate distance traveled since last update
    double distanceTraveled = 0.0;
    if (state.currentPosition != null) {
      final Distance distance = const Distance();
      distanceTraveled = distance.as(
        LengthUnit.Meter,
        state.currentPosition!,
        currentPos,
      );
    }

    // Update totals
    final newTotalDistanceTraveled = state.totalDistanceTraveled + distanceTraveled;
    final newTotalTimeElapsed = state.totalTimeElapsed + timeSinceLastUpdate;

    // Track time moving (speed >= 0.5 m/s)
    final isMoving = speed >= 0.5;
    final newTotalTimeMoving = state.totalTimeMoving + (isMoving ? timeSinceLastUpdate : 0);

    // Calculate averages
    final newAvgSpeedWithStops = newTotalTimeElapsed > 0
        ? newTotalDistanceTraveled / newTotalTimeElapsed
        : 0.0;

    final newAvgSpeedWithoutStops = newTotalTimeMoving > 0
        ? newTotalDistanceTraveled / newTotalTimeMoving
        : 0.0;

    AppLogger.debug('Speed tracking', tag: 'NAVIGATION', data: {
      'distanceTraveled': '${distanceTraveled.toStringAsFixed(1)}m',
      'totalDistance': '${newTotalDistanceTraveled.toStringAsFixed(0)}m',
      'totalTime': '${newTotalTimeElapsed}s',
      'timeMoving': '${newTotalTimeMoving}s',
      'avgWithStops': '${(newAvgSpeedWithStops * 3.6).toStringAsFixed(1)} km/h',
      'avgWithoutStops': '${(newAvgSpeedWithoutStops * 3.6).toStringAsFixed(1)} km/h',
    });

    // Auto-collapse warnings after 10 seconds
    bool warningsExpanded = state.warningsExpanded;
    DateTime? warningsExpandedAt = state.warningsExpandedAt;

    if (warningsExpanded && warningsExpandedAt != null) {
      final secondsSinceExpanded = now.difference(warningsExpandedAt).inSeconds;
      if (secondsSinceExpanded >= 10) {
        warningsExpanded = false;
        warningsExpandedAt = null;
        AppLogger.debug('Auto-collapsing warnings after 10s', tag: 'NAVIGATION');
      }
    }

    // Update warnings with current distance from user
    final List<RouteWarning> updatedWarnings = [];
    for (final warning in state.routeWarnings) {
      // Only include warnings ahead of user
      final distanceFromUser = warning.distanceAlongRoute - currentDistanceAlongRoute;
      if (distanceFromUser > 0) {
        // Create updated warning with new distanceFromUser
        if (warning.type == RouteWarningType.community) {
          updatedWarnings.add(RouteWarning(
            type: warning.type,
            distanceAlongRoute: warning.distanceAlongRoute,
            distanceFromUser: distanceFromUser,
            communityWarning: warning.communityWarning,
          ));
        } else {
          updatedWarnings.add(RouteWarning(
            type: warning.type,
            distanceAlongRoute: warning.distanceAlongRoute,
            distanceFromUser: distanceFromUser,
            surfaceQuality: warning.surfaceQuality,
            surfaceLength: warning.surfaceLength,
            surfaceType: warning.surfaceType,
          ));
        }
      }
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
      hasArrived: hasArrived,
      averageSpeedWithStops: newAvgSpeedWithStops,
      averageSpeedWithoutStops: newAvgSpeedWithoutStops,
      totalDistanceTraveled: newTotalDistanceTraveled,
      totalTimeElapsed: newTotalTimeElapsed,
      totalTimeMoving: newTotalTimeMoving,
      routeWarnings: updatedWarnings,
      warningsExpanded: warningsExpanded,
      warningsExpandedAt: warningsExpandedAt,
    );

    // Log navigation update (every update for debugging)
    AppLogger.debug('Navigation update', tag: 'NAVIGATION', data: {
      'segment': closestSegment,
      'nextManeuver': nextManeuver?.type.name ?? 'none',
      'distanceToNext': '${distanceToManeuver.toStringAsFixed(0)}m',
      'remaining': '${(remainingDistance / 1000).toStringAsFixed(2)}km',
      'speed': '${speedKmh.toStringAsFixed(1)}km/h',
      'offRoute': isOffRoute,
      'arrived': hasArrived,
    });

    // Handle arrival
    if (hasArrived && !state.hasArrived) {
      // First time arrival detected
      _onArrival();
    }

    // Automatic rerouting if off route
    if (isOffRoute && !_isRerouting) {
      AppLogger.warning('Off route detected', tag: 'REROUTE', data: {
        'distance': '${offRouteDistance.toStringAsFixed(1)}m',
      });

      // Show toast notification when going off-route
      if (!state.isOffRoute) {
        // First time going off route
        ToastService.warning('Off route: ${offRouteDistance.toStringAsFixed(0)}m from path');
      }

      AppLogger.debug('Initiating automatic rerouting', tag: 'REROUTE');
      _handleAutomaticRerouting(currentPos);
    } else if (isOffRoute && _isRerouting) {
      AppLogger.debug('Off route but rerouting already in progress', tag: 'REROUTE');
      ToastService.info('Rerouting in progress...');
    }
  }

  /// Handle arrival at destination
  void _onArrival() {
    // Keep navigation active but mark as arrived
    // User can manually stop navigation
    AppLogger.success('Arrived at destination', tag: 'NAVIGATION');

    // Show toast notification
    ToastService.success('You have arrived at your destination!');

    // TODO: Add voice announcement if voice guidance is enabled
    // This would require integration with a TTS (Text-to-Speech) service
  }

  /// Handle automatic rerouting when off route
  Future<void> _handleAutomaticRerouting(LatLng currentPos) async {
    AppLogger.debug('_handleAutomaticRerouting called', tag: 'REROUTE');

    // Check if we're still navigating
    if (!state.isNavigating || state.activeRoute == null) {
      AppLogger.debug('Rerouting aborted - not navigating or no active route', tag: 'REROUTE');
      return;
    }

    // Check cooldown period
    if (_lastRerouteTime != null) {
      final timeSinceLastReroute = DateTime.now().difference(_lastRerouteTime!).inSeconds;
      AppLogger.debug('Checking reroute cooldown', tag: 'REROUTE', data: {
        'timeSinceLastReroute': '${timeSinceLastReroute}s',
        'cooldown': '${_rerouteCooldownSeconds}s',
      });
      if (timeSinceLastReroute < _rerouteCooldownSeconds) {
        final remainingSeconds = _rerouteCooldownSeconds - timeSinceLastReroute;
        ToastService.info('Rerouting on cooldown, wait ${remainingSeconds}s');
        AppLogger.debug('Rerouting cooldown active', tag: 'NAVIGATION', data: {
          'timeSince': '${timeSinceLastReroute}s',
          'cooldown': '${_rerouteCooldownSeconds}s',
        });
        AppLogger.debug('Rerouting aborted - cooldown active', tag: 'REROUTE');
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

      AppLogger.debug('Checking reroute position threshold', tag: 'REROUTE', data: {
        'distanceFromLastReroute': '${distance.toStringAsFixed(1)}m',
        'threshold': '${_reroutePositionThreshold}m',
      });

      if (distance < _reroutePositionThreshold) {
        // Same position as last successful reroute - abort
        final metersNeeded = (_reroutePositionThreshold - distance).toInt();
        ToastService.warning('Rerouting blocked: Move ${metersNeeded}m+ more');
        AppLogger.warning('Rerouting aborted - same position', tag: 'NAVIGATION', data: {
          'distance': '${distance.toStringAsFixed(1)}m',
          'threshold': '${_reroutePositionThreshold}m',
        });

        AppLogger.debug('Rerouting aborted - same position, updating cooldown', tag: 'REROUTE');

        // Update cooldown to prevent spam
        _lastRerouteTime = DateTime.now();
        return;
      }
    }

    // Start rerouting
    AppLogger.debug('Starting reroute process', tag: 'REROUTE');
    _isRerouting = true;
    final routeType = state.activeRoute!.type;
    final destination = state.activeRoute!.points.last;

    // Show toast notification
    final routeTypeName = routeType == RouteType.fastest
        ? 'Fastest'
        : routeType == RouteType.safest
            ? 'Safest'
            : 'Shortest';
    AppLogger.debug('Showing reroute toast', tag: 'REROUTE', data: {
      'routeType': routeTypeName,
    });
    ToastService.info('Calculating new $routeTypeName route...');

    AppLogger.separator('Automatic Rerouting');
    AppLogger.debug('Starting automatic reroute', tag: 'NAVIGATION', data: {
      'routeType': routeType.name,
      'from': '${currentPos.latitude},${currentPos.longitude}',
      'to': '${destination.latitude},${destination.longitude}',
    });
    AppLogger.debug('Calling routing service', tag: 'REROUTE');

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
      // Add delay between stop and start to ensure proper route clearing
      stopNavigation();

      // Wait for map to clear old route before showing new one
      await Future.delayed(const Duration(milliseconds: 150));

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
