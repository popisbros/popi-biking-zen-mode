import 'package:latlong2/latlong.dart';
import '../services/routing_service.dart';
import 'maneuver_instruction.dart';

/// State for turn-by-turn navigation
class NavigationState {
  /// Whether navigation is currently active
  final bool isNavigating;

  /// The active route being navigated
  final RouteResult? activeRoute;

  /// Current GPS position
  final LatLng? currentPosition;

  /// Current speed in meters per second
  final double? currentSpeed;

  /// Current heading in degrees (0-360, where 0 is North)
  final double? currentHeading;

  /// Index of current route segment user is on
  final int currentSegmentIndex;

  /// All detected maneuvers on this route
  final List<ManeuverInstruction> allManeuvers;

  /// Next maneuver instruction
  final ManeuverInstruction? nextManeuver;

  /// Distance to next maneuver in meters
  final double distanceToNextManeuver;

  /// Total distance remaining on route in meters
  final double totalDistanceRemaining;

  /// Estimated time remaining in seconds
  final int estimatedTimeRemaining;

  /// Whether user has gone off the planned route
  final bool isOffRoute;

  /// Distance from route in meters (when off-route)
  final double offRouteDistanceMeters;

  /// Whether off-route dialog is currently shown
  final bool showingOffRouteDialog;

  /// Timestamp of last location update
  final DateTime? lastUpdateTime;

  /// Whether user is approaching destination (pre-arrival state)
  final bool isApproachingDestination;

  /// Whether user has arrived at destination
  final bool hasArrived;

  /// Timestamp when user first entered arrival zone
  final DateTime? arrivalZoneEntryTime;

  /// Average speed including stops (m/s) - for pessimistic ETA
  final double averageSpeedWithStops;

  /// Average speed excluding stops (m/s) - for optimistic ETA
  final double averageSpeedWithoutStops;

  /// Total distance traveled during navigation (meters)
  final double totalDistanceTraveled;

  /// Total time elapsed during navigation (seconds)
  final int totalTimeElapsed;

  /// Total time spent moving (speed >= 0.5 m/s) in seconds
  final int totalTimeMoving;

  const NavigationState({
    this.isNavigating = false,
    this.activeRoute,
    this.currentPosition,
    this.currentSpeed,
    this.currentHeading,
    this.currentSegmentIndex = 0,
    this.allManeuvers = const [],
    this.nextManeuver,
    this.distanceToNextManeuver = 0,
    this.totalDistanceRemaining = 0,
    this.estimatedTimeRemaining = 0,
    this.isOffRoute = false,
    this.offRouteDistanceMeters = 0,
    this.showingOffRouteDialog = false,
    this.lastUpdateTime,
    this.isApproachingDestination = false,
    this.hasArrived = false,
    this.arrivalZoneEntryTime,
    this.averageSpeedWithStops = 0.0,
    this.averageSpeedWithoutStops = 0.0,
    this.totalDistanceTraveled = 0.0,
    this.totalTimeElapsed = 0,
    this.totalTimeMoving = 0,
  });

