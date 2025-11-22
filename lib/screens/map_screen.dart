import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../providers/compass_provider.dart';
import '../providers/search_provider.dart';
import '../providers/navigation_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_visibility_provider.dart';
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
import '../utils/map_navigation_tracker.dart';
import '../utils/map_bounds_utils.dart';
import '../utils/mapbox_marker_utils.dart';
import '../models/map_models.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/navigation_card.dart';
import '../widgets/navigation_controls.dart';
import '../widgets/arrival_dialog.dart';
import '../widgets/map_toggle_button.dart';
import '../widgets/common_dialog.dart';
import '../widgets/osm_poi_selector_button.dart';
import '../widgets/profile_button.dart';
import '../widgets/map_controls/top_right_controls.dart';
import '../widgets/map_controls/bottom_left_controls.dart';
import '../widgets/map_controls/bottom_right_controls.dart';
import '../providers/debug_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/route_surface_helper.dart';
import '../utils/poi_utils.dart';
// Conditional import for 3D map button - use stub on Web
import 'mapbox_map_screen_simple.dart'
    if (dart.library.html) 'mapbox_map_screen_simple_stub.dart';
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
  final MapNavigationTracker _navigationTracker = MapNavigationTracker();

  // Smooth auto-zoom state
  DateTime? _lastZoomChangeTime;
  double? _currentAutoZoom;
  double? _targetAutoZoom;
  static const Duration _zoomChangeInterval = Duration(seconds: 3);
  static const double _minZoomChangeThreshold = 0.5;

  // Active route for persistent navigation sheet
  RouteResult? _activeRoute;

  // Track displayed marker counts for toggle badges
  int _displayedOSMPOICount = 0;
  int _displayedWarningCount = 0;
  int _displayedFavoritesCount = 0;

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
    return MapBoundsUtils.calculateExtendedBounds(visibleBounds);
  }

  /// Calculate reload trigger bounds (10% buffer zone)
  BoundingBox _calculateReloadTriggerBounds(BoundingBox loadedBounds) {
    return MapBoundsUtils.calculateReloadTriggerBounds(loadedBounds);
  }

  /// Check if we should reload data (smart reload logic)
  bool _shouldReloadData(LatLngBounds visibleBounds) {
    return MapBoundsUtils.shouldReloadData(visibleBounds, _reloadTriggerBounds);
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

    // Restore POI visibility to pre-route-selection state
    RouteCalculationHelper.restorePOIStateAfterNavigation(ref);

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

        // Auto-center if user moved > threshold AND auto-zoom is enabled
        final mapState = ref.read(mapProvider);
        if (distance > threshold && mapState.autoZoomEnabled) {
          // Navigation mode: continuous tracking with dynamic zoom + rotation
          if (isNavigationMode) {
            // Calculate target zoom
            final logicalZoom = NavigationUtils.calculateNavigationZoom(location.speed);
            final targetZoom = NavigationUtils.toFlutterMapZoom(logicalZoom);
            _targetAutoZoom = targetZoom;

            // Determine actual zoom to use (with throttling)
            double actualZoom = _mapController.camera.zoom;
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

            _mapController.move(newGPSPosition, actualZoom);

            // Rotate map based on travel direction (keep last rotation if stationary)
            final travelBearing = _calculateTravelDirection();
            if (travelBearing != null) {
              _mapController.rotate(-travelBearing); // Negative: up = direction of travel

              AppLogger.map('Navigation rotation', data: {
                'bearing': '${travelBearing.toStringAsFixed(1)}°',
                'breadcrumbs': _navigationTracker.breadcrumbCount,
              });
            } else if (_navigationTracker.lastBearing != null) {
              // Keep last bearing when stationary
              _mapController.rotate(-_navigationTracker.lastBearing!);
            }
          } else {
            // Exploration mode: simple auto-center, keep zoom and rotation
            _mapController.move(newGPSPosition, _mapController.camera.zoom);
          }

          AppLogger.location('GPS moved, auto-centering', data: {
            'distance': '${distance.toStringAsFixed(1)}m',
            'mode': navState.mode.name,
            'threshold': '${threshold}m',
            'autoZoom': 'enabled',
          });

          _loadAllMapDataWithBounds();
          _originalGPSReference = newGPSPosition;
        } else if (distance > threshold && !mapState.autoZoomEnabled) {
          AppLogger.location('GPS moved but auto-zoom disabled, skipping auto-center', data: {
            'distance': '${distance.toStringAsFixed(1)}m',
            'mode': navState.mode.name,
            'autoZoom': 'disabled',
          });
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

    // Add search result marker at long-click position with timestamp name
    final now = DateTime.now();
    final timestampName = 'Location ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    ref.read(searchProvider.notifier).setSelectedLocation(point.latitude, point.longitude, timestampName);

    _showContextMenu(tapPosition, point);
  }

  /// Show context menu for reporting hazard
  void _showContextMenu(TapPosition tapPosition, LatLng point) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final authUser = ref.read(authStateProvider).value;

    CommonDialog.show(
      context: context,
      title: CommonDialog.buildTitle(
        emoji: '📍',
        text: 'Location: ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (authUser != null)
            CommonDialog.buildListTileButton(
              leading: Icon(Icons.warning, color: Colors.orange[700]),
              title: const Text(
                'Report Hazard here',
                style: TextStyle(fontSize: CommonDialog.bodyFontSize),
              ),
              onTap: () {
                Navigator.pop(context);
                _showReportHazardDialog(point);
              },
            ),
          CommonDialog.buildListTileButton(
            leading: const Text('🚴‍♂️', style: TextStyle(fontSize: 22)),
            title: const Text(
              'Calculate a route to',
              style: TextStyle(fontSize: CommonDialog.bodyFontSize),
            ),
            onTap: () {
              Navigator.pop(context);
              _calculateRouteTo(point.latitude, point.longitude);
            },
          ),
          if (authUser != null)
            CommonDialog.buildListTileButton(
              leading: const Icon(Icons.star_border, color: Colors.amber),
              title: const Text(
                'Add to Favorites',
                style: TextStyle(fontSize: CommonDialog.bodyFontSize),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(authNotifierProvider.notifier).toggleFavorite(
                  'Location ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
                  point.latitude,
                  point.longitude,
                );
                // Auto-enable favorites visibility so user can see their new favorite
                ref.read(favoritesVisibilityProvider.notifier).state = true;
              },
            ),
        ],
      ),
    );
  }

  /// Show routing-only dialog (for search results)
  void _showRoutingDialog(TapPosition tapPosition, LatLng point) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final authUser = ref.read(authStateProvider).value;

    // Check if location is already favorited
    final userProfile = ref.read(userProfileProvider).value;
    final isFavorite = userProfile?.favoriteLocations.any(
      (loc) => loc.latitude == point.latitude && loc.longitude == point.longitude
    ) ?? false;

    // Get search result name
    final searchState = ref.read(searchProvider);
    final locationName = searchState.selectedLocation?.label ??
        'Location: ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';

    CommonDialog.show(
      context: context,
      title: CommonDialog.buildTitle(
        emoji: '🔍',
        text: locationName,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonDialog.buildListTileButton(
            leading: const Text('🚴‍♂️', style: TextStyle(fontSize: 22)),
            title: const Text(
              'Calculate a route to',
              style: TextStyle(fontSize: CommonDialog.bodyFontSize),
            ),
            onTap: () {
              Navigator.pop(context);
              _calculateRouteTo(point.latitude, point.longitude);
            },
          ),
          if (authUser != null)
            CommonDialog.buildListTileButton(
              leading: Icon(isFavorite ? Icons.star : Icons.star_border, color: Colors.amber),
              title: Text(
                isFavorite ? 'Favorited' : 'Add to Favorites',
                style: const TextStyle(fontSize: CommonDialog.bodyFontSize),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(authNotifierProvider.notifier).toggleFavorite(
                  locationName,
                  point.latitude,
                  point.longitude,
                );
                // Auto-enable favorites visibility so user can see their new favorite
                if (!isFavorite) {
                  ref.read(favoritesVisibilityProvider.notifier).state = true;
                }
              },
            ),
        ],
      ),
    );
  }

  /// Show dialog for favorites/destinations markers
  void _showFavoriteDestinationDetailsDialog(double latitude, double longitude, String name, bool isDestination) {
    CommonDialog.show(
      context: context,
      title: CommonDialog.buildTitle(
        emoji: isDestination ? '📍' : '⭐',
        text: name,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonDialog.buildCaptionText(
            'Coordinates: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
          ),
        ],
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Route To button with border
            CommonDialog.buildBorderedTextButton(
              label: 'ROUTE TO',
              icon: const Text('🚴‍♂️', style: TextStyle(fontSize: 18)),
              onPressed: () {
                Navigator.of(context).pop();
                _calculateRouteTo(latitude, longitude, destinationName: name);
              },
            ),
            const SizedBox(height: 8),
            // Remove button with border
            CommonDialog.buildBorderedTextButton(
              label: isDestination ? 'REMOVE FROM DESTINATIONS' : 'REMOVE FROM FAVORITES',
              icon: const Icon(Icons.delete, color: Colors.red, size: 18),
              textColor: Colors.red,
              onPressed: () {
                Navigator.of(context).pop();
                // Find and remove the destination or favorite
                final userProfile = ref.read(userProfileProvider).value;
                if (userProfile != null) {
                  if (isDestination) {
                    final index = userProfile.recentDestinations.indexWhere(
                      (dest) => dest.latitude == latitude && dest.longitude == longitude,
                    );
                    if (index != -1) {
                      ref.read(authNotifierProvider.notifier).deleteDestination(index);
                    }
                  } else {
                    final index = userProfile.favoriteLocations.indexWhere(
                      (fav) => fav.latitude == latitude && fav.longitude == longitude,
                    );
                    if (index != -1) {
                      ref.read(authNotifierProvider.notifier).deleteFavorite(index);
                    }
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
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
  Future<void> _calculateRouteTo(double destLat, double destLon, {String? destinationName}) async {
    // Try to get destination name from search result if not provided
    final name = destinationName ?? ref.read(searchProvider).selectedLocation?.label;

    await RouteCalculationHelper.calculateAndShowRoutes(
      context: context,
      ref: ref,
      destLat: destLat,
      destLon: destLon,
      destinationName: name,
      fitBoundsCallback: _fitRouteBounds,
      onRouteSelected: _displaySelectedRoute,
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
    _navigationTracker.addBreadcrumb(location);
  }

  /// Calculate travel direction from breadcrumbs (returns null if insufficient data)
  double? _calculateTravelDirection() {
    return _navigationTracker.calculateTravelDirection(smoothingRatio: 0.7);
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
      case MapLayerType.wike2D:
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

  /// Build destination marker (teardrop icon)
  Marker _buildDestinationMarker(double latitude, double longitude, String name) {
    final size = MarkerConfig.getRadiusForType(POIMarkerType.osmPOI) * 2;

    return Marker(
      point: LatLng(latitude, longitude),
      width: size,
      height: size,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {
          AppLogger.map('Destination marker tapped', data: {'name': name});
          _showFavoriteDestinationDetailsDialog(latitude, longitude, name, true);
        },
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.yellow.shade100.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.yellow.shade600,
              width: MarkerConfig.circleStrokeWidth,
            ),
          ),
          child: Text(
            '📍', // Teardrop/location icon
            style: TextStyle(fontSize: size * 0.5),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// Build favorite marker (star icon)
  Marker _buildFavoriteMarker(double latitude, double longitude, String name) {
    final size = MarkerConfig.getRadiusForType(POIMarkerType.osmPOI) * 2;

    return Marker(
      point: LatLng(latitude, longitude),
      width: size,
      height: size,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {
          AppLogger.map('Favorite marker tapped', data: {'name': name});
          _showFavoriteDestinationDetailsDialog(latitude, longitude, name, false);
        },
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.yellow.shade100.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.yellow.shade600,
              width: MarkerConfig.circleStrokeWidth,
            ),
          ),
          child: Text(
            '⭐', // Star icon
            style: TextStyle(fontSize: size * 0.5),
            textAlign: TextAlign.center,
          ),
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
      onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude, destinationName: poi.name),
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
      compact: false,
    );
  }


  @override
  Widget build(BuildContext context) {
    AppLogger.debug('Building widget', tag: 'MapScreen');

    final locationAsync = ref.watch(locationNotifierProvider);
    final poisAsync = ref.watch(osmPOIsNotifierProvider);
    final warningsAsync = ref.watch(communityWarningsBoundsNotifierProvider);
    final mapState = ref.watch(mapProvider);
    final compassHeading = kIsWeb ? null : ref.watch(compassNotifierProvider);

    // Listen for location changes to trigger POI loading
    ref.listen<AsyncValue<LocationData?>>(locationNotifierProvider, (previous, next) {
      next.whenData((location) {
        if (location != null) {
          // Only log if user has moved significantly (reduce log spam)
          bool shouldLog = false;
          if (_lastGPSPosition == null) {
            shouldLog = true; // First location update
          } else {
            final distance = Geolocator.distanceBetween(
              _lastGPSPosition!.latitude,
              _lastGPSPosition!.longitude,
              location.latitude,
              location.longitude,
            );
            shouldLog = distance > 10; // Only log if moved more than 10 meters
          }

          if (shouldLog) {
            AppLogger.location('Location changed via listener', data: {
              'lat': location.latitude.toStringAsFixed(6),
              'lng': location.longitude.toStringAsFixed(6),
            });
          }

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
          'heading': '$next°',
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
        final distance = next.totalDistanceRemaining;

        // Show arrival dialog
        showDialog(
          context: context,
          barrierColor: CommonDialog.barrierColor,
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
        final navProviderState = ref.read(navigationProvider);
        final isNavigationMode = navState.mode == NavMode.navigation;

        // Determine which position to show for the main marker
        // Use displayPosition (snapped) if available during navigation, otherwise use real GPS position
        final displayPos = navProviderState.isNavigating && navProviderState.displayPosition != null
            ? navProviderState.displayPosition!
            : LatLng(location.latitude, location.longitude);

        AppLogger.map('Adding user location marker', data: {
          'lat': location.latitude,
          'lng': location.longitude,
          'displayLat': displayPos.latitude,
          'displayLng': displayPos.longitude,
          'snapped': navProviderState.displayPosition != null,
          'navMode': navState.mode.name,
        });

        // Use navigation bearing if available (from route or GPS movement),
        // otherwise use compass/GPS heading as fallback
        double? heading;
        if (isNavigationMode && _navigationTracker.lastBearing != null) {
          // Use calculated navigation bearing (from route or breadcrumbs)
          heading = _navigationTracker.lastBearing;
        } else {
          // Fallback to compass heading on Native, or GPS heading
          heading = !kIsWeb && compassHeading != null ? compassHeading : location.heading;
        }
        final hasHeading = heading != null && heading >= 0;

        AppLogger.map('Marker heading', data: {
          'heading': heading?.toStringAsFixed(1),
          'hasHeading': hasHeading,
          'isNavigationMode': isNavigationMode,
          'source': isNavigationMode && _navigationTracker.lastBearing != null ? 'navigation' : 'gps/compass',
        });

        final userSize = MarkerConfig.getRadiusForType(POIMarkerType.userLocation) * 2;

        // Main marker (purple, shows snapped position during navigation)
        markers.add(
          Marker(
            point: displayPos,
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

        // Debug marker (grey, shows real GPS position when debug mode enabled)
        if (navProviderState.debugModeEnabled && navProviderState.isNavigating) {
          final realGpsPos = LatLng(location.latitude, location.longitude);
          markers.add(
            Marker(
              point: realGpsPos,
              width: userSize,
              height: userSize,
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: (isNavigationMode && hasHeading) ? (heading * math.pi / 180) : 0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer circle (grey)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey,
                          width: MarkerConfig.circleStrokeWidth,
                        ),
                      ),
                    ),
                    // Icon: Arrow in navigation mode, dot in exploration mode (grey)
                    if (isNavigationMode && hasHeading)
                      Icon(
                        Icons.navigation,
                        color: Colors.grey,
                        size: userSize * 0.6,
                      )
                    else
                      Icon(
                        Icons.circle,
                        color: Colors.grey,
                        size: userSize * 0.4,
                      ),
                  ],
                ),
              ),
            ),
          );
        }
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

        // Count only visible markers (filter by current map bounds)
        if (_isMapReady) {
          final bounds = _mapController.camera.visibleBounds;
          final visiblePOIs = filteredPOIs.where((poi) {
            return poi.latitude >= bounds.south &&
                   poi.latitude <= bounds.north &&
                   poi.longitude >= bounds.west &&
                   poi.longitude <= bounds.east;
          }).length;
          _displayedOSMPOICount = visiblePOIs;
        } else {
          _displayedOSMPOICount = filteredPOIs.length;
        }
      });
    } else {
      AppLogger.debug('OSM POIs hidden by toggle', tag: 'MAP');
    }

    // Add warning markers (only if showWarnings is true)
    if (mapState.showWarnings) {
      warningsAsync.whenData((allWarnings) {
        // Filter out deleted warnings
        final warnings = allWarnings.where((warning) => !warning.isDeleted).toList();

        AppLogger.map('Adding warning markers', data: {
          'total': allWarnings.length,
          'visible': warnings.length,
          'deleted': allWarnings.length - warnings.length,
        });
        markers.addAll(warnings.map((warning) => _buildWarningMarker(warning)));

        // Count only visible markers (filter by current map bounds)
        if (_isMapReady) {
          final bounds = _mapController.camera.visibleBounds;
          final visibleWarnings = warnings.where((warning) {
            return warning.latitude >= bounds.south &&
                   warning.latitude <= bounds.north &&
                   warning.longitude >= bounds.west &&
                   warning.longitude <= bounds.east;
          }).length;
          _displayedWarningCount = visibleWarnings;
        } else {
          _displayedWarningCount = warnings.length;
        }
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

    // Add favorites and destinations markers (only if toggle is enabled and user is logged in)
    final favoritesVisible = ref.watch(favoritesVisibilityProvider);
    final userProfile = ref.watch(userProfileProvider).value;
    if (favoritesVisible && userProfile != null) {
      // Add destination markers
      for (final destination in userProfile.recentDestinations) {
        markers.add(_buildDestinationMarker(
          destination.latitude,
          destination.longitude,
          destination.name,
        ));
      }
      AppLogger.debug('Added ${userProfile.recentDestinations.length} destination markers', tag: 'MAP');

      // Add favorite markers
      for (final favorite in userProfile.favoriteLocations) {
        markers.add(_buildFavoriteMarker(
          favorite.latitude,
          favorite.longitude,
          favorite.name,
        ));
      }
      AppLogger.debug('Added ${userProfile.favoriteLocations.length} favorite markers', tag: 'MAP');

      // Count only visible markers (filter by current map bounds)
      if (_isMapReady) {
        final bounds = _mapController.camera.visibleBounds;
        final visibleDestinations = userProfile.recentDestinations.where((dest) {
          return dest.latitude >= bounds.south &&
                 dest.latitude <= bounds.north &&
                 dest.longitude >= bounds.west &&
                 dest.longitude <= bounds.east;
        }).length;
        final visibleFavorites = userProfile.favoriteLocations.where((fav) {
          return fav.latitude >= bounds.south &&
                 fav.latitude <= bounds.north &&
                 fav.longitude >= bounds.west &&
                 fav.longitude <= bounds.east;
        }).length;
        _displayedFavoritesCount = visibleDestinations + visibleFavorites;
      } else {
        _displayedFavoritesCount = userProfile.recentDestinations.length + userProfile.favoriteLocations.length;
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
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch to full height
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                    child: const NavigationCard(),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: _buildMapAndControls(context, locationAsync, poisAsync, warningsAsync, mapState, markers, mapCenter),
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
                    children: _buildMapAndControls(context, locationAsync, poisAsync, warningsAsync, mapState, markers, mapCenter),
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
                    // Only use subdomains for tile providers that support it (not Mapbox)
                    subdomains: mapState.tileUrl.contains('mapbox.com') ? const [] : const ['a', 'b', 'c'],
                    // Set tile size to 512 for high-res Mapbox @2x tiles, otherwise 256
                    tileSize: mapState.tileUrl.contains('@2x') ? 512 : 256,
                    // Error handler for tile loading failures
                    errorTileCallback: (tile, error, stackTrace) {
                      AppLogger.error('Tile loading failed', tag: 'MAP', error: error, stackTrace: stackTrace, data: {
                        'tileUrl': mapState.tileUrl,
                        'errorMessage': error.toString(),
                      });
                    },
                  ),
                  // Preview routes layer (shown during route selection)
                  // Render in z-order: selected route last (on top)
                  if (searchState.previewFastestRoute != null && (searchState.previewSafestRoute != null || searchState.previewShortestRoute != null))
                    PolylineLayer(
                      polylines: _buildPreviewPolylinesInZOrder(
                        searchState.previewFastestRoute!,
                        searchState.previewSafestRoute,
                        searchState.previewShortestRoute,
                        searchState.selectedPreviewRouteIndex,
                      ),
                    ),
                  // Selected route polyline layer (below markers)
                  if (routePoints != null && routePoints.isNotEmpty && searchState.previewFastestRoute == null)
                    Consumer(
                      builder: (context, ref, _) {
                        final navState = ref.watch(navigationProvider);

                        // During navigation with surface data, render color-coded segments
                        if (navState.isNavigating && navState.activeRoute != null) {
                          final pathDetails = navState.activeRoute!.pathDetails;
                          final routePoints = navState.activeRoute!.points;

                          // Calculate current point index to determine traveled segments
                          int? currentPointIndex;
                          final currentPos = navState.currentPosition;
                          if (currentPos != null && routePoints.isNotEmpty) {
                            double minDistance = double.infinity;
                            int closestIndex = 0;

                            for (int i = 0; i < routePoints.length; i++) {
                              final routePoint = routePoints[i];
                              final distance = GeoUtils.calculateDistance(
                                currentPos.latitude,
                                currentPos.longitude,
                                routePoint.latitude,
                                routePoint.longitude,
                              );

                              if (distance < minDistance) {
                                minDistance = distance;
                                closestIndex = i;
                              }
                            }

                            currentPointIndex = closestIndex;
                          }

                          if (pathDetails != null && pathDetails.containsKey('surface')) {
                            // Has surface data - use color-coded segments
                            final segments = RouteSurfaceHelper.createSurfaceSegments(
                              routePoints,
                              pathDetails,
                            );

                            return PolylineLayer(
                              polylines: segments.asMap().entries.map((entry) {
                                final segment = entry.value;
                                final isTraveled = currentPointIndex != null &&
                                    segment.endIndex < currentPointIndex;

                                // Apply grey color and thinner width for traveled segments
                                final color = isTraveled
                                    ? Color(MapboxMarkerUtils.getTraveledSegmentColor())
                                    : segment.color;
                                final width = isTraveled ? 5.0 : 8.0;

                                return Polyline(
                                  points: segment.points,
                                  strokeWidth: width,
                                  color: color,
                                  borderStrokeWidth: 2.0,
                                  borderColor: Colors.white,
                                );
                              }).toList(),
                            );
                          } else {
                            // No surface data - create two polylines (traveled + remaining)
                            if (currentPointIndex == null || currentPointIndex == 0) {
                              // No traveled portion yet - show entire route in blue
                              return PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: routePoints,
                                    strokeWidth: 8.0,
                                    color: Colors.blue,
                                    borderStrokeWidth: 2.0,
                                    borderColor: Colors.white,
                                  ),
                                ],
                              );
                            } else {
                              // Split into traveled (gray) and remaining (blue)
                              final traveledPoints = routePoints.sublist(0, currentPointIndex + 1);
                              final remainingPoints = routePoints.sublist(currentPointIndex);

                              return PolylineLayer(
                                polylines: [
                                  // Traveled portion (gray, thinner)
                                  Polyline(
                                    points: traveledPoints,
                                    strokeWidth: 5.0,
                                    color: Color(MapboxMarkerUtils.getTraveledSegmentColor()),
                                    borderStrokeWidth: 2.0,
                                    borderColor: Colors.white,
                                  ),
                                  // Remaining portion (blue, normal width)
                                  Polyline(
                                    points: remainingPoints,
                                    strokeWidth: 8.0,
                                    color: Colors.blue,
                                    borderStrokeWidth: 2.0,
                                    borderColor: Colors.white,
                                  ),
                                ],
                              );
                            }
                          }
                        }

                        // Fallback: single color route
                        return PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              strokeWidth: 8.0,
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

          // Top-right controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 10,
            child: Column(
              children: [
                // POI toggles (separate from shared controls)
                Consumer(
                  builder: (context, ref, child) {
                    final navState = ref.watch(navigationProvider);
                    if (navState.isNavigating || !_isMapReady) return const SizedBox.shrink();

                    final currentZoom = _mapController.camera.zoom;
                    final togglesEnabled = currentZoom > 13.0;

                    return Column(
                      children: [
                        OSMPOISelectorButton(
                          count: _displayedOSMPOICount,
                          enabled: togglesEnabled,
                        ),
                        const SizedBox(height: 4),
                        MapToggleButton(
                          isActive: mapState.showWarnings,
                          icon: Icons.warning,
                          activeColor: Colors.orange,
                          count: _displayedWarningCount,
                          enabled: togglesEnabled,
                          onPressed: () {
                            AppLogger.map('Warning toggle pressed');
                            final wasOff = !mapState.showWarnings;
                            ref.read(mapProvider.notifier).toggleWarnings();
                            if (wasOff) _loadWarningsIfNeeded();
                          },
                          tooltip: 'Toggle Warnings',
                        ),
                        const SizedBox(height: 4),
                        Consumer(
                          builder: (context, ref, child) {
                            final authUser = ref.watch(authStateProvider).value;
                            if (authUser == null) return const SizedBox.shrink();

                            final favoritesVisible = ref.watch(favoritesVisibilityProvider);
                            return MapToggleButton(
                              isActive: favoritesVisible,
                              icon: Icons.star,
                              activeColor: Colors.yellow.shade600,
                              count: _displayedFavoritesCount,
                              enabled: true,
                              onPressed: () {
                                AppLogger.map('Favorites toggle pressed');
                                ref.read(favoritesVisibilityProvider.notifier).toggle();
                              },
                              tooltip: 'Toggle Favorites & Destinations',
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                // Shared controls (zoom, location, profile)
                TopRightControls(
                  onZoomIn: () {
                    AppLogger.map('Zoom in pressed');
                    final currentZoom = _mapController.camera.zoom;
                    final newZoom = currentZoom.floor() + 1.0;
                    _mapController.move(_mapController.camera.center, newZoom);
                    AppLogger.map('Zoom changed', data: {'from': currentZoom, 'to': newZoom});

                    // Auto-restore POI toggles when zooming above threshold
                    if (currentZoom <= 13.0 && newZoom > 13.0) {
                      ref.read(mapProvider.notifier).restoreSavedToggles();
                      AppLogger.map('Auto-restored POI toggles at zoom > 13');
                    }
                    setState(() {});
                  },
                  onZoomOut: () {
                    AppLogger.map('Zoom out pressed');
                    final currentZoom = _mapController.camera.zoom;
                    final newZoom = currentZoom.floor() - 1.0;
                    _mapController.move(_mapController.camera.center, newZoom);
                    AppLogger.map('Zoom changed', data: {'from': currentZoom, 'to': newZoom});

                    // Auto-save and disable POI toggles at zoom <= 13
                    if (currentZoom > 13.0 && newZoom <= 13.0) {
                      final mapState = ref.read(mapProvider);
                      // Only save and disable if any toggles are currently on
                      if (mapState.showOSMPOIs || mapState.showWarnings) {
                        ref.read(mapProvider.notifier).saveAndDisableToggles();
                        AppLogger.map('Auto-saved and disabled POI toggles at zoom <= 13');
                      }
                    }
                    setState(() {});
                  },
                  onCenterLocation: () {
                    AppLogger.map('My location button pressed');
                    final locationAsync = ref.read(locationNotifierProvider);
                    locationAsync.whenData((location) {
                      if (location != null) {
                        AppLogger.map('Centering on GPS location');
                        _mapController.move(LatLng(location.latitude, location.longitude), 15);
                        _loadAllMapDataWithBounds();
                      }
                    });
                  },
                  currentZoom: _isMapReady ? _mapController.camera.zoom : 13.0,
                  isZoomVisible: _isMapReady,
                ),
              ],
            ),
          ),

          // Bottom-left controls
          Positioned(
            bottom: 10,
            left: 10,
            child: BottomLeftControls(
              onAutoZoomToggle: () {
                final wasEnabled = ref.read(mapProvider).autoZoomEnabled;
                ref.read(mapProvider.notifier).toggleAutoZoom();
                AppLogger.map('Auto-zoom ${wasEnabled ? "disabled" : "enabled"} (2D)');

                // If we just enabled auto-zoom, immediately re-center on user position
                if (!wasEnabled) {
                  final location = ref.read(locationNotifierProvider).value;
                  if (location != null && _isMapReady) {
                    final newPosition = LatLng(location.latitude, location.longitude);
                    final logicalZoom = NavigationUtils.calculateNavigationZoom(location.speed);
                    final targetZoom = NavigationUtils.toFlutterMapZoom(logicalZoom);
                    _mapController.move(newPosition, targetZoom);
                    _originalGPSReference = newPosition;
                    AppLogger.map('Auto-zoom re-enabled, immediately re-centered on user');
                  }
                }
              },
              onCompassToggle: () {
                setState(() {
                  _compassRotationEnabled = !_compassRotationEnabled;
                  if (!_compassRotationEnabled) {
                    _mapController.rotate(0);
                    _lastBearing = null;
                  }
                });
                AppLogger.map('Compass rotation ${_compassRotationEnabled ? "enabled" : "disabled"} (2D)');
              },
              onReloadPOIs: () {
                AppLogger.map('Manual POI reload requested (2D)');
                _loadAllMapDataWithBounds(forceReload: true);
              },
              compassEnabled: _compassRotationEnabled,
            ),
          ),
          // Bottom-right controls
          Positioned(
            bottom: 10,
            right: 10,
            child: BottomRightControls(
              onNavigationEnded: () {
                setState(() {
                  _activeRoute = null;
                });
                _mapController.rotate(0.0);
              },
              onLayerPicker: _showLayerPicker,
              on3DSwitch: _open3DMap,
            ),
          ),

          // Search button (top-left, yellow) - hidden in navigation mode
          Consumer(
            builder: (context, ref, child) {
              final navState = ref.watch(navigationProvider);
              if (!_isMapReady || navState.isNavigating) return const SizedBox.shrink();

              return Positioned(
                top: MediaQuery.of(context).padding.top + 10,
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
              );
            },
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
              onResultTap: (lat, lon, label) {
                AppLogger.map('Search result tapped - navigating to location', data: {
                  'lat': lat,
                  'lon': lon,
                  'label': label,
                });
                // Set selected location to show marker with proper label
                ref.read(searchProvider.notifier).setSelectedLocation(lat, lon, label);

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
    ]; // End map and controls list
  }

  /// Get lighter color for traveled route segments (deprecated - use MapboxMarkerUtils.getTraveledSegmentColor)
  ///
  /// Blends color with white (50% original, 50% white) and reduces opacity to 50%
  @deprecated
  static Color _getLighterColor(Color color) {
    // Extract RGB components
    final r = color.red;
    final g = color.green;
    final b = color.blue;

    // Blend with white (50% original, 50% white)
    final lighterR = (r * 0.5 + 255 * 0.5).round();
    final lighterG = (g * 0.5 + 255 * 0.5).round();
    final lighterB = (b * 0.5 + 255 * 0.5).round();

    // Return with 50% opacity
    return Color.fromARGB(
      (color.alpha * 0.5).round(),
      lighterR,
      lighterG,
      lighterB,
    );
  }

  /// Build preview polylines in z-order (selected route on top)
  /// Routes: 0=car (red), 1=bike (green), 2=foot (blue)
  List<Polyline> _buildPreviewPolylinesInZOrder(
    List<LatLng> carRoute,
    List<LatLng>? bikeRoute,
    List<LatLng>? footRoute,
    int selectedIndex,
  ) {
    final polylines = <Polyline>[];

    // Determine rendering order: selected route last (drawn on top)
    final routesToRender = <int>[];
    for (int i = 0; i < 3; i++) {
      if (i != selectedIndex) {
        routesToRender.add(i);
      }
    }
    routesToRender.add(selectedIndex);

    // Build polylines in the determined order
    for (final routeIndex in routesToRender) {
      switch (routeIndex) {
        case 0: // Car route (red)
          polylines.add(Polyline(
            points: carRoute,
            strokeWidth: 8.0,
            color: Colors.red[700]!,
            borderStrokeWidth: 3.0,
            borderColor: Colors.white,
          ));
          break;
        case 1: // Bike route (green)
          if (bikeRoute != null) {
            polylines.add(Polyline(
              points: bikeRoute,
              strokeWidth: 8.0,
              color: Colors.green[700]!,
              borderStrokeWidth: 3.0,
              borderColor: Colors.white,
            ));
          }
          break;
        case 2: // Foot route (blue)
          if (footRoute != null) {
            polylines.add(Polyline(
              points: footRoute,
              strokeWidth: 8.0,
              color: Colors.blue[700]!,
              borderStrokeWidth: 3.0,
              borderColor: Colors.white,
            ));
          }
          break;
      }
    }

    return polylines;
  }
}
