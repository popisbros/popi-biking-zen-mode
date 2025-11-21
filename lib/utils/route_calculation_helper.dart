import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_data.dart';
import '../models/multi_profile_route_result.dart';
import '../services/routing_service.dart';
import '../services/route_hazard_detector.dart';
import '../services/toast_service.dart';
import '../providers/search_provider.dart';
import '../providers/map_provider.dart';
import '../providers/navigation_mode_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/location_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_visibility_provider.dart';
import '../providers/community_provider.dart';
import '../widgets/dialogs/route_selection_dialog.dart';
import 'app_logger.dart';

/// Helper class for route calculation and display logic
///
/// Consolidates duplicate route calculation workflow from map screens
class RouteCalculationHelper {
  // Static variable to store POI state for restoration after navigation ends
  static POIVisibilityState? _savedPOIStateForNavigation;
  /// Calculate multiple routes and show selection dialog
  ///
  /// Returns true if calculation succeeded, false otherwise
  static Future<bool> calculateAndShowRoutes({
    required BuildContext context,
    required WidgetRef ref,
    required double destLat,
    required double destLon,
    String? destinationName,
    LocationData? userLocation,
    VoidCallback? onPreRoutesCalculated,
    required Function(List<LatLng>) fitBoundsCallback,
    required Function(RouteResult) onRouteSelected,
    VoidCallback? onCancel,
  }) async {
    // Get user location if not provided
    final location = userLocation ?? _getUserLocation(ref);

    if (location == null) {
      AppLogger.warning('Cannot calculate route - user location not available', tag: 'ROUTING');
      ToastService.error('Unable to calculate route - location not available');
      return false;
    }

    AppLogger.map('Calculating multi-profile routes (Car, Bike, Foot)', data: {
      'from': '${location.latitude},${location.longitude}',
      'to': '$destLat,$destLon',
    });

    // Show loading indicator
    ToastService.loading('Calculating routes...');

    final routingService = RoutingService();
    final multiProfileRoutes = await routingService.calculateMultiProfileRoutes(
      startLat: location.latitude,
      startLon: location.longitude,
      endLat: destLat,
      endLon: destLon,
    );

    if (!multiProfileRoutes.hasAnyRoute) {
      AppLogger.warning('Route calculation failed - no routes available', tag: 'ROUTING');
      ToastService.dismiss();
      ToastService.error('Unable to calculate routes');
      return false;
    }

    AppLogger.success('Calculated ${multiProfileRoutes.availableCount}/3 profile routes', tag: 'ROUTING', data: {
      'car': multiProfileRoutes.carRoute != null ? '✓' : '✗',
      'bike': multiProfileRoutes.bikeRoute != null ? '✓' : '✗',
      'foot': multiProfileRoutes.footRoute != null ? '✓' : '✗',
    });

    // Detect hazards on all routes
    final warningsAsync = ref.read(communityWarningsBoundsNotifierProvider);
    final allWarnings = warningsAsync.value ?? [];

    AppLogger.debug('Detecting hazards on routes', tag: 'ROUTING', data: {
      'totalWarnings': allWarnings.length,
    });

    // Detect hazards on each route individually
    RouteResult? carRouteWithHazards;
    RouteResult? bikeRouteWithHazards;
    RouteResult? footRouteWithHazards;

    if (multiProfileRoutes.carRoute != null) {
      final hazards = RouteHazardDetector.detectHazardsOnRoute(
        routePoints: multiProfileRoutes.carRoute!.points,
        allHazards: allWarnings,
      );
      carRouteWithHazards = multiProfileRoutes.carRoute!.copyWithHazards(hazards);
      AppLogger.debug('Car route: ${hazards.length} hazards', tag: 'ROUTING');
    }

    if (multiProfileRoutes.bikeRoute != null) {
      final hazards = RouteHazardDetector.detectHazardsOnRoute(
        routePoints: multiProfileRoutes.bikeRoute!.points,
        allHazards: allWarnings,
      );
      bikeRouteWithHazards = multiProfileRoutes.bikeRoute!.copyWithHazards(hazards);
      AppLogger.debug('Bike route: ${hazards.length} hazards', tag: 'ROUTING');
    }

    if (multiProfileRoutes.footRoute != null) {
      final hazards = RouteHazardDetector.detectHazardsOnRoute(
        routePoints: multiProfileRoutes.footRoute!.points,
        allHazards: allWarnings,
      );
      footRouteWithHazards = multiProfileRoutes.footRoute!.copyWithHazards(hazards);
      AppLogger.debug('Foot route: ${hazards.length} hazards', tag: 'ROUTING');
    }

    final routesWithHazards = MultiProfileRouteResult(
      carRoute: carRouteWithHazards,
      bikeRoute: bikeRouteWithHazards,
      footRoute: footRouteWithHazards,
    );

    // Dismiss loading toast on success
    ToastService.dismiss();

    // Allow screen to prepare for routes (e.g., adjust pitch)
    onPreRoutesCalculated?.call();

    // Set preview routes in state (to display on map)
    final availableRoutes = routesWithHazards.availableRoutes;
    if (availableRoutes.length >= 2) {
      ref.read(searchProvider.notifier).setPreviewRoutes(
        availableRoutes[0].points,
        availableRoutes[1].points,
        availableRoutes.length == 3 ? availableRoutes[2].points : null,
      );

      // Auto-zoom to fit all routes on screen
      final allPoints = availableRoutes.expand((r) => r.points).toList();
      fitBoundsCallback(allPoints);
    }

    // Save current POI visibility state before showing dialog (for cancel restoration)
    final currentFavoritesVisible = ref.read(favoritesVisibilityProvider);
    final savedPOIState = ref.read(mapProvider.notifier).savePOIState(currentFavoritesVisible);

    // Also save to static variable for restoration after navigation ends
    _savedPOIStateForNavigation = savedPOIState;

    // Turn off POIs/Favorites to make map lighter during route selection
    ref.read(mapProvider.notifier).setPOIVisibility(
      showOSM: false,
      showCommunity: false,
      showHazards: true, // Keep hazards visible
    );

    // Turn off Favorites toggle
    ref.read(favoritesVisibilityProvider.notifier).setVisible(false);

    // Show route selection dialog with multi-profile routes
    if (context.mounted) {
      RouteSelectionDialog.showMultiProfile(
        context: context,
        multiProfileRoutes: routesWithHazards,
        onRouteSelected: (route) {
          // Save destination to recent destinations (if user is logged in and name is provided)
          final authUser = ref.read(authStateProvider).value;
          if (authUser != null) {
            final name = destinationName ?? '$destLat, $destLon';
            ref.read(authNotifierProvider.notifier).addRecentDestination(name, destLat, destLon);
          }

          // Note: Profile preference is now saved in the dialog's onRouteSelected handler
          // when user taps "START NAVIGATION" button

          ref.read(searchProvider.notifier).clearPreviewRoutes();
          // POI state will be managed by displaySelectedRoute (keeps them off during navigation)
          onRouteSelected(route);
        },
        onCancel: () {
          // Restore previous POI visibility state when canceling
          ref.read(mapProvider.notifier).restorePOIState(savedPOIState);
          ref.read(favoritesVisibilityProvider.notifier).setVisible(savedPOIState.showFavorites);
          ref.read(searchProvider.notifier).clearPreviewRoutes();
          onCancel?.call();
        },
      );
    }

    return true;
  }

