import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../providers/compass_provider.dart';
import '../providers/search_provider.dart';
import '../providers/navigation_mode_provider.dart';
import '../services/map_service.dart';
import '../services/routing_service.dart';
import '../services/toast_service.dart';
import '../services/conditional_poi_loader.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/app_logger.dart';
import '../utils/geo_utils.dart';
import '../utils/navigation_utils.dart';
import '../utils/poi_dialog_handler.dart';
import '../utils/route_calculation_helper.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/navigation_card.dart';
import '../widgets/navigation_controls.dart';
import '../widgets/dialogs/route_selection_dialog.dart';
import '../widgets/arrival_dialog.dart';
import '../widgets/map_toggle_button.dart';
import '../widgets/osm_poi_selector_button.dart';
import '../widgets/profile_button.dart';
import '../providers/debug_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/route_surface_helper.dart';
import '../utils/poi_utils.dart';
// Conditional import for 3D map button - use stub on Web
import 'mapbox_map_screen_simple.dart'
    if (dart.library.html) 'mapbox_map_screen_simple_stub.dart';
import 'community/poi_management_screen.dart';
import 'community/hazard_report_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  Timer? _debounceTimer;
  LatLng? _lastGPSPosition;
  LatLng? _originalGPSReference;
  bool _isUserMoving = false;
  bool _hasTriggeredInitialPOILoad = false; // Track if we've loaded POIs on first location

  // Smart reload logic - store loaded bounds and buffer zone
  BoundingBox? _lastLoadedBounds;
  BoundingBox? _reloadTriggerBounds;

  // Compass rotation state (Native only)
  bool _compassRotationEnabled = false;
  double? _lastBearing;
  static const double _compassThreshold = 5.0; // Only rotate if change > 5°

  // Navigation mode: GPS breadcrumb tracking for map rotation
  final List<_LocationBreadcrumb> _breadcrumbs = [];
  double? _lastNavigationBearing; // Smoothed bearing for navigation mode
  static const int _maxBreadcrumbs = 5;
  static const double _minBreadcrumbDistance = 5.0; // meters - responsive at cycling speeds
  static const Duration _breadcrumbMaxAge = Duration(seconds: 20); // 20s window for stable tracking

  // Smooth auto-zoom state
  DateTime? _lastZoomChangeTime;
  double? _currentAutoZoom;
  double? _targetAutoZoom;
  static const Duration _zoomChangeInterval = Duration(seconds: 3);
  static const double _minZoomChangeThreshold = 0.5;

  // Active route for persistent navigation sheet
  RouteResult? _activeRoute;

  @override
  void initState() {
    super.initState();
    AppLogger.separator('MapScreen initState');
    AppLogger.ios('initState called', data: {
      'timestamp': DateTime.now().toIso8601String(),
    });

    // REMOVED: Don't call _onMapReady() prematurely - let GPS trigger natural init
    // Initialize map when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.ios('PostFrameCallback executing', data: {'screen': 'MapScreen'});

      // CRITICAL FIX: Manually trigger location handler for initial load
      // The ref.listen() in build() only fires on CHANGES, not initial value
      final locationAsync = ref.read(locationNotifierProvider);
      locationAsync.whenData((location) {
        if (location != null && !_hasTriggeredInitialPOILoad) {
          AppLogger.ios('MANUAL TRIGGER for initial location', data: {'screen': 'MapScreen'});
          // Give the map a moment to fully initialize before loading POIs
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              AppLogger.ios('Triggering initial POI load via manual handler', data: {'screen': 'MapScreen'});
              _handleGPSLocationChange(location);
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    AppLogger.debug('Disposing map screen', tag: 'MapScreen');
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onMapReady() {
    AppLogger.separator('Map ready');
    setState(() {
      _isMapReady = true;
    });
    AppLogger.success('Map ready flag set to TRUE', tag: 'MAP');

    // DON'T load POIs immediately - wait for GPS location first!
    AppLogger.map('Waiting for GPS location before loading POIs');
    _centerOnUserLocation();

    // Fallback: if POIs haven't loaded after 2 seconds, load them anyway
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isMapReady && !_hasTriggeredInitialPOILoad) {
        AppLogger.warning('Fallback POI load triggered (location might not be available)', tag: 'MAP');
        _loadAllMapDataWithBounds();
        _hasTriggeredInitialPOILoad = true;
      }
    });
  }

  /// Center map on user's GPS location (CRITICAL for OSM POIs to work)
  Future<void> _centerOnUserLocation() async {
    AppLogger.separator('Centering on user location');

    final locationAsync = ref.read(locationNotifierProvider);

    locationAsync.when(
      data: (location) {
        if (location != null) {
          AppLogger.success('Got GPS location', tag: 'LOCATION', data: {
            'lat': location.latitude,
            'lng': location.longitude,
            'accuracy': '${location.accuracy}m',
          });

          final newPosition = LatLng(location.latitude, location.longitude);
          AppLogger.map('Moving map to user location');

          // Only move map if it's ready (prevents FlutterMap exception)
          if (_isMapReady) {
            _mapController.move(newPosition, 15.0);
            AppLogger.success('Map moved', tag: 'MAP', data: {
              'lat': newPosition.latitude,
              'lng': newPosition.longitude,
              'zoom': 15.0,
            });
          } else {
            AppLogger.debug('Map not ready yet, will center on first render', tag: 'MAP');
          }

          // Initialize GPS position tracking
          _lastGPSPosition = newPosition;
          _originalGPSReference = newPosition;

          // NOTE: POI loading will be triggered automatically by the location listener in build()
          AppLogger.success('GPS references initialized', tag: 'MAP');
        } else {
          AppLogger.warning('Location is NULL - GPS not available yet', tag: 'LOCATION');
          AppLogger.debug('Will retry when location becomes available via build() listener', tag: 'MAP');
        }
      },
      loading: () {
        AppLogger.ios('Location still LOADING', data: {
          'note': 'Will load POIs automatically when location becomes available',
        });
      },
      error: (error, stack) {
        AppLogger.error('Location ERROR', tag: 'LOCATION', error: error, data: {
          'note': 'Cannot load POIs without location',
        });
      },
    );
  }

  /// Calculate extended bounds (3x3 of visible area) for smooth panning
  BoundingBox _calculateExtendedBounds(LatLngBounds visibleBounds) {
    final latDiff = visibleBounds.north - visibleBounds.south;
    final lngDiff = visibleBounds.east - visibleBounds.west;

    final latExtension = latDiff;
    final lngExtension = lngDiff;

    final bbox = BoundingBox(
      south: visibleBounds.south - latExtension,
      west: visibleBounds.west - lngExtension,
      north: visibleBounds.north + latExtension,
      east: visibleBounds.east + lngExtension,
    );

    AppLogger.map('Extended bounds calculated', data: {
      'visible_S': visibleBounds.south.toStringAsFixed(4),
      'visible_N': visibleBounds.north.toStringAsFixed(4),
      'visible_W': visibleBounds.west.toStringAsFixed(4),
      'visible_E': visibleBounds.east.toStringAsFixed(4),
      'extended_S': bbox.south.toStringAsFixed(4),
      'extended_N': bbox.north.toStringAsFixed(4),
      'extended_W': bbox.west.toStringAsFixed(4),
      'extended_E': bbox.east.toStringAsFixed(4),
    });

    return bbox;
  }

  /// Calculate reload trigger bounds (10% buffer zone)
  BoundingBox _calculateReloadTriggerBounds(BoundingBox loadedBounds) {
    final latDiff = loadedBounds.north - loadedBounds.south;
    final lngDiff = loadedBounds.east - loadedBounds.west;

    final latBuffer = latDiff * 0.1;
    final lngBuffer = lngDiff * 0.1;

    return BoundingBox(
      south: loadedBounds.south + latBuffer,
      west: loadedBounds.west + lngBuffer,
      north: loadedBounds.north - latBuffer,
      east: loadedBounds.east - lngBuffer,
    );
  }

  /// Check if we should reload data (smart reload logic)
  bool _shouldReloadData(LatLngBounds visibleBounds) {
    if (_reloadTriggerBounds == null) {
      AppLogger.map('First load - should reload = TRUE');
      return true;
    }

    final shouldReload = visibleBounds.south < _reloadTriggerBounds!.south ||
        visibleBounds.north > _reloadTriggerBounds!.north ||
        visibleBounds.west < _reloadTriggerBounds!.west ||
        visibleBounds.east > _reloadTriggerBounds!.east;

    AppLogger.map('Should reload check', data: {'shouldReload': shouldReload});
    if (!shouldReload) {
      AppLogger.debug('Still within buffer zone, skipping reload', tag: 'MAP');
    }

    return shouldReload;
  }

  /// Load all map data (OSM POIs, Warnings) using extended bounds
  void _loadAllMapDataWithBounds({bool forceReload = false}) {
    if (!_isMapReady) {
      AppLogger.warning('Map not ready, skipping data load', tag: 'MAP');
      return;
    }

    try {
      AppLogger.separator('Loading map data');

      final camera = _mapController.camera;
      final latLngBounds = camera.visibleBounds;

      // Check if we should reload (skip check if forceReload is true)
      if (!forceReload && !_shouldReloadData(latLngBounds)) {
        AppLogger.debug('Within loaded bounds, skipping reload', tag: 'MAP');
        return;
      }

      // Calculate extended bounds
      final extendedBounds = _calculateExtendedBounds(latLngBounds);

      AppLogger.map('Starting background data reload');

      // Load data in background
      _loadDataInBackground(extendedBounds);

      // Update stored bounds
      _lastLoadedBounds = extendedBounds;
      _reloadTriggerBounds = _calculateReloadTriggerBounds(extendedBounds);

      AppLogger.success('Background loading initiated', tag: 'MAP');
    } catch (e, stackTrace) {
      AppLogger.error('Error loading map data', tag: 'MAP', error: e, stackTrace: stackTrace);
    }
  }

  /// Load data in background without clearing existing data
  void _loadDataInBackground(BoundingBox extendedBounds) {
    AppLogger.debug('Loading data in background', tag: 'MAP', data: {
      'S': extendedBounds.south.toStringAsFixed(4),
      'N': extendedBounds.north.toStringAsFixed(4),
      'W': extendedBounds.west.toStringAsFixed(4),
      'E': extendedBounds.east.toStringAsFixed(4),
    });

    final mapState = ref.read(mapProvider);
    final loadTypes = <String>[];

    // Only load OSM POIs if toggle is ON
    if (mapState.showOSMPOIs) {
      final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
      AppLogger.debug('Calling OSM POI background load', tag: 'MAP');
      osmPOIsNotifier.loadPOIsInBackground(extendedBounds);
      loadTypes.add('OSM POIs');
    }

    // Only load Community POIs if toggle is ON
    if (mapState.showPOIs) {
      final communityPOIsNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
      AppLogger.debug('Calling community POIs background load', tag: 'MAP');
      communityPOIsNotifier.loadPOIsInBackground(extendedBounds);
      loadTypes.add('Community POIs');
    }

    // Only load Warnings if toggle is ON
    if (mapState.showWarnings) {
      final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
      AppLogger.debug('Calling community warnings background load', tag: 'MAP');
      warningsNotifier.loadWarningsInBackground(extendedBounds);
      loadTypes.add('Warnings');
    }

    AppLogger.success('Background loading calls completed', tag: 'MAP', data: {
      'types': loadTypes.isEmpty ? 'None (all toggles OFF)' : loadTypes.join(', '),
    });
  }

  /// Load OSM POIs only if data doesn't exist or bounds changed significantly
  void _loadOSMPOIsIfNeeded() {
    final camera = _mapController.camera;
    final bounds = _calculateExtendedBounds(camera.visibleBounds);
    ConditionalPOILoader.loadOSMPOIsIfNeeded(
      ref: ref,
      extendedBounds: bounds,
    );
  }

  /// Load Community POIs only if data doesn't exist
  void _loadCommunityPOIsIfNeeded() {
    final camera = _mapController.camera;
    final bounds = _calculateExtendedBounds(camera.visibleBounds);
    ConditionalPOILoader.loadCommunityPOIsIfNeeded(
      ref: ref,
      extendedBounds: bounds,
    );
  }

  /// Load Warnings only if data doesn't exist
  void _loadWarningsIfNeeded() {
    final camera = _mapController.camera;
    final bounds = _calculateExtendedBounds(camera.visibleBounds);
    ConditionalPOILoader.loadWarningsIfNeeded(
      ref: ref,
      extendedBounds: bounds,
    );
  }

  /// Find bicycle parking near destination (500m radius)
  Future<void> _findParkingNearDestination() async {
    AppLogger.success('Finding parking near destination', tag: 'PARKING');

    // Get destination from navigation state
    final navState = ref.read(navigationProvider);
    if (!navState.isNavigating || navState.activeRoute == null) {
      AppLogger.warning('No active navigation to find parking', tag: 'PARKING');
      return;
    }

    final destination = navState.activeRoute!.points.last;

    // End navigation first
    ref.read(navigationProvider.notifier).stopNavigation();
    ref.read(searchProvider.notifier).clearRoute();
    AppLogger.info('Navigation ended to search for parking', tag: 'PARKING');

    // Calculate 500m bounds around destination
    final radiusKm = 0.5; // 500 meters
    const earthRadiusKm = 6371.0;

    final latDelta = (radiusKm / earthRadiusKm) * (180 / 3.14159265359);
    final lonDelta = (radiusKm / earthRadiusKm) * (180 / 3.14159265359) /
                     math.cos(destination.latitude * 3.14159265359 / 180).abs();

    final north = destination.latitude + latDelta;
    final south = destination.latitude - latDelta;
    final east = destination.longitude + lonDelta;
    final west = destination.longitude - lonDelta;

    AppLogger.debug('Parking search bounds', tag: 'PARKING', data: {
      'center': '${destination.latitude},${destination.longitude}',
      'radius': '500m',
      'north': north,
      'south': south,
      'east': east,
      'west': west,
    });

    // Update map bounds to show 500m area
    ref.read(mapProvider.notifier).updateBounds(
      LatLng(south, west),
      LatLng(north, east),
    );

    // Enable OSM POIs with bicycle parking type selected
    ref.read(mapProvider.notifier).setSelectedOSMPOITypes({'bike_parking'});

    // Fit bounds to show the parking search area
    final bounds = LatLngBounds(
      LatLng(south, west),
      LatLng(north, east),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );

    AppLogger.success('Zoomed to parking search area', tag: 'PARKING');

    // Load POIs to ensure parking markers appear
    _loadAllMapDataWithBounds(forceReload: true);

    // Show toast
    ToastService.info('Showing bicycle parking within 500m');
  }

  /// Handle map events
  void _onMapEvent(MapEvent mapEvent) {
    // Set map ready on first event (after FlutterMap fully rendered)
    if (!_isMapReady) {
      AppLogger.success('Map rendered - setting ready flag', tag: 'MAP');
      _onMapReady();
    }

    if (mapEvent is MapEventMove || mapEvent is MapEventMoveStart || mapEvent is MapEventMoveEnd) {
      _isUserMoving = true;

      // Debounce reload
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
        if (_isMapReady) {
          AppLogger.map('Map moved, reloading data (debounced)');
          _loadAllMapDataWithBounds();
          _isUserMoving = false;
        }
      });
    }
  }

  /// Handle GPS location changes (auto-center on significant movement)
  void _handleGPSLocationChange(LocationData? location) {
    if (location != null && _isMapReady) {
      final newGPSPosition = LatLng(location.latitude, location.longitude);
      final navState = ref.read(navigationModeProvider);
      final isNavigationMode = navState.mode == NavMode.navigation;

      // CRITICAL: If this is the first time we have location and haven't loaded POIs yet, do it now!
      if (!_hasTriggeredInitialPOILoad) {
        AppLogger.separator('FIRST LOCATION RECEIVED');
        AppLogger.location('Centering map and loading POIs', data: {
          'lat': location.latitude,
          'lng': location.longitude,
        });

        // Only move map if it's ready
        if (_isMapReady) {
          _mapController.move(newGPSPosition, 15.0);
        }
        _originalGPSReference = newGPSPosition;
        _lastGPSPosition = newGPSPosition;

        // Add delay to ensure map has moved before loading POIs
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            AppLogger.map('Triggering INITIAL POI load');
            _loadAllMapDataWithBounds();
            _hasTriggeredInitialPOILoad = true;
            AppLogger.success('Initial POI load triggered', tag: 'MAP');
          }
        });

        return;
      }

      // Add breadcrumb for navigation mode
      if (isNavigationMode) {
        _addBreadcrumb(location);
      }

      // Auto-center logic (threshold: navigation 3m, exploration 25m)
      if (_originalGPSReference != null) {
        final distance = GeoUtils.calculateDistance(
          _originalGPSReference!.latitude,
          _originalGPSReference!.longitude,
          newGPSPosition.latitude,
          newGPSPosition.longitude,
        );

        final threshold = isNavigationMode ? 3.0 : 25.0;

        // Auto-center if user moved > threshold
        if (distance > threshold) {
          // Navigation mode: continuous tracking with dynamic zoom + rotation
          if (isNavigationMode) {
            // Calculate target zoom (only if auto-zoom enabled)
            final mapState = ref.read(mapProvider);
            final logicalZoom = NavigationUtils.calculateNavigationZoom(location.speed);
            final targetZoom = NavigationUtils.toFlutterMapZoom(logicalZoom);
            _targetAutoZoom = targetZoom;

            // Determine actual zoom to use (with throttling if auto-zoom enabled)
            double actualZoom = _mapController.camera.zoom;

            if (mapState.autoZoomEnabled) {
              final now = DateTime.now();
              final canChangeZoom = _lastZoomChangeTime == null ||
                  now.difference(_lastZoomChangeTime!) >= _zoomChangeInterval;

              if (canChangeZoom) {
                final currentZoom = _currentAutoZoom ?? _mapController.camera.zoom;
                final zoomDifference = (targetZoom - currentZoom).abs();

                // Only change zoom if difference >= 0.5
                if (zoomDifference >= _minZoomChangeThreshold) {
                  _currentAutoZoom = targetZoom;
                  _lastZoomChangeTime = now;
                  actualZoom = targetZoom;

                  AppLogger.map('Auto-zoom change', data: {
                    'from': currentZoom.toStringAsFixed(1),
                    'to': targetZoom.toStringAsFixed(1),
                    'speed': '${(location.speed ?? 0) * 3.6}km/h',
                  });
                } else {
                  actualZoom = currentZoom;
                }
              } else {
                // Keep current auto-zoom during throttle period
                actualZoom = _currentAutoZoom ?? _mapController.camera.zoom;
              }
            }

            _mapController.move(newGPSPosition, actualZoom);

            // Rotate map based on travel direction (keep last rotation if stationary)
            final travelBearing = _calculateTravelDirection();
            if (travelBearing != null) {
              _mapController.rotate(-travelBearing); // Negative: up = direction of travel
              _lastNavigationBearing = travelBearing;

              AppLogger.map('Navigation rotation', data: {
                'bearing': '${travelBearing.toStringAsFixed(1)}°',
                'breadcrumbs': _breadcrumbs.length,
              });
            } else if (_lastNavigationBearing != null) {
              // Keep last bearing when stationary
              _mapController.rotate(-_lastNavigationBearing!);
            }
          } else {
            // Exploration mode: simple auto-center, keep zoom and rotation
            _mapController.move(newGPSPosition, _mapController.camera.zoom);
          }

          AppLogger.location('GPS moved, auto-centering', data: {
            'distance': '${distance.toStringAsFixed(1)}m',
            'mode': navState.mode.name,
            'threshold': '${threshold}m',
          });

          _loadAllMapDataWithBounds();
          _originalGPSReference = newGPSPosition;
        }
      }

      _lastGPSPosition = newGPSPosition;
    }
  }

  /// Handle long press on map to show context menu
  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    if (!_isMapReady) return;

    AppLogger.map('Map long-pressed', data: {
      'lat': point.latitude,
      'lng': point.longitude,
    });

    // Provide haptic feedback for mobile users
    HapticFeedback.mediumImpact();

    // Add search result marker at long-click position
    ref.read(searchProvider.notifier).setSelectedLocation(point.latitude, point.longitude, 'Long-click location');

    _showContextMenu(tapPosition, point);
  }

  /// Show context menu for adding Community POI or reporting hazard
  void _showContextMenu(TapPosition tapPosition, LatLng point) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition.global & Size.zero,
        Offset.zero & overlay.size,
      ),
      color: Colors.white.withOpacity(0.6),
      items: [
        PopupMenuItem<String>(
          value: 'add_poi',
          child: Row(
            children: [
              Icon(Icons.add_location, color: Colors.green[700]),
              const SizedBox(width: 8),
              const Text('Add Community here', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'report_hazard',
          child: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Report Hazard here', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'calculate_route',
          child: Row(
            children: [
              const Text('🚴‍♂️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text('Calculate a route to', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ).then((String? selectedValue) {
      if (selectedValue != null) {
        switch (selectedValue) {
          case 'add_poi':
            _showAddPOIDialog(point);
            break;
          case 'report_hazard':
            _showReportHazardDialog(point);
            break;
          case 'calculate_route':
            _calculateRouteTo(point.latitude, point.longitude);
            break;
        }
      }
    });
  }

  /// Show routing-only dialog (for search results)
  void _showRoutingDialog(TapPosition tapPosition, LatLng point) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition.global & Size.zero,
        Offset.zero & overlay.size,
      ),
      color: Colors.white.withOpacity(0.6),
      items: [
        PopupMenuItem<String>(
          value: 'calculate_route',
          child: Row(
            children: [
              const Text('🚴‍♂️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text('Calculate a route to', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ).then((String? selectedValue) {
      if (selectedValue == 'calculate_route') {
        _calculateRouteTo(point.latitude, point.longitude);
      }
    });
  }

  /// Navigate to Community POI management screen
  void _showAddPOIDialog(LatLng point) async {
    AppLogger.map('Opening Add POI screen', data: {
      'lat': point.latitude,
      'lng': point.longitude,
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => POIManagementScreenWithLocation(
          initialLatitude: point.latitude,
          initialLongitude: point.longitude,
        ),
      ),
    );

    // After returning from POI screen, force reload of map data
    AppLogger.map('Returned from POI screen, reloading map data');
    if (mounted && _isMapReady) {
      _loadAllMapDataWithBounds(forceReload: true);
    }
  }

  /// Navigate to Hazard report screen
  void _showReportHazardDialog(LatLng point) async {
    AppLogger.map('Opening Report Hazard screen', data: {
      'lat': point.latitude,
      'lng': point.longitude,
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HazardReportScreenWithLocation(
          initialLatitude: point.latitude,
          initialLongitude: point.longitude,
        ),
      ),
    );

    // After returning from Warning screen, force reload of map data
    AppLogger.map('Returned from Warning screen, reloading map data');
    if (mounted && _isMapReady) {
      _loadAllMapDataWithBounds(forceReload: true);
    }
  }

  /// Calculate route from current user location to destination
  Future<void> _calculateRouteTo(double destLat, double destLon) async {
    await RouteCalculationHelper.calculateAndShowRoutes(
      context: context,
      ref: ref,
      destLat: destLat,
      destLon: destLon,
      fitBoundsCallback: _fitRouteBounds,
      onRouteSelected: _displaySelectedRoute,
      transparentBarrier: true,
    );
  }

  /// Display the selected route on the map
  void _displaySelectedRoute(RouteResult route) {
    RouteCalculationHelper.displaySelectedRoute(
      ref: ref,
      route: route,
      onCenterMap: () {
        // Center on user's GPS location for navigation (instead of showing entire route)
        final locationAsync = ref.read(locationNotifierProvider);
        final location = locationAsync.value;
        if (location != null && _isMapReady) {
          _mapController.move(
            LatLng(location.latitude, location.longitude),
            NavigationUtils.toFlutterMapZoom(16.0), // 17.0 - matches Mapbox 16.0 visual zoom
          );

          // Calculate initial bearing from current location to first route point
          if (route.points.isNotEmpty) {
            final userPosition = LatLng(location.latitude, location.longitude);
            final firstRoutePoint = route.points.first;
            final initialBearing = GeoUtils.calculateBearing(userPosition, firstRoutePoint);

            // Rotate map to face the route direction
            _mapController.rotate(-initialBearing); // Negative: up = direction of travel
            _lastNavigationBearing = initialBearing;

            AppLogger.debug('Map rotated to initial route bearing', tag: 'ROUTING', data: {
              'bearing': '${initialBearing.toStringAsFixed(1)}°',
            });
          }

          AppLogger.debug('Map centered on user location for navigation', tag: 'ROUTING');
        } else {
          AppLogger.warning('Cannot center map - location not available or map not ready', tag: 'ROUTING');
        }
      },
    );

    // Store active route for state management
    setState(() {
      _activeRoute = route;
    });
  }

  /// Fit map bounds to show entire route
  void _fitRouteBounds(List<LatLng> routePoints) {
    if (routePoints.isEmpty || !_isMapReady) {
      if (!_isMapReady) {
        AppLogger.warning('Cannot fit route bounds - map not ready yet', tag: 'ROUTING');
      }
      return;
    }

    // Calculate bounding box
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLon = routePoints.first.longitude;
    double maxLon = routePoints.first.longitude;

    for (final point in routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    // Create LatLngBounds and fit to map with padding
    final bounds = LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );

    // First, reset rotation to North-up for route preview
    _mapController.rotate(0.0);

    // Then fit bounds with padding
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(100), // Add padding around route
      ),
    );

    AppLogger.debug('Map fitted to route bounds (North-up)', tag: 'ROUTING', data: {
      'minLat': minLat,
      'maxLat': maxLat,
      'minLon': minLon,
      'maxLon': maxLon,
      'rotation': '0° (North)',
    });
  }

  /// Add GPS breadcrumb for navigation mode rotation
  void _addBreadcrumb(LocationData location) {
    final now = DateTime.now();
    final newPosition = LatLng(location.latitude, location.longitude);

    // Remove old breadcrumbs
    _breadcrumbs.removeWhere((b) => now.difference(b.timestamp) > _breadcrumbMaxAge);

    // Only add if moved significant distance from last breadcrumb
    if (_breadcrumbs.isNotEmpty) {
      final lastPos = _breadcrumbs.last.position;
      final distance = GeoUtils.calculateDistance(
        lastPos.latitude, lastPos.longitude,
        newPosition.latitude, newPosition.longitude,
      );
      if (distance < _minBreadcrumbDistance) return; // Too close, skip
    }

    _breadcrumbs.add(_LocationBreadcrumb(
      position: newPosition,
      timestamp: now,
      speed: location.speed,
    ));

    // Keep only recent breadcrumbs
    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
  }

  /// Calculate travel direction from breadcrumbs (returns null if insufficient data)
  double? _calculateTravelDirection() {
    if (_breadcrumbs.length < 2) return null;

    final start = _breadcrumbs.first.position;
    final end = _breadcrumbs.last.position;

    final totalDistance = GeoUtils.calculateDistance(
      start.latitude, start.longitude,
      end.latitude, end.longitude,
    );

    // Need at least 8m total movement (slightly more than GPS accuracy)
    if (totalDistance < 8) return null;

    final bearing = GeoUtils.calculateBearing(start, end);

    // Smooth bearing with last value (70% new, 30% old) - 3x more responsive
    if (_lastNavigationBearing != null) {
      final diff = (bearing - _lastNavigationBearing!).abs();
      if (diff < 180) {
        return bearing * 0.7 + _lastNavigationBearing! * 0.3;
      }
    }

    return bearing;
  }

  void _open3DMap() {
    AppLogger.map('Opening 3D map');

    // Save current map bounds to state before switching
    final bounds = _mapController.camera.visibleBounds;
    final southWest = LatLng(bounds.south, bounds.west);
    final northEast = LatLng(bounds.north, bounds.east);

    ref.read(mapProvider.notifier).updateBounds(southWest, northEast);
    AppLogger.map('Saved bounds for 3D map', data: {
      'sw': '${bounds.south.toStringAsFixed(4)},${bounds.west.toStringAsFixed(4)}',
      'ne': '${bounds.north.toStringAsFixed(4)},${bounds.east.toStringAsFixed(4)}'
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const MapboxMapScreenSimple(),
      ),
    );
  }

  void _showLayerPicker() {
    AppLogger.map('Showing layer picker');
    final mapService = ref.read(mapServiceProvider);
    final currentLayer = ref.read(mapProvider).current2DLayer;

    showModalBottomSheet(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Map Layer',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...MapLayerType.values.map((layer) {
              return ListTile(
                dense: true,
                visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                leading: Icon(
                  _getLayerIcon(layer),
                  color: currentLayer == layer ? Colors.green : Colors.grey,
                ),
                title: Text(
                  mapService.getLayerName(layer),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: currentLayer == layer ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  AppLogger.map('Layer changed', data: {'layer': layer.toString()});
                  ref.read(mapProvider.notifier).change2DLayer(layer);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  IconData _getLayerIcon(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
      case MapLayerType.openCycleMap:
      case MapLayerType.thunderforestCycle:
      case MapLayerType.cyclOSM:
      // case MapLayerType.wike2D:
        return Icons.directions_bike;
      case MapLayerType.thunderforestOutdoors:
        return Icons.terrain;
      case MapLayerType.satellite:
        return Icons.satellite;
      case MapLayerType.terrain:
        return Icons.landscape;
    }
  }

  Marker _buildPOIMarker(OSMPOI poi) {
    final size = MarkerConfig.getRadiusForType(POIMarkerType.osmPOI) * 2;
    final emoji = POITypeConfig.getOSMPOIEmoji(poi.type);

    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () {
          AppLogger.map('POI tapped', data: {
            'name': poi.name,
            'type': poi.type,
          });
          _showPOIDetails(poi);
        },
        child: Container(
          decoration: BoxDecoration(
            color: MarkerConfig.getFillColorForType(POIMarkerType.osmPOI),
            shape: BoxShape.circle,
            border: Border.all(
              color: MarkerConfig.getBorderColorForType(POIMarkerType.osmPOI),
              width: MarkerConfig.circleStrokeWidth,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            emoji,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: size * 0.5, height: 1.0),
          ),
        ),
      ),
    );
  }

  Marker _buildWarningMarker(CommunityWarning warning) {
    final size = MarkerConfig.getRadiusForType(POIMarkerType.warning) * 2;
    final emoji = POITypeConfig.getWarningEmoji(warning.type);

    return Marker(
      point: LatLng(warning.latitude, warning.longitude),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () {
          AppLogger.map('Warning tapped', data: {'type': warning.type});
          _showWarningDetails(warning);
        },
        child: Container(
          decoration: BoxDecoration(
            color: MarkerConfig.getFillColorForType(POIMarkerType.warning),
            shape: BoxShape.circle,
            border: Border.all(
              color: MarkerConfig.getBorderColorForType(POIMarkerType.warning),
              width: MarkerConfig.circleStrokeWidth,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            emoji,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: size * 0.5, height: 1.0),
          ),
        ),
      ),
    );
  }

  Marker _buildCommunityPOIMarker(CyclingPOI poi) {
    final size = MarkerConfig.getRadiusForType(POIMarkerType.communityPOI) * 2;
    final emoji = POITypeConfig.getCommunityPOIEmoji(poi.type);

    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () {
          AppLogger.map('Community POI tapped', data: {'name': poi.name});
          _showCommunityPOIDetails(poi);
        },
        child: Container(
          decoration: BoxDecoration(
            color: MarkerConfig.getFillColorForType(POIMarkerType.communityPOI),
            shape: BoxShape.circle,
            border: Border.all(
              color: MarkerConfig.getBorderColorForType(POIMarkerType.communityPOI),
              width: MarkerConfig.circleStrokeWidth,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            emoji,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: size * 0.5, height: 1.0),
          ),
        ),
      ),
    );
  }

  Marker _buildSearchResultMarker(double latitude, double longitude) {
    // Match user location marker size (12.0 radius = 24.0 diameter)
    final size = MarkerConfig.getRadiusForType(POIMarkerType.userLocation) * 2;
    return Marker(
      point: LatLng(latitude, longitude),
      width: size,
      height: size,
      alignment: Alignment.center, // Center-aligned like other POIs
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x33757575), // Grey with same transparency as user location (~20% opacity)
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.grey.shade700, // Dark grey border
            width: MarkerConfig.circleStrokeWidth,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.add,
          color: Colors.red, // Red + symbol
          size: size * 0.6,
        ),
      ),
    );
  }

  /// Build road sign warning marker (orange circle matching community hazards style)
  Widget _buildRoadSignMarker(String surfaceType) {
    // Match community hazard marker size exactly
    final size = MarkerConfig.getRadiusForType(POIMarkerType.warning) * 2;

    // Get surface-specific icon
    final surfaceStr = surfaceType.toLowerCase();
    IconData iconData;

    if (surfaceStr.contains('gravel') || surfaceStr.contains('unpaved')) {
      iconData = Icons.texture; // Gravel/unpaved
    } else if (surfaceStr.contains('dirt') || surfaceStr.contains('sand') ||
               surfaceStr.contains('grass') || surfaceStr.contains('mud')) {
      iconData = Icons.warning; // Poor surfaces
    } else if (surfaceStr.contains('cobble') || surfaceStr.contains('sett')) {
      iconData = Icons.grid_4x4; // Cobblestone
    } else {
      iconData = Icons.warning; // Default warning
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Orange with ~20% opacity to match community hazard transparency
        color: const Color(0x33FFE0B2), // orange.shade100 with ~20% opacity
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.orange, // Orange border
          width: MarkerConfig.circleStrokeWidth,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        iconData,
        size: size * 0.5,
        color: Colors.orange.shade900,
      ),
    );
  }

  void _showPOIDetails(OSMPOI poi) {
    POIDialogHandler.showPOIDetails(
      context: context,
      poi: poi,
      onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude),
      transparentBarrier: true,
      compact: false,
    );
  }

  void _showWarningDetails(CommunityWarning warning) {
    POIDialogHandler.showWarningDetails(
      context: context,
      ref: ref,
      warning: warning,
      onDataChanged: () {
        if (mounted && _isMapReady) {
          _loadAllMapDataWithBounds(forceReload: true);
        }
      },
      transparentBarrier: true,
      compact: false,
    );
  }

  void _showCommunityPOIDetails(CyclingPOI poi) {
    POIDialogHandler.showCommunityPOIDetails(
      context: context,
      ref: ref,
      poi: poi,
      onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude),
      onDataChanged: () {
        if (mounted && _isMapReady) {
          _loadAllMapDataWithBounds(forceReload: true);
        }
      },
      compact: false,
      transparentBarrier: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('Building widget', tag: 'MapScreen');

    final locationAsync = ref.watch(locationNotifierProvider);
    final poisAsync = ref.watch(osmPOIsNotifierProvider);
    final communityPOIsAsync = ref.watch(cyclingPOIsBoundsNotifierProvider);
    final warningsAsync = ref.watch(communityWarningsBoundsNotifierProvider);
    final mapState = ref.watch(mapProvider);
    final compassHeading = kIsWeb ? null : ref.watch(compassNotifierProvider);

    // Listen for location changes to trigger POI loading
    ref.listen<AsyncValue<LocationData?>>(locationNotifierProvider, (previous, next) {
      next.whenData((location) {
        if (location != null) {
          AppLogger.location('Location changed via listener');
          _handleGPSLocationChange(location);
        }
      });
    });

    // Listen for compass changes to rotate map (Native only, with toggle + threshold)
    if (!kIsWeb) {
      ref.listen<double?>(compassNotifierProvider, (previous, next) {
        if (!_compassRotationEnabled || next == null || !_isMapReady || _isUserMoving) {
          return;
        }

        // Only rotate if change is significant (debouncing)
        if (_lastBearing != null) {
          final diff = (next - _lastBearing!).abs();
          if (diff < _compassThreshold) {
            return; // Skip small changes
          }
        }

        _lastBearing = next;

        // Rotate map to match compass heading
        // flutter_map rotation is counter-clockwise, compass is clockwise
        // So we need to negate the heading
        final rotation = -next;
        AppLogger.debug('Rotating map', tag: 'COMPASS', data: {
          'rotation': '${rotation.toStringAsFixed(1)}°',
          'heading': '${next}°',
          'threshold': _compassThreshold,
        });
        _mapController.rotate(rotation);
      });
    }

    // Listen for OSM POI state changes to trigger reload ONLY when first enabled
    ref.listen<MapState>(mapProvider, (previous, next) {
      if (!_isMapReady) return;

      // Only reload if POIs were just enabled (false -> true)
      // Type changes just filter the existing data client-side, no need to reload
      final previousShowOSM = previous?.showOSMPOIs ?? false;
      final nextShowOSM = next.showOSMPOIs;
      final osmJustEnabled = !previousShowOSM && nextShowOSM;

      if (osmJustEnabled) {
        AppLogger.map('OSM POIs enabled, triggering initial load');
        _loadAllMapDataWithBounds(forceReload: true);
      }
    });

    // Listen for arrival at destination
    ref.listen(navigationProvider, (previous, next) {
      // Show arrival dialog when user arrives
      if (next.hasArrived && !(previous?.hasArrived ?? false)) {
        AppLogger.success('Showing arrival dialog', tag: 'NAVIGATION');
        final distance = next.totalDistanceRemaining;

        // Show arrival dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ArrivalDialog(
            destinationName: 'Your Destination',
            finalDistance: distance,
            onFindParking: () => _findParkingNearDestination(),
          ),
        );
      }
    });

    // Build marker list
    List<Marker> markers = [];

    // Add user location marker with direction indicator
    locationAsync.whenData((location) {
      if (location != null) {
        final navState = ref.read(navigationModeProvider);
        final isNavigationMode = navState.mode == NavMode.navigation;

        AppLogger.map('Adding user location marker', data: {
          'lat': location.latitude,
          'lng': location.longitude,
          'navMode': navState.mode.name,
        });

        // Use navigation bearing if available (from route or GPS movement),
        // otherwise use compass/GPS heading as fallback
        double? heading;
        if (isNavigationMode && _lastNavigationBearing != null) {
          // Use calculated navigation bearing (from route or breadcrumbs)
          heading = _lastNavigationBearing;
        } else {
          // Fallback to compass heading on Native, or GPS heading
          heading = !kIsWeb && compassHeading != null ? compassHeading : location.heading;
        }
        final hasHeading = heading != null && heading >= 0;

        AppLogger.map('Marker heading', data: {
          'heading': heading?.toStringAsFixed(1),
          'hasHeading': hasHeading,
          'isNavigationMode': isNavigationMode,
          'source': isNavigationMode && _lastNavigationBearing != null ? 'navigation' : 'gps/compass',
        });

        final userSize = MarkerConfig.getRadiusForType(POIMarkerType.userLocation) * 2;
        markers.add(
          Marker(
            point: LatLng(location.latitude, location.longitude),
            width: userSize,
            height: userSize,
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: (isNavigationMode && hasHeading) ? (heading * math.pi / 180) : 0, // Rotate only in nav mode
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer circle (accuracy indicator)
                  Container(
                    decoration: BoxDecoration(
                      color: MarkerConfig.getFillColorForType(POIMarkerType.userLocation),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MarkerConfig.getBorderColorForType(POIMarkerType.userLocation),
                        width: MarkerConfig.circleStrokeWidth,
                      ),
                    ),
                  ),
                  // Icon: Arrow in navigation mode, dot in exploration mode
                  if (isNavigationMode && hasHeading)
                    Icon(
                      Icons.navigation,
                      color: MarkerConfig.getBorderColorForType(POIMarkerType.userLocation),
                      size: userSize * 0.6,
                    )
                  else
                    Icon(
                      Icons.circle,
                      color: MarkerConfig.getBorderColorForType(POIMarkerType.userLocation),
                      size: userSize * 0.4, // Smaller dot for exploration mode
                    ),
                ],
              ),
            ),
          ),
        );
      }
    });

    // Add OSM POI markers (only if showOSMPOIs is true)
    if (mapState.showOSMPOIs) {
      poisAsync.whenData((pois) {
        // Filter POIs based on selected types using shared utility
        final filteredPOIs = POIUtils.filterPOIsByType(pois, mapState.selectedOSMPOITypes);

        AppLogger.map('Adding OSM POI markers', data: {
          'total': pois.length,
          'filtered': filteredPOIs.length,
          'selectedTypes': mapState.selectedOSMPOITypes?.join(', ') ?? 'all',
        });
        markers.addAll(filteredPOIs.map((poi) => _buildPOIMarker(poi)));
      });
    } else {
      AppLogger.debug('OSM POIs hidden by toggle', tag: 'MAP');
    }

    // Add Community POI markers (only if showPOIs is true)
    if (mapState.showPOIs) {
      communityPOIsAsync.when(
        data: (communityPOIs) {
          AppLogger.map('Adding Community POI markers', data: {'count': communityPOIs.length});
          markers.addAll(communityPOIs.map((poi) => _buildCommunityPOIMarker(poi)));
        },
        loading: () {
          AppLogger.debug('Community POIs still loading', tag: 'MAP');
        },
        error: (error, stackTrace) {
          AppLogger.error('Community POIs error', tag: 'MAP', error: error, stackTrace: stackTrace);
        },
      );
    } else {
      AppLogger.debug('Community POIs hidden by toggle', tag: 'MAP');
    }

    // Add warning markers (only if showWarnings is true)
    if (mapState.showWarnings) {
      warningsAsync.whenData((warnings) {
        AppLogger.map('Adding warning markers', data: {'count': warnings.length});
        markers.addAll(warnings.map((warning) => _buildWarningMarker(warning)));
      });
    } else {
      AppLogger.debug('Warnings hidden by toggle', tag: 'MAP');
    }

    // Add search result marker if location is selected
    final searchState = ref.watch(searchProvider);
    if (searchState.selectedLocation != null) {
      final selectedLoc = searchState.selectedLocation!;
      AppLogger.map('Adding search result marker', data: {
        'lat': selectedLoc.latitude,
        'lon': selectedLoc.longitude,
      });
      markers.add(_buildSearchResultMarker(selectedLoc.latitude, selectedLoc.longitude));
    }

    // Add surface warning markers during navigation
    final navState = ref.read(navigationProvider);
    if (navState.isNavigating && navState.activeRoute != null) {
      final pathDetails = navState.activeRoute!.pathDetails;
      if (pathDetails != null && pathDetails.containsKey('surface')) {
        final warningMarkers = RouteSurfaceHelper.getSurfaceWarningMarkers(
          navState.activeRoute!.points,
          pathDetails,
        );

        for (final warningMarker in warningMarkers) {
          // Use same size as community hazard markers
          final size = MarkerConfig.getRadiusForType(POIMarkerType.warning) * 2;
          markers.add(Marker(
            width: size,
            height: size,
            point: warningMarker.position,
            child: _buildRoadSignMarker(warningMarker.surfaceType),
          ));
        }

        AppLogger.debug('Added ${warningMarkers.length} surface warning markers', tag: 'MAP');
      }

      // Add route hazards markers during navigation
      if (navState.activeRoute!.routeHazards != null && navState.activeRoute!.routeHazards!.isNotEmpty) {
        final routeHazards = navState.activeRoute!.routeHazards!;
        for (final hazard in routeHazards) {
          markers.add(_buildWarningMarker(hazard.warning));
        }
        AppLogger.debug('Added ${routeHazards.length} route hazard markers', tag: 'MAP');
      }
    }

    AppLogger.map('Total markers on map', data: {'count': markers.length});

    // Get map center for search
    final mapCenter = _isMapReady
        ? _mapController.camera.center
        : (locationAsync.value != null
            ? LatLng(locationAsync.value!.latitude, locationAsync.value!.longitude)
            : const LatLng(0, 0));

    // Watch navigation state to determine layout
    final navigationState = ref.watch(navigationProvider);
    final isNavigating = navigationState.isNavigating;

    return Scaffold(
      backgroundColor: Colors.white,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;

          if (isLandscape && isNavigating) {
            // Landscape layout: Navigation card on left (50%), map on right (50%)
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start, // Align children to top
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  child: const NavigationCard(),
                ),
                Expanded(
                  child: Stack(
                    children: _buildMapAndControls(context, locationAsync, poisAsync, communityPOIsAsync, warningsAsync, mapState, markers, mapCenter),
                  ),
                ),
              ],
            );
          } else {
            // Portrait layout: Navigation card at top, map below
            return Column(
              children: [
                if (isNavigating) const NavigationCard(),
                Expanded(
                  child: Stack(
                    children: _buildMapAndControls(context, locationAsync, poisAsync, communityPOIsAsync, warningsAsync, mapState, markers, mapCenter),
                  ),
                ),
              ],
            );
          }
        },
      ),
      floatingActionButtonLocation: null,
    );
  }

  /// Build map and controls (reused in both orientations)
  List<Widget> _buildMapAndControls(
    BuildContext context,
    AsyncValue<LocationData?> locationAsync,
    AsyncValue<List<dynamic>> poisAsync,
    AsyncValue<List<dynamic>> communityPOIsAsync,
    AsyncValue<List<dynamic>> warningsAsync,
    MapState mapState,
    List<Marker> markers,
    LatLng mapCenter,
  ) {
    return [
      // Main map content
      locationAsync.when(
            data: (location) {
              if (location == null) {
                AppLogger.warning('Location is NULL - showing loading indicator', tag: 'MAP');
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Waiting for GPS location...'),
                    ],
                  ),
                );
              }

              AppLogger.map('Building map with location', data: {
                'lat': location.latitude,
                'lng': location.longitude,
              });

              // Use saved bounds if available (from 3D map), otherwise use center+zoom
              final hasBounds = mapState.southWest != null && mapState.northEast != null;

              if (hasBounds) {
                AppLogger.map('2D Map using saved bounds', data: {
                  'sw': '${mapState.southWest!.latitude},${mapState.southWest!.longitude}',
                  'ne': '${mapState.northEast!.latitude},${mapState.northEast!.longitude}'
                });
              } else {
                final flutter2DZoom = mapState.zoom - 1.0;
                AppLogger.map('2D Map using default zoom', data: {'flutter_zoom': flutter2DZoom});
              }

              final mapOptions = hasBounds
                  ? MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: LatLngBounds(mapState.southWest!, mapState.northEast!),
                        padding: const EdgeInsets.all(0),
                      ),
                      initialRotation: 0.0, // North-up (exploration mode)
                      onMapEvent: _onMapEvent,
                      onLongPress: _onMapLongPress,
                    )
                  : MapOptions(
                      initialCenter: LatLng(location.latitude, location.longitude),
                      initialZoom: mapState.zoom - 1.0, // Convert from Mapbox zoom scale
                      initialRotation: 0.0, // North-up (exploration mode)
                      onMapEvent: _onMapEvent,
                      onLongPress: _onMapLongPress,
                    );

              // Get route from search provider
              final searchState = ref.watch(searchProvider);
              final routePoints = searchState.routePoints;

              return FlutterMap(
                mapController: _mapController,
                options: mapOptions,
                children: [
                  TileLayer(
                    urlTemplate: mapState.tileUrl,
                    userAgentPackageName: 'com.popibiking.popiBikingFresh',
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  // Preview routes layer (shown during route selection)
                  if (searchState.previewFastestRoute != null && (searchState.previewSafestRoute != null || searchState.previewShortestRoute != null))
                    PolylineLayer(
                      polylines: [
                        // Fastest route in red (car)
                        Polyline(
                          points: searchState.previewFastestRoute!,
                          strokeWidth: 8.0,
                          color: Colors.red,
                          borderStrokeWidth: 3.0,
                          borderColor: Colors.white,
                        ),
                        // Safest route in green (bike - if exists)
                        if (searchState.previewSafestRoute != null)
                          Polyline(
                            points: searchState.previewSafestRoute!,
                            strokeWidth: 8.0,
                            color: Colors.green,
                            borderStrokeWidth: 3.0,
                            borderColor: Colors.white,
                          ),
                        // Shortest route in blue (foot/walking - if exists)
                        if (searchState.previewShortestRoute != null)
                          Polyline(
                            points: searchState.previewShortestRoute!,
                            strokeWidth: 8.0,
                            color: Colors.blue,
                            borderStrokeWidth: 3.0,
                            borderColor: Colors.white,
                          ),
                      ],
                    ),
                  // Selected route polyline layer (below markers)
                  if (routePoints != null && routePoints.isNotEmpty && searchState.previewFastestRoute == null)
                    Consumer(
                      builder: (context, ref, _) {
                        final navState = ref.watch(navigationProvider);

                        // During navigation with surface data, render color-coded segments
                        if (navState.isNavigating && navState.activeRoute != null) {
                          final pathDetails = navState.activeRoute!.pathDetails;

                          if (pathDetails != null && pathDetails.containsKey('surface')) {
                            final segments = RouteSurfaceHelper.createSurfaceSegments(
                              navState.activeRoute!.points,
                              pathDetails,
                            );

                            return PolylineLayer(
                              polylines: segments.map((segment) => Polyline(
                                points: segment.points,
                                strokeWidth: 6.0,
                                color: segment.color,
                                borderStrokeWidth: 2.0,
                                borderColor: Colors.white,
                              )).toList(),
                            );
                          }
                        }

                        // Fallback: single color route
                        return PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              strokeWidth: 6.0,
                              color: const Color(0xFF85a78b),
                              borderStrokeWidth: 2.0,
                              borderColor: Colors.white,
                            ),
                          ],
                        );
                      },
                    ),
                  if (markers.isNotEmpty)
                    MarkerLayer(
                      markers: markers,
                    ),
                ],
              );
            },
            loading: () {
              AppLogger.debug('Location LOADING - showing spinner', tag: 'MAP');
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Getting your location...'),
                    SizedBox(height: 8),
                    Text('(Make sure to allow location permission)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            },
            error: (error, stack) {
              AppLogger.error('Location ERROR', tag: 'MAP', error: error);
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Error: $error',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        AppLogger.debug('User requested permission retry', tag: 'MAP');
                        ref.read(locationNotifierProvider.notifier).requestPermission();
                      },
                      child: const Text('Request Permission'),
                    ),
                  ],
                ),
              );
            },
          ),

          // Toggle buttons on the right side
          Positioned(
            top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
            right: 10,
            child: Column(
              children: [
                // Check zoom level - disable toggles if zoom <= 12
                Builder(
                  builder: (context) {
                    final currentZoom = _isMapReady ? _mapController.camera.zoom : 15.0;
                    final togglesEnabled = currentZoom > 12.0;

                    return Column(
                      children: [
                        // OSM POI selector (multi-choice dropdown)
                        OSMPOISelectorButton(
                          count: poisAsync.value != null
                              ? POIUtils.filterPOIsByType(
                                  poisAsync.value!.cast<OSMPOI>(),
                                  mapState.selectedOSMPOITypes,
                                ).length
                              : 0,
                          enabled: togglesEnabled,
                        ),
                        const SizedBox(height: 8),

                        // Community POI toggle with count
                        MapToggleButton(
                          isActive: mapState.showPOIs,
                          icon: Icons.location_on,
                          activeColor: Colors.green,
                          count: communityPOIsAsync.value?.length ?? 0,
                          enabled: togglesEnabled,
                          onPressed: () {
                            AppLogger.map('Community POI toggle pressed');
                            final wasOff = !mapState.showPOIs;
                            ref.read(mapProvider.notifier).togglePOIs();
                            // If turning ON, load only this feature if needed
                            if (wasOff) {
                              _loadCommunityPOIsIfNeeded();
                            }
                          },
                          tooltip: 'Toggle Community POIs',
                        ),
                        const SizedBox(height: 8),

                        // Warning toggle with count
                        MapToggleButton(
                          isActive: mapState.showWarnings,
                          icon: Icons.warning,
                          activeColor: Colors.orange,
                          count: warningsAsync.value?.length ?? 0,
                          enabled: togglesEnabled,
                          onPressed: () {
                            AppLogger.map('Warning toggle pressed');
                            final wasOff = !mapState.showWarnings;
                            ref.read(mapProvider.notifier).toggleWarnings();
                            // If turning ON, load only this feature if needed
                            if (wasOff) {
                              _loadWarningsIfNeeded();
                            }
                          },
                          tooltip: 'Toggle Warnings',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),

                // Zoom controls
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  onPressed: () {
                    AppLogger.map('Zoom in pressed');
                    final currentZoom = _mapController.camera.zoom;
                    // Use floor to get integer zoom: 17.6 -> 18
                    final newZoom = currentZoom.floor() + 1.0;
                    _mapController.move(
                      _mapController.camera.center,
                      newZoom,
                    );
                    AppLogger.map('Zoom changed', data: {
                      'from': currentZoom,
                      'to': newZoom,
                    });
                    setState(() {}); // Refresh to update zoom display
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 2),

                // Zoom level display
                if (_isMapReady)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _mapController.camera.zoom.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                if (_isMapReady)
                  const SizedBox(height: 2),

                // Zoom out button
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  onPressed: () {
                    AppLogger.map('Zoom out pressed');
                    final currentZoom = _mapController.camera.zoom;
                    // Use floor to get integer zoom: 17.6 -> 17
                    final newZoom = currentZoom.floor() - 1.0;
                    _mapController.move(
                      _mapController.camera.center,
                      newZoom,
                    );
                    AppLogger.map('Zoom changed', data: {
                      'from': currentZoom,
                      'to': newZoom,
                    });

                    // Auto-turn OFF all POI toggles if zooming to <= 12
                    if (newZoom <= 12.0) {
                      final mapState = ref.read(mapProvider);
                      if (mapState.showOSMPOIs) {
                        ref.read(mapProvider.notifier).toggleOSMPOIs();
                      }
                      if (mapState.showPOIs) {
                        ref.read(mapProvider.notifier).togglePOIs();
                      }
                      if (mapState.showWarnings) {
                        ref.read(mapProvider.notifier).toggleWarnings();
                      }
                      AppLogger.map('Auto-disabled all POI toggles at zoom <= 12');
                    }

                    setState(() {}); // Refresh to update zoom display and toggles
                  },
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),

          // Bottom-left controls: navigation mode, compass, center, reload
          Positioned(
            bottom: kIsWeb ? 10 : 30,
            left: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Auto-zoom toggle button (only show in navigation mode)
                Consumer(
                  builder: (context, ref, child) {
                    final navState = ref.watch(navigationModeProvider);
                    final isNavigationMode = navState.mode == NavMode.navigation;
                    final mapState = ref.watch(mapProvider);

                    if (!isNavigationMode) return const SizedBox.shrink();

                    return FloatingActionButton(
                      mini: true,
                      heroTag: 'auto_zoom_toggle_2d',
                      onPressed: () {
                        ref.read(mapProvider.notifier).toggleAutoZoom();
                        AppLogger.map('Auto-zoom ${mapState.autoZoomEnabled ? "disabled" : "enabled"} (2D)');
                      },
                      backgroundColor: mapState.autoZoomEnabled ? Colors.blue : Colors.grey.shade300,
                      foregroundColor: mapState.autoZoomEnabled ? Colors.white : Colors.grey.shade600,
                      tooltip: mapState.autoZoomEnabled ? 'Disable Auto-Zoom' : 'Enable Auto-Zoom',
                      child: Icon(mapState.autoZoomEnabled ? Icons.zoom_out_map : Icons.zoom_out_map_outlined),
                    );
                  },
                ),
                // Spacing after auto-zoom button (only in navigation mode)
                Consumer(
                  builder: (context, ref, child) {
                    final navState = ref.watch(navigationModeProvider);
                    return navState.mode == NavMode.navigation ? const SizedBox(height: 8) : const SizedBox.shrink();
                  },
                ),
                // Compass rotation toggle button (Native only)
                if (!kIsWeb)
                  FloatingActionButton(
                    mini: true, // Match zoom button size
                    heroTag: 'compass_rotation_toggle_2d',
                    onPressed: () {
                      setState(() {
                        _compassRotationEnabled = !_compassRotationEnabled;
                        if (!_compassRotationEnabled) {
                          // Reset map to north when disabling
                          _mapController.rotate(0);
                          _lastBearing = null;
                        }
                      });
                      AppLogger.map('Compass rotation ${_compassRotationEnabled ? "enabled" : "disabled"} (2D)');
                    },
                    backgroundColor: _compassRotationEnabled ? Colors.purple : Colors.grey.shade300,
                    foregroundColor: _compassRotationEnabled ? Colors.white : Colors.grey.shade600,
                    tooltip: 'Toggle Compass Rotation',
                    child: Icon(_compassRotationEnabled ? Icons.explore : Icons.explore_off),
                  ),
                if (!kIsWeb) const SizedBox(height: 8), // Match zoom spacing
                // GPS center button
                FloatingActionButton(
                  mini: true, // Match zoom button size
                  heroTag: 'my_location',
                  onPressed: () {
                    AppLogger.map('My location button pressed');
                    locationAsync.whenData((location) {
                      if (location != null) {
                        AppLogger.map('Centering on GPS location');
                        _mapController.move(LatLng(location.latitude, location.longitude), 15);
                        _loadAllMapDataWithBounds();
                      }
                    });
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.urbanBlue,
                  tooltip: 'Center on Location',
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                // Reload POIs button
                FloatingActionButton(
                  mini: true, // Match zoom button size
                  heroTag: 'reload_pois_2d',
                  onPressed: () {
                    AppLogger.map('Manual POI reload requested (2D)');
                    _loadAllMapDataWithBounds(forceReload: true);
                  },
                  backgroundColor: Colors.orange,
                  tooltip: 'Reload POIs',
                  child: const Icon(Icons.refresh),
                ),
                const SizedBox(height: 8),
                // Debug toggle button
                Builder(
                  builder: (context) {
                    final debugState = ref.watch(debugProvider);
                    return FloatingActionButton(
                      mini: true,
                      heroTag: 'debug_toggle_2d',
                      onPressed: () {
                        ref.read(debugProvider.notifier).toggleVisibility();
                      },
                      backgroundColor: debugState.isVisible ? Colors.red : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      tooltip: 'Debug Tracking',
                      child: const Icon(Icons.bug_report),
                    );
                  },
                ),
                // Navigation controls (End + Mute buttons) - spacing only when navigating
                Consumer(
                  builder: (context, ref, child) {
                    final navState = ref.watch(navigationProvider);
                    if (!navState.isNavigating) return const SizedBox.shrink();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        NavigationControls(
                          onNavigationEnded: () {
                            setState(() {
                              _activeRoute = null;
                            });
                            // Reset rotation to North-up after ending navigation
                            _mapController.rotate(0.0);
                            AppLogger.debug('Reset map rotation to North after navigation ended', tag: 'NAVIGATION');
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Bottom-right controls: tiles selector, 3D switch
          Positioned(
            bottom: kIsWeb ? 10 : 30,
            right: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Layer picker button (tiles selector)
                FloatingActionButton(
                  mini: true, // Match zoom button size
                  heroTag: 'layer_picker',
                  onPressed: _showLayerPicker,
                  backgroundColor: Colors.blue,
                  tooltip: 'Change Map Layer',
                  child: const Icon(Icons.layers),
                ),
                // 3D Map button - only show on Native (not on web/PWA)
                if (!kIsWeb) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    mini: true, // Match zoom button size
                    heroTag: '3d_map',
                    onPressed: _open3DMap,
                    backgroundColor: Colors.green,
                    tooltip: 'Switch to 3D Map',
                    child: const Icon(Icons.terrain),
                  ),
                ],
              ],
            ),
          ),

          // Search button (top-left, yellow) - rendered on top
          Positioned(
            top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
            left: 10,
            child: FloatingActionButton(
              mini: true,
              heroTag: 'search_button',
              backgroundColor: const Color(0xFFFFEB3B), // Yellow
              foregroundColor: Colors.black87,
              onPressed: () {
                AppLogger.map('Search button pressed');
                ref.read(searchProvider.notifier).toggleSearchBar();
              },
              tooltip: 'Search',
              child: const Icon(Icons.search),
            ),
          ),

          // Route navigation sheet (persistent bottom sheet, non-modal)
          // Hidden when turn-by-turn navigation is active (new NavigationCard is used instead)

          // Search bar widget (slides down from top) - rendered on top of everything
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SearchBarWidget(
              mapCenter: mapCenter,
              onResultTap: (lat, lon) {
                AppLogger.map('Search result tapped - navigating to location', data: {
                  'lat': lat,
                  'lon': lon,
                });
                // Set selected location to show marker
                ref.read(searchProvider.notifier).setSelectedLocation(lat, lon, 'Search Result');

                // Navigate to location
                _mapController.move(LatLng(lat, lon), 16.0);
                _loadAllMapDataWithBounds();

                // Show routing-only dialog at center of screen
                // Calculate center position after a short delay to let map move
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    final RenderBox? box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final size = box.size;
                      final center = Offset(size.width / 2, size.height / 2);
                      final tapPosition = TapPosition(center, center);
                      _showRoutingDialog(tapPosition, LatLng(lat, lon));
                    }
                  }
                });
              },
            ),
          ),

      // Debug overlay - on top of everything
      const DebugOverlay(),

      // Profile button - top-right corner
      const Positioned(
        top: 16,
        right: 16,
        child: ProfileButton(),
      ),
    ]; // End map and controls list
  }
}

/// Helper class for tracking GPS breadcrumbs (navigation mode)
class _LocationBreadcrumb {
  final LatLng position;
  final DateTime timestamp;
  final double? speed; // m/s

  _LocationBreadcrumb({
    required this.position,
    required this.timestamp,
    this.speed,
  });
}