  /// Get human-readable remaining distance
  String get remainingDistanceText {
    if (totalDistanceRemaining < 1000) {
      return '${totalDistanceRemaining.toStringAsFixed(0)} m';
    } else {
      return '${(totalDistanceRemaining / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Get human-readable remaining time
  String get remainingTimeText {
    final minutes = (estimatedTimeRemaining / 60).round();
    if (minutes <= 1) {
      return 'less than 1 min';
    } else if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = (minutes / 60).floor();
      final mins = minutes % 60;
      return '${hours}h ${mins}min';
    }
  }

  /// Get current speed in km/h
  double get speedKmh {
    if (currentSpeed == null) return 0;
    return currentSpeed! * 3.6;
  }

  /// Get formatted speed string with averages
  /// Format: "Live km/h - (Avg: AvgWithStops-AvgWithoutStops km/h)"
  String get speedText {
    final live = speedKmh.toStringAsFixed(1);
    final avgWithStops = (averageSpeedWithStops * 3.6).toStringAsFixed(1);
    final avgWithoutStops = (averageSpeedWithoutStops * 3.6).toStringAsFixed(1);

    // Show averages only if we have meaningful data (at least 30 seconds of navigation)
    if (totalTimeElapsed < 30) {
      return '$live km/h';
    }

    return '$live km/h - (Avg: $avgWithStops-$avgWithoutStops km/h)';
  }

  /// Get average speed including stops in km/h
  double get averageSpeedWithStopsKmh {
    return averageSpeedWithStops * 3.6;
  }

  /// Get average speed excluding stops in km/h
  double get averageSpeedWithoutStopsKmh {
    return averageSpeedWithoutStops * 3.6;
  }

  /// Get estimated time of arrival
  DateTime? get estimatedArrival {
    if (!isNavigating || lastUpdateTime == null) return null;
    return lastUpdateTime!.add(Duration(seconds: estimatedTimeRemaining));
  }

  /// Get formatted ETA string
  String get etaText {
    final eta = estimatedArrival;
    if (eta == null) return '--:--';
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  /// Calculate ETA range using both speed averages
  /// Returns [pessimistic_seconds, optimistic_seconds]
  List<int> get etaRangeSeconds {
    if (totalDistanceRemaining == 0) return [0, 0];

    // Pessimistic: using average with stops (slower)
    int pessimisticSeconds = estimatedTimeRemaining;
    if (averageSpeedWithStops > 0.5) {
      pessimisticSeconds = (totalDistanceRemaining / averageSpeedWithStops).round();
    }

    // Optimistic: using average without stops (faster)
    int optimisticSeconds = estimatedTimeRemaining;
    if (averageSpeedWithoutStops > 0.5) {
      optimisticSeconds = (totalDistanceRemaining / averageSpeedWithoutStops).round();
    }

    return [pessimisticSeconds, optimisticSeconds];
  }

  /// Get formatted ETA range as text
  /// Format: "10:30 - 10:45" (pessimistic to optimistic)
  String get etaRangeText {
    if (!isNavigating || lastUpdateTime == null || totalTimeElapsed < 30) {
      return etaText; // Fall back to single ETA if not enough data
    }

    final range = etaRangeSeconds;
    final pessimisticEta = lastUpdateTime!.add(Duration(seconds: range[0]));
    final optimisticEta = lastUpdateTime!.add(Duration(seconds: range[1]));

    final pessimisticStr = '${pessimisticEta.hour.toString().padLeft(2, '0')}:${pessimisticEta.minute.toString().padLeft(2, '0')}';
    final optimisticStr = '${optimisticEta.hour.toString().padLeft(2, '0')}:${optimisticEta.minute.toString().padLeft(2, '0')}';

    // If same minute, just show one time
    if (pessimisticStr == optimisticStr) {
      return pessimisticStr;
    }

    return '$pessimisticStr - $optimisticStr';
  }

  /// Get formatted remaining time range
  /// Format: "25-30 min" (optimistic to pessimistic)
  String get remainingTimeRangeText {
    if (totalTimeElapsed < 30) {
      return remainingTimeText; // Fall back to single time if not enough data
    }

    final range = etaRangeSeconds;
    final optimisticMin = (range[1] / 60).round();
    final pessimisticMin = (range[0] / 60).round();

    // If difference is small, show single value
    if ((pessimisticMin - optimisticMin).abs() <= 1) {
      return remainingTimeText;
    }

    if (optimisticMin < 60 && pessimisticMin < 60) {
      return '$optimisticMin-$pessimisticMin min';
    } else {
      final optHours = (optimisticMin / 60).floor();
      final optMins = optimisticMin % 60;
      final pessHours = (pessimisticMin / 60).floor();
      final pessMins = pessimisticMin % 60;
      return '${optHours}h${optMins}min - ${pessHours}h${pessMins}min';
    }
  }

  /// Get navigation progress (0.0 to 1.0)
  double get progress {
    if (activeRoute == null) return 0.0;
    final totalDistance = activeRoute!.distanceMeters;
    if (totalDistance == 0) return 1.0;
    return 1.0 - (totalDistanceRemaining / totalDistance);
  }

  NavigationState copyWith({
    bool? isNavigating,
    RouteResult? activeRoute,
    LatLng? currentPosition,
    double? currentSpeed,
    double? currentHeading,
    int? currentSegmentIndex,
    List<ManeuverInstruction>? allManeuvers,
    ManeuverInstruction? nextManeuver,
    double? distanceToNextManeuver,
    double? totalDistanceRemaining,
    int? estimatedTimeRemaining,
    bool? isOffRoute,
    double? offRouteDistanceMeters,
    bool? showingOffRouteDialog,
    DateTime? lastUpdateTime,
    bool? isApproachingDestination,
    bool? hasArrived,
    DateTime? arrivalZoneEntryTime,
    double? averageSpeedWithStops,
    double? averageSpeedWithoutStops,
    double? totalDistanceTraveled,
    int? totalTimeElapsed,
    int? totalTimeMoving,
  }) {
    return NavigationState(
      isNavigating: isNavigating ?? this.isNavigating,
      activeRoute: activeRoute ?? this.activeRoute,
      currentPosition: currentPosition ?? this.currentPosition,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      currentHeading: currentHeading ?? this.currentHeading,
      currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
      allManeuvers: allManeuvers ?? this.allManeuvers,
      nextManeuver: nextManeuver ?? this.nextManeuver,
      distanceToNextManeuver: distanceToNextManeuver ?? this.distanceToNextManeuver,
      totalDistanceRemaining: totalDistanceRemaining ?? this.totalDistanceRemaining,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      isOffRoute: isOffRoute ?? this.isOffRoute,
      offRouteDistanceMeters: offRouteDistanceMeters ?? this.offRouteDistanceMeters,
      showingOffRouteDialog: showingOffRouteDialog ?? this.showingOffRouteDialog,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      isApproachingDestination: isApproachingDestination ?? this.isApproachingDestination,
      hasArrived: hasArrived ?? this.hasArrived,
      arrivalZoneEntryTime: arrivalZoneEntryTime ?? this.arrivalZoneEntryTime,
      averageSpeedWithStops: averageSpeedWithStops ?? this.averageSpeedWithStops,
      averageSpeedWithoutStops: averageSpeedWithoutStops ?? this.averageSpeedWithoutStops,
      totalDistanceTraveled: totalDistanceTraveled ?? this.totalDistanceTraveled,
      totalTimeElapsed: totalTimeElapsed ?? this.totalTimeElapsed,
      totalTimeMoving: totalTimeMoving ?? this.totalTimeMoving,
    );
  }

  /// Create initial empty state
  factory NavigationState.initial() {
    return const NavigationState();
  }

  @override
  String toString() {
    return 'NavigationState(isNavigating: $isNavigating, segment: $currentSegmentIndex, '
        'distanceToNext: ${distanceToNextManeuver.toStringAsFixed(0)}m, '
        'remaining: $remainingDistanceText, isOffRoute: $isOffRoute)';
  }
}
