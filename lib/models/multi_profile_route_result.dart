import '../services/routing_service.dart';
import '../services/route_hazard_detector.dart';

/// Transport profile types for multi-profile routing
enum TransportProfile {
  car,
  bike,
  foot;

  /// Get display label for profile
  String get label {
    switch (this) {
      case TransportProfile.car:
        return 'Car';
      case TransportProfile.bike:
        return 'Bike';
      case TransportProfile.foot:
        return 'Foot';
    }
  }

  /// Get icon emoji for profile
  String get emoji {
    switch (this) {
      case TransportProfile.car:
        return '🚗';
      case TransportProfile.bike:
        return '🚴';
      case TransportProfile.foot:
        return '🚶';
    }
  }

  /// Get GraphHopper profile name
  String get graphhopperProfile {
    switch (this) {
      case TransportProfile.car:
        return 'car';
      case TransportProfile.bike:
        return 'bike';
      case TransportProfile.foot:
        return 'foot';
    }
  }
}

/// Result containing routes for all transport profiles (Car, Bike, Foot)
class MultiProfileRouteResult {
  final RouteResult? carRoute;
  final RouteResult? bikeRoute;
  final RouteResult? footRoute;

  MultiProfileRouteResult({
    this.carRoute,
    this.bikeRoute,
    this.footRoute,
  });

  /// Get route for specific profile
  RouteResult? getRoute(TransportProfile profile) {
    switch (profile) {
      case TransportProfile.car:
        return carRoute;
      case TransportProfile.bike:
        return bikeRoute;
      case TransportProfile.foot:
        return footRoute;
    }
  }

  /// Get all available routes as a list
  List<RouteResult> get availableRoutes {
    final routes = <RouteResult>[];
    if (carRoute != null) routes.add(carRoute!);
    if (bikeRoute != null) routes.add(bikeRoute!);
    if (footRoute != null) routes.add(footRoute!);
    return routes;
  }

  /// Check if any routes are available
  bool get hasAnyRoute => carRoute != null || bikeRoute != null || footRoute != null;

  /// Get count of available routes
  int get availableCount {
    int count = 0;
    if (carRoute != null) count++;
    if (bikeRoute != null) count++;
    if (footRoute != null) count++;
    return count;
  }

  /// Copy with updated routes
  MultiProfileRouteResult copyWith({
    RouteResult? carRoute,
    RouteResult? bikeRoute,
    RouteResult? footRoute,
  }) {
    return MultiProfileRouteResult(
      carRoute: carRoute ?? this.carRoute,
      bikeRoute: bikeRoute ?? this.bikeRoute,
      footRoute: footRoute ?? this.footRoute,
    );
  }

  /// Update hazards for all routes
  MultiProfileRouteResult copyWithHazards(List<RouteHazard> hazards) {
    return MultiProfileRouteResult(
      carRoute: carRoute?.copyWithHazards(hazards),
      bikeRoute: bikeRoute?.copyWithHazards(hazards),
      footRoute: footRoute?.copyWithHazards(hazards),
    );
  }
}
