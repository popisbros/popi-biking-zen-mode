/// Routing provider options
enum RoutingProvider {
  /// GraphHopper routing service
  /// - Balanced routes with safety options
  /// - Provides fastest, safest, and shortest routes
  graphhopper,

  /// OpenRouteService routing service
  /// - Cycling-optimized with terrain awareness
  /// - Steepness controls and fitness level options
  /// - Based on OpenStreetMap data
  openrouteservice,
}

/// Extension methods for RoutingProvider
extension RoutingProviderExtension on RoutingProvider {
  /// Display name for the provider
  String get displayName {
    switch (this) {
      case RoutingProvider.graphhopper:
        return 'GraphHopper';
      case RoutingProvider.openrouteservice:
        return 'OpenRouteService';
    }
  }

  /// Description of the provider
  String get description {
    switch (this) {
      case RoutingProvider.graphhopper:
        return 'Balanced routes with safety options';
      case RoutingProvider.openrouteservice:
        return 'Cycling-optimized with terrain awareness';
    }
  }

  /// Icon emoji for the provider
  String get icon {
    switch (this) {
      case RoutingProvider.graphhopper:
        return '🚴‍♂️';
      case RoutingProvider.openrouteservice:
        return '⛰️';
    }
  }

  /// Convert to string for persistence
  String toStorageString() {
    return name;
  }

  /// Parse from string
  static RoutingProvider fromStorageString(String value) {
    return RoutingProvider.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RoutingProvider.graphhopper,
    );
  }
}
