import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_data.dart';
import '../services/routing_service.dart';
import '../services/toast_service.dart';
import '../providers/search_provider.dart';
import '../providers/map_provider.dart';
import '../providers/navigation_mode_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/location_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_visibility_provider.dart';
import '../widgets/dialogs/route_selection_dialog.dart';
import 'app_logger.dart';

/// Helper class for route calculation and display logic
///
/// Consolidates duplicate route calculation workflow from map screens
class RouteCalculationHelper {
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
    bool transparentBarrier = true,
  }) async {
    // Get user location if not provided
    final location = userLocation ?? _getUserLocation(ref);

    if (location == null) {
      AppLogger.warning('Cannot calculate route - user location not available', tag: 'ROUTING');
      ToastService.error('Unable to calculate route - location not available');
      return false;
    }

    AppLogger.map('Calculating multiple routes', data: {
      'from': '${location.latitude},${location.longitude}',
      'to': '$destLat,$destLon',
    });

    // Show loading indicator
    ToastService.loading('Calculating routes...');

    final routingService = RoutingService();
    final routes = await routingService.calculateMultipleRoutes(
      startLat: location.latitude,
      startLon: location.longitude,
      endLat: destLat,
      endLon: destLon,
    );

    if (routes == null || routes.isEmpty) {
      AppLogger.warning('Route calculation failed', tag: 'ROUTING');
      ToastService.dismiss();
      ToastService.error('Unable to calculate routes');
      return false;
    }

    // Dismiss loading toast on success
    ToastService.dismiss();

    AppLogger.debug('Routes received', tag: 'ROUTING', data: {
      'count': routes.length,
      'types': routes.map((r) => r.type.name).join(', '),
    });

    // Allow screen to prepare for routes (e.g., adjust pitch)
    onPreRoutesCalculated?.call();

    // Set preview routes in state (to display on map)
    if (routes.length >= 2) {
      final fastest = routes.firstWhere((r) => r.type == RouteType.fastest);
      final safest = routes.where((r) => r.type == RouteType.safest).firstOrNull;
      final shortest = routes.where((r) => r.type == RouteType.shortest).firstOrNull;

      ref.read(searchProvider.notifier).setPreviewRoutes(
        fastest.points,
        safest?.points ?? shortest!.points,
        routes.length == 3 ? shortest?.points : null,
      );

      // Auto-zoom to fit all routes on screen
      final allPoints = [
        ...fastest.points,
        if (safest != null) ...safest.points,
        if (shortest != null) ...shortest.points,
      ];
      fitBoundsCallback(allPoints);
    }

    // Show route selection dialog
    if (context.mounted) {
      RouteSelectionDialog.show(
        context: context,
        routes: routes,
        onRouteSelected: (route) {
          // Save destination to recent destinations (if user is logged in and name is provided)
          final authUser = ref.read(authStateProvider).value;
          if (authUser != null) {
            final name = destinationName ?? '$destLat, $destLon';
            ref.read(authNotifierProvider.notifier).addRecentDestination(name, destLat, destLon);

            // Save route profile preference
            final profileName = route.type == RouteType.fastest ? 'car'
                              : route.type == RouteType.safest ? 'bike'
                              : 'foot';
            ref.read(authNotifierProvider.notifier).updateDefaultRouteProfile(profileName);
          }

          ref.read(searchProvider.notifier).clearPreviewRoutes();
          onRouteSelected(route);
        },
        onCancel: () {
          ref.read(searchProvider.notifier).clearPreviewRoutes();
          onCancel?.call();
        },
        transparentBarrier: transparentBarrier,
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