  /// Display selected route and activate navigation
  static void displaySelectedRoute({
    required WidgetRef ref,
    required RouteResult route,
    VoidCallback? onCenterMap,
  }) {
    // Store route in provider
    ref.read(searchProvider.notifier).setRoute(route.points);

    // Toggle POIs: OSM OFF, Community OFF, Hazards ON
    ref.read(mapProvider.notifier).setPOIVisibility(
      showOSM: false,
      showCommunity: false,
      showHazards: true,
    );

    // Disable favorites/destinations visibility during navigation
    ref.read(favoritesVisibilityProvider.notifier).disable();

    // Activate navigation mode automatically
    ref.read(navigationModeProvider.notifier).startRouteNavigation();

    // Start turn-by-turn navigation
    ref.read(navigationProvider.notifier).startNavigation(route);

    // Allow screen to handle map centering (different implementations for 2D/3D)
    onCenterMap?.call();

    final routeTypeLabel = route.type == RouteType.fastest ? 'Fastest' : 'Safest';
    AppLogger.success('$routeTypeLabel route displayed', tag: 'ROUTING', data: {
      'points': route.points.length,
      'distance': route.distanceKm,
      'duration': route.durationMin,
    });
  }

  /// Restore POI visibility state after navigation ends
  ///
  /// Call this when navigation is stopped to restore POI toggles to their
  /// pre-route-selection state
  static void restorePOIStateAfterNavigation(WidgetRef ref) {
    if (_savedPOIStateForNavigation != null) {
      ref.read(mapProvider.notifier).restorePOIState(_savedPOIStateForNavigation!);
      ref.read(favoritesVisibilityProvider.notifier).setVisible(_savedPOIStateForNavigation!.showFavorites);
      AppLogger.info('Restored POI visibility state after navigation (favorites: ${_savedPOIStateForNavigation!.showFavorites})', tag: 'POI');
      _savedPOIStateForNavigation = null; // Clear after restoring
    }
  }

  /// Helper to get user location from provider
  static LocationData? _getUserLocation(WidgetRef ref) {
    final locationAsync = ref.read(locationNotifierProvider);
    LocationData? location;
    locationAsync.whenData((data) {
      location = data;
    });
    return location;
  }
}
