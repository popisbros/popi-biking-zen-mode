import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;
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
import '../services/ios_navigation_service.dart';
import '../services/toast_service.dart';
import '../services/conditional_poi_loader.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/app_logger.dart';
import '../utils/geo_utils.dart';
import '../utils/navigation_utils.dart';
import '../utils/poi_dialog_handler.dart';
import '../utils/poi_utils.dart';
import '../utils/route_calculation_helper.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/navigation_card.dart';
import '../widgets/profile_button.dart';
import '../services/route_surface_helper.dart';
import '../widgets/navigation_controls.dart';
import '../widgets/arrival_dialog.dart';
import '../widgets/dialogs/poi_detail_dialog.dart';
import '../widgets/dialogs/warning_detail_dialog.dart';
import '../widgets/dialogs/route_selection_dialog.dart';
import '../widgets/dialogs/community_poi_detail_dialog.dart';
import '../widgets/map_toggle_button.dart';
import '../widgets/osm_poi_selector_button.dart';
import '../providers/debug_provider.dart';
import '../providers/navigation_provider.dart';
import 'map_screen.dart';
import 'community/poi_management_screen.dart';
import 'community/hazard_report_screen.dart';

/// Simplified Mapbox 3D Map Screen
/// This version works with Mapbox Maps Flutter 2.11.0 API
class MapboxMapScreenSimple extends ConsumerStatefulWidget {
  const MapboxMapScreenSimple({super.key});

  @override
  ConsumerState<MapboxMapScreenSimple> createState() => _MapboxMapScreenSimpleState();
}

class _MapboxMapScreenSimpleState extends ConsumerState<MapboxMapScreenSimple> {
  MapboxMap? _mapboxMap;
  bool _isMapReady = false;
  CameraOptions? _initialCamera;
  PointAnnotationManager? _pointAnnotationManager;
  Timer? _debounceTimer;
  DateTime? _lastPOILoadTime;
  Timer? _cameraCheckTimer;
  Point? _lastCameraCenter;
  double? _lastCameraZoom;

  // Navigation mode: GPS breadcrumb tracking for map rotation
  final List<_LocationBreadcrumb> _breadcrumbs = [];
  double? _lastNavigationBearing; // Smoothed bearing for navigation mode
  static const int _maxBreadcrumbs = 5;
  static const double _minBreadcrumbDistance = 5.0; // meters - responsive at cycling speeds
  static const Duration _breadcrumbMaxAge = Duration(seconds: 20); // 20s window for stable tracking

  // GPS auto-center tracking
  latlong.LatLng? _originalGPSReference;
  latlong.LatLng? _lastGPSPosition;

  // Active route for persistent navigation sheet
  RouteResult? _activeRoute;

  // Track last route point index to avoid unnecessary redraws
  int? _lastRoutePointIndex;

  // Track which route segments are currently marked as "traveled"
  final Set<int> _traveledSegmentIndices = {};

  // Cache segment metadata for efficient updates
  final List<_RouteSegmentMetadata> _routeSegments = [];

  // Pitch angle state
  double _currentPitch = 60.0; // Default pitch
  double? _pitchBeforeRouteCalculation; // Store pitch before showing route selection
  double? _pitchBeforeNavigation; // Store pitch before starting navigation
  static const List<double> _pitchOptions = [10.0, 35.0, 60.0, 85.0];

  // Zoom level state
  double _currentZoom = 15.0; // Default zoom

  // Smooth auto-zoom state
  DateTime? _lastZoomChangeTime;
  double? _currentAutoZoom;
  double? _targetAutoZoom;
  static const Duration _zoomChangeInterval = Duration(seconds: 3);
  static const double _minZoomChangeThreshold = 0.5;

  // Store POI data for tap handling
  final Map<String, OSMPOI> _osmPoiById = {};
  final Map<String, CyclingPOI> _communityPoiById = {};
  final Map<String, CommunityWarning> _warningById = {};
  final Map<String, ({double lat, double lng, String name})> _destinationsById = {};
  final Map<String, ({double lat, double lng, String name})> _favoritesById = {};

  @override
  void initState() {
    super.initState();
    AppLogger.ios('initState called', data: {'screen': 'Mapbox3D'});

    // Ensure location provider is initialized and permissions are requested
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.ios('PostFrameCallback - initializing location', data: {'screen': 'Mapbox3D'});
      // This will trigger location provider initialization and permission request
      ref.read(locationNotifierProvider);

      AppLogger.ios('Getting initial camera position', data: {'screen': 'Mapbox3D'});
      final locationAsync = ref.read(locationNotifierProvider);

      locationAsync.when(
        data: (location) {
          // Get camera settings from state (synced with 2D map)
          final mapState = ref.read(mapProvider);
          final hasBounds = mapState.southWest != null && mapState.northEast != null;

          if (hasBounds) {
            AppLogger.map('3D Map using saved bounds', data: {
              'sw': '${mapState.southWest!.latitude},${mapState.southWest!.longitude}',
              'ne': '${mapState.northEast!.latitude},${mapState.northEast!.longitude}'
            });
          } else {
            AppLogger.map('3D Map using default zoom', data: {'mapbox_zoom': mapState.zoom});
          }

          // Use center+zoom for initial camera (bounds will be applied in _onMapCreated)
          final camera = location != null
              ? CameraOptions(
                  center: Point(
                    coordinates: Position(
                      location.longitude,
                      location.latitude,
                    ),
                  ),
                  zoom: mapState.zoom, // Use zoom from state (stored in Mapbox scale)
                  pitch: _currentPitch, // Dynamic pitch angle
                  bearing: 0.0, // North up (exploration mode)
                )
              : _getDefaultCamera();

          if (mounted) {
            setState(() {
              _initialCamera = camera;
            });
            AppLogger.success('Initial camera set', tag: 'Mapbox3D', data: {
              'lat': location?.latitude,
              'lng': location?.longitude,
            });

            // Auto-center on GPS after map is ready (wait 1s for map initialization)
            if (location != null) {
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && _mapboxMap != null) {
                  AppLogger.ios('Auto-centering on GPS location', data: {'screen': 'Mapbox3D'});
                  _centerOnUserLocation();
                }
              });
            }
          }
        },
        loading: () {
          AppLogger.ios('Location still loading, using default camera', data: {'screen': 'Mapbox3D'});
          if (mounted) {
            setState(() {
              _initialCamera = _getDefaultCamera();
            });
          }
        },
        error: (_, __) {
          AppLogger.error('Location error, using default camera', tag: 'Mapbox3D');
          if (mounted) {
            setState(() {
              _initialCamera = _getDefaultCamera();
            });
          }
        },
      );
    });
  }

  CameraOptions _getDefaultCamera() {
    final mapState = ref.read(mapProvider);
    return CameraOptions(
      center: Point(
        coordinates: Position(5.826000, 40.643944), // Custom default location
      ),
      zoom: mapState.zoom, // Use zoom from state (synced with 2D map)
      pitch: _currentPitch, // Dynamic pitch angle
      bearing: 0.0, // North up (exploration mode)
    );
  }

  Future<void> _centerOnUserLocation() async {
    AppLogger.map('GPS button clicked');

    if (_mapboxMap == null) {
      AppLogger.error('Map not ready', tag: 'Mapbox3D');
      return;
    }

    try {
      AppLogger.map('Reading location from provider');

      final locationAsync = ref.read(locationNotifierProvider);

      locationAsync.when(
        data: (location) {
          if (location != null) {
            AppLogger.success('Got location', tag: 'Mapbox3D', data: {
              'lat': location.latitude,
              'lng': location.longitude,
            });

            _mapboxMap!.flyTo(
              CameraOptions(
                center: Point(
                  coordinates: Position(location.longitude, location.latitude),
                ),
                zoom: 16.0, // Mapbox zoom 16 = 2D zoom 15
                pitch: _currentPitch, // Dynamic pitch angle
              ),
              MapAnimationOptions(duration: 1000),
            );

            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                AppLogger.success('Centered on your location', tag: 'Mapbox3D');
              }
            });
          } else {
            AppLogger.error('Location is NULL', tag: 'Mapbox3D');
          }
        },
        loading: () {
          AppLogger.ios('Location still loading', data: {'screen': 'Mapbox3D'});
        },
        error: (error, _) {
          AppLogger.error('Location error', tag: 'Mapbox3D', error: error);
        },
      );
    } catch (e) {
      AppLogger.error('Exception', tag: 'Mapbox3D', error: e);
    }
  }

  void _showStylePicker() {
    final mapService = ref.read(mapServiceProvider);
    final currentStyle = ref.read(mapProvider).current3DStyle;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose 3D Map Style',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...MapboxStyleType.values.map((style) {
              return ListTile(
                dense: true,
                visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                leading: Icon(
                  _getStyleIcon(style),
                  color: currentStyle == style ? Colors.green : Colors.grey,
                ),
                title: Text(mapService.getStyleName(style), style: const TextStyle(fontSize: 12)),
                trailing: currentStyle == style
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  ref.read(mapProvider.notifier).change3DStyle(style);
                  final styleUri = mapService.getMapboxStyleUri(style);
                  await _mapboxMap?.loadStyleURI(styleUri);
                  // Re-add markers after style change
                  _pointAnnotationManager = await _mapboxMap?.annotations.createPointAnnotationManager();
                  _addMarkers();
                  Navigator.pop(context);
                  AppLogger.map('Style changed to ${mapService.getStyleName(style)}');
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showPitchPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Camera Pitch',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._pitchOptions.map((pitch) {
              return ListTile(
                dense: true,
                visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                leading: Icon(
                  Icons.height,
                  color: _currentPitch == pitch ? Colors.deepPurple : Colors.grey,
                ),
                title: Text('${pitch.toInt()}°', style: const TextStyle(fontSize: 12)),
                trailing: _currentPitch == pitch
                    ? const Icon(Icons.check, color: Colors.deepPurple)
                    : null,
                onTap: () async {
                  setState(() => _currentPitch = pitch);
                  await _mapboxMap?.setCamera(CameraOptions(pitch: pitch));
                  Navigator.pop(context);
                  AppLogger.map('Pitch changed to $pitch°');
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  IconData _getStyleIcon(MapboxStyleType style) {
    switch (style) {
      case MapboxStyleType.streets:
        return Icons.map;
      case MapboxStyleType.outdoors:
        return Icons.terrain;
      case MapboxStyleType.wike3D:
        return Icons.directions_bike;
    }
  }

  void _switchTo2DMap() async {
    AppLogger.map('Switching to 2D map');

    // Save current map bounds to state before switching
    final cameraBounds = await _mapboxMap?.getBounds();
    if (cameraBounds != null) {
      final bounds = cameraBounds.bounds;
      final southWest = latlong.LatLng(bounds.southwest.coordinates.lat.toDouble(), bounds.southwest.coordinates.lng.toDouble());
      final northEast = latlong.LatLng(bounds.northeast.coordinates.lat.toDouble(), bounds.northeast.coordinates.lng.toDouble());

      ref.read(mapProvider.notifier).updateBounds(southWest, northEast);
      AppLogger.map('Saved bounds for 2D map', data: {
        'sw': '${bounds.southwest.coordinates.lat.toStringAsFixed(4)},${bounds.southwest.coordinates.lng.toStringAsFixed(4)}',
        'ne': '${bounds.northeast.coordinates.lat.toStringAsFixed(4)},${bounds.northeast.coordinates.lng.toStringAsFixed(4)}'
      });
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const MapScreen(),
      ),
    );
  }

  /// Handle long press on map to show context menu
  Future<void> _onMapLongPress(Point coordinates) async {
    final lat = coordinates.coordinates.lat.toDouble();
    final lng = coordinates.coordinates.lng.toDouble();

    AppLogger.map('Map long-pressed', data: {
      'lat': lat,
      'lng': lng,
    });

    // Provide haptic feedback for mobile users
    HapticFeedback.mediumImpact();

    // Add search result marker at long-click position
    ref.read(searchProvider.notifier).setSelectedLocation(lat, lng, 'Long-click location');

    // Wait for marker to be added before showing dialog
    await _addMarkers();

    // Small delay to ensure map has settled
    await Future.delayed(const Duration(milliseconds: 100));

    _showContextMenu(coordinates);
  }

  /// Calculate dialog alignment based on marker position on screen
  /// Returns alignment and debug info as a map
  Future<Map<String, dynamic>> _calculateDialogAlignment(Point coordinates) async {
    if (_mapboxMap == null) {
      return {
        'alignment': const Alignment(0.0, -0.33),
        'screenY': 0.0,
        'screenHeight': 0.0,
        'normalizedY': 0.0,
        'inMiddleThird': false,
      };
    }

    try {
      // Get screen coordinate for the map point
      final screenCoordinate = await _mapboxMap!.pixelForCoordinate(coordinates);

      // Get screen size
      final size = MediaQuery.of(context).size;

      // Calculate normalized position (0.0 to 1.0)
      final normalizedY = screenCoordinate.y / size.height;
      final inMiddleThird = normalizedY >= 0.33 && normalizedY <= 0.67;

      // If marker is in middle third (0.33 to 0.67), show dialog at bottom
      Alignment alignment;
      if (inMiddleThird) {
        alignment = const Alignment(0.0, 0.6); // Position at bottom third
      } else {
        alignment = const Alignment(0.0, -0.33);
      }

      return {
        'alignment': alignment,
        'screenY': screenCoordinate.y,
        'screenHeight': size.height,
        'normalizedY': normalizedY,
        'inMiddleThird': inMiddleThird,
      };
    } catch (e) {
      AppLogger.warning('Failed to calculate dialog alignment: $e', tag: 'MAP');
      return {
        'alignment': const Alignment(0.0, -0.33),
        'screenY': 0.0,
        'screenHeight': 0.0,
        'normalizedY': 0.0,
        'inMiddleThird': false,
      };
    }
  }

  /// Show context menu for adding Community POI or reporting hazard
  Future<void> _showContextMenu(Point coordinates) async {
    final lat = coordinates.coordinates.lat.toDouble();
    final lng = coordinates.coordinates.lng.toDouble();
    final authUser = ref.read(authStateProvider).value;

    // Calculate smart dialog alignment based on marker position
    final alignmentData = await _calculateDialogAlignment(coordinates);
    final alignment = alignmentData['alignment'] as Alignment;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final inMiddleThird = alignmentData['inMiddleThird'] as bool;

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // Positioned dialog based on marker location
              Positioned(
                left: 20,
                right: 20,
                top: inMiddleThird ? MediaQuery.of(context).size.height * 0.60 : MediaQuery.of(context).size.height * 0.28,
                child: AlertDialog(
                  backgroundColor: Colors.white.withOpacity(0.6),
                  titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  title: const Text('Possible Actions for this Location', style: TextStyle(fontSize: 14)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        leading: Icon(Icons.add_location, color: Colors.green[700]),
                        title: const Text('Add Community here', style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          _showAddPOIDialog(lat, lng);
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        leading: Icon(Icons.warning, color: Colors.orange[700]),
                        title: const Text('Report Hazard here', style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          _showReportHazardDialog(lat, lng);
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        leading: const Text('🚴‍♂️', style: TextStyle(fontSize: 22)),
                        title: const Text('Calculate a route to', style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          _calculateRouteTo(lat, lng);
                        },
                      ),
                      if (authUser != null)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                          leading: const Icon(Icons.star_border, color: Colors.amber),
                          title: const Text('Add to Favorites', style: TextStyle(fontSize: 12)),
                          onTap: () {
                            Navigator.pop(context);
                            ref.read(authNotifierProvider.notifier).toggleFavorite(
                              'Location ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                              lat,
                              lng,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show routing-only dialog (for search results)
  Future<void> _showRoutingDialog(double lat, double lng) async {
    final coordinates = Point(coordinates: Position(lng, lat));
    final authUser = ref.read(authStateProvider).value;

    // Check if location is already favorited
    final userProfile = ref.read(userProfileProvider).value;
    final isFavorite = userProfile?.favoriteLocations.any(
      (loc) => loc.latitude == lat && loc.longitude == lng
    ) ?? false;

    // Calculate smart dialog alignment based on marker position
    final alignmentData = await _calculateDialogAlignment(coordinates);
    final alignment = alignmentData['alignment'] as Alignment;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final inMiddleThird = alignmentData['inMiddleThird'] as bool;

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // Positioned dialog based on marker location
              Positioned(
                left: 20,
                right: 20,
                top: inMiddleThird ? MediaQuery.of(context).size.height * 0.60 : MediaQuery.of(context).size.height * 0.28,
                child: AlertDialog(
                  backgroundColor: Colors.white.withOpacity(0.6),
                  titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  title: const Text('Possible Actions for this Location', style: TextStyle(fontSize: 14)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        leading: const Text('🚴‍♂️', style: TextStyle(fontSize: 22)),
                        title: const Text('Calculate a route to', style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          _calculateRouteTo(lat, lng);
                        },
                      ),
                      if (authUser != null)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                          leading: Icon(isFavorite ? Icons.star : Icons.star_border, color: Colors.amber),
                          title: Text(isFavorite ? 'Favorited' : 'Add to Favorites', style: const TextStyle(fontSize: 12)),
                          onTap: () {
                            Navigator.pop(context);
                            // Get the search result name if available
                            final searchState = ref.read(searchProvider);
                            final locationName = searchState.selectedLocation?.label ??
                                'Location ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
                            ref.read(authNotifierProvider.notifier).toggleFavorite(
                              locationName,
                              lat,
                              lng,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Navigate to Community POI management screen
  void _showAddPOIDialog(double latitude, double longitude) async {
    AppLogger.map('Opening Add POI screen', data: {
      'lat': latitude,
      'lng': longitude,
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => POIManagementScreenWithLocation(
          initialLatitude: latitude,
          initialLongitude: longitude,
        ),
      ),
    );

    AppLogger.map('Returned from POI screen, reloading data and refreshing markers');
    if (mounted && _isMapReady) {
      // Reload POI data from Firebase
      await _loadAllPOIData();
      // Refresh markers on map
      _addMarkers();
    }
  }

  /// Navigate to Hazard report screen
  void _showReportHazardDialog(double latitude, double longitude) async {
    AppLogger.map('Opening Report Hazard screen', data: {
      'lat': latitude,
      'lng': longitude,
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HazardReportScreenWithLocation(
          initialLatitude: latitude,
          initialLongitude: longitude,
        ),
      ),
    );

    AppLogger.map('Returned from Warning screen, reloading data and refreshing markers');
    if (mounted && _isMapReady) {
      // Reload warning data from Firebase
      await _loadAllPOIData();
      // Refresh markers on map
      _addMarkers();
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
      onPreRoutesCalculated: () async {
        // Store current pitch and set to 10° BEFORE zooming to routes
        // Also reset bearing to 0 (North up) for route preview
        _pitchBeforeRouteCalculation = _currentPitch;
        if (_mapboxMap != null) {
          await _mapboxMap!.easeTo(
            CameraOptions(pitch: 10.0, bearing: 0.0),
            MapAnimationOptions(duration: 500),
          );
          _currentPitch = 10.0;
        }
        // Refresh markers to show preview routes on map
        _addMarkers();
      },
      fitBoundsCallback: (points) async => await _fitRouteBounds(points),
      onRouteSelected: _displaySelectedRoute,
      onCancel: () {
        // Refresh markers to remove preview routes from map
        _addMarkers();
        // Restore previous pitch
        if (_pitchBeforeRouteCalculation != null) {
          _mapboxMap?.easeTo(
            CameraOptions(pitch: _pitchBeforeRouteCalculation!),
            MapAnimationOptions(duration: 500),
          );
          _currentPitch = _pitchBeforeRouteCalculation!;
          _pitchBeforeRouteCalculation = null;
        }
      },
      transparentBarrier: false,
    );
  }

  /// Display the selected route on the map
  Future<void> _displaySelectedRoute(RouteResult route) async {
    // Use helper for common route display logic
    RouteCalculationHelper.displaySelectedRoute(
      ref: ref,
      route: route,
      onCenterMap: () {}, // Camera positioning handled below for 3D specifics
    );

    // 3D-specific: Set active route state
    setState(() {
      _activeRoute = route;
    });

    // 3D-specific: Refresh map to show selected route and clear preview routes
    _addMarkers();

    // 3D-specific: Restore previous pitch (pitch was already set to 10° before dialog)
    if (_mapboxMap != null && _pitchBeforeRouteCalculation != null) {
      await _mapboxMap!.easeTo(
        CameraOptions(pitch: _pitchBeforeRouteCalculation!),
        MapAnimationOptions(duration: 500),
      );
      _currentPitch = _pitchBeforeRouteCalculation!;
      _pitchBeforeRouteCalculation = null;
    }
    AppLogger.success('Turn-by-turn navigation started', tag: 'NAVIGATION');

    // Store current pitch and set navigation pitch (35° for better forward view)
    _pitchBeforeNavigation = _currentPitch;
    const navigationPitch = 35.0;
    _currentPitch = navigationPitch;

    // Zoom to current GPS position for navigation view (close-up)
    final currentLocation = ref.read(locationNotifierProvider).value;
    if (currentLocation != null && _mapboxMap != null) {
      // Use fixed zoom 16.0 at navigation start (matches 2D map)
      // Dynamic zoom based on speed will take over as user moves
      final navigationZoom = 16.0;

      // Calculate initial bearing from current location to first route point
      double bearing = currentLocation.heading ?? 0.0; // Fallback to GPS heading
      if (route.points.isNotEmpty) {
        final userPosition = latlong.LatLng(currentLocation.latitude, currentLocation.longitude);
        final firstRoutePoint = route.points.first;
        final initialBearing = GeoUtils.calculateBearing(userPosition, firstRoutePoint);
        bearing = initialBearing;
        _lastNavigationBearing = initialBearing;

        AppLogger.debug('Initial route bearing calculated', tag: 'NAVIGATION', data: {
          'bearing': '${initialBearing.toStringAsFixed(1)}°',
        });
      }

      final screenHeight = MediaQuery.of(context).size.height;
      final offsetPixels = screenHeight / 4; // User at 3/4 from top

      await _mapboxMap!.easeTo(
        CameraOptions(
          center: Point(coordinates: Position(currentLocation.longitude, currentLocation.latitude)),
          zoom: navigationZoom,
          bearing: -bearing,
          pitch: navigationPitch,
          padding: MbxEdgeInsets(top: offsetPixels, left: 0, bottom: 0, right: 0),
        ),
        MapAnimationOptions(duration: 1000),
      );
      AppLogger.debug('Camera positioned for navigation', tag: 'NAVIGATION', data: {
        'pitch': '${navigationPitch}°',
      });
    }
  }

  /// Display route directly (without selection dialog) - legacy method
  Future<void> _displayRoute(List<latlong.LatLng> routePoints) async {
    // Store route in provider
    ref.read(searchProvider.notifier).setRoute(routePoints);

    // Toggle POIs: OSM OFF, Community OFF, Hazards ON
    ref.read(mapProvider.notifier).setPOIVisibility(
      showOSM: false,
      showCommunity: false,
      showHazards: true,
    );

    // Set camera pitch to 10°
    if (_mapboxMap != null) {
      await _mapboxMap!.easeTo(
        CameraOptions(pitch: 10.0),
        MapAnimationOptions(duration: 500),
      );
      _currentPitch = 10.0;
    }

    // Zoom map to fit the entire route
    await _fitRouteBounds(routePoints);

    AppLogger.success('Route displayed', tag: 'ROUTING', data: {
      'points': routePoints.length,
    });

    ToastService.info('Route calculated (${routePoints.length} points)');
  }

  /// Fit map bounds to show entire route
  Future<void> _fitRouteBounds(List<latlong.LatLng> routePoints) async {
    if (routePoints.isEmpty || _mapboxMap == null || !_isMapReady) {
      if (!_isMapReady) {
        AppLogger.warning('Cannot fit route bounds - map not ready yet', tag: 'ROUTING');
      }
      return;
    }

    try {
      // Convert route points to Mapbox coordinates
      final coordinates = routePoints.map((point) =>
        Point(coordinates: Position(point.longitude, point.latitude))
      ).toList();

      // Get screen size for padding calculation
      final size = MediaQuery.of(context).size;
      final padding = EdgeInsets.all(size.width * 0.1); // 10% padding

      // Use Mapbox's cameraForCoordinates to calculate optimal camera
      final cameraOptions = await _mapboxMap!.cameraForCoordinates(
        coordinates,
        MbxEdgeInsets(
          top: padding.top,
          left: padding.left,
          bottom: padding.bottom,
          right: padding.right,
        ),
        0.0, // bearing - North up for route preview
        _currentPitch, // pitch
      );

      // Fly to the calculated camera position
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: cameraOptions.center,
          zoom: cameraOptions.zoom,
          pitch: _currentPitch,
          bearing: 0.0, // North up for route preview
        ),
        MapAnimationOptions(duration: 1500),
      );

      AppLogger.debug('Map fitted to route bounds', tag: 'ROUTING', data: {
        'coordinates': coordinates.length,
        'zoom': cameraOptions.zoom,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fit route bounds', tag: 'ROUTING', error: e, stackTrace: stackTrace);
    }
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
    _stopNavigation();
    AppLogger.info('Navigation ended to search for parking', tag: 'PARKING');

    // Calculate 500m bounds around destination
    final radiusKm = 0.5; // 500 meters
    const earthRadiusKm = 6371.0;

    final latDelta = (radiusKm / earthRadiusKm) * (180 / 3.14159265359);
    final lonDelta = (radiusKm / earthRadiusKm) * (180 / 3.14159265359) /
                     (3.14159265359 * destination.latitude / 180).abs();

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
      latlong.LatLng(south, west),
      latlong.LatLng(north, east),
    );

    // Enable OSM POIs with bicycle parking type selected
    ref.read(mapProvider.notifier).setSelectedOSMPOITypes({'bike_parking'});

    // Zoom to show the parking search area
    if (_mapboxMap != null) {
      final coordinates = [
        Point(coordinates: Position(west, north)),
        Point(coordinates: Position(east, south)),
      ];

      try {
        final cameraOptions = await _mapboxMap!.cameraForCoordinates(
          coordinates,
          MbxEdgeInsets(top: 100, left: 50, bottom: 100, right: 50),
          null, // bearing
          null, // pitch
        );

        await _mapboxMap!.easeTo(
          CameraOptions(
            center: cameraOptions.center,
            zoom: cameraOptions.zoom,
            pitch: _currentPitch,
            bearing: 0.0, // North up
          ),
          MapAnimationOptions(duration: 1000),
        );

        AppLogger.success('Zoomed to parking search area', tag: 'PARKING', data: {
          'zoom': cameraOptions.zoom,
        });

        // Reload POIs to ensure parking markers appear
        await _loadAllPOIData();
        _addMarkers();

        // Show toast
        ToastService.info('Showing bicycle parking within 500m');
      } catch (e) {
        AppLogger.error('Failed to zoom to parking area', tag: 'PARKING', error: e);
      }
    }
  }

  /// Handle marker tap - show appropriate dialog based on marker type
  void _handleMarkerTap(double lat, double lng) {
    AppLogger.map('Handling marker tap', data: {'lat': lat, 'lng': lng});

    // Try all five types of IDs
    final osmId = 'osm_${lat}_$lng';
    final communityId = 'community_${lat}_$lng';
    final warningId = 'warning_${lat}_$lng';
    final destinationId = 'destination_${lat}_$lng';
    final favoriteId = 'favorite_${lat}_$lng';

    if (_osmPoiById.containsKey(osmId)) {
      _showPOIDetails(_osmPoiById[osmId]!);
    } else if (_communityPoiById.containsKey(communityId)) {
      _showCommunityPOIDetails(_communityPoiById[communityId]!);
    } else if (_warningById.containsKey(warningId)) {
      _showWarningDetails(_warningById[warningId]!);
    } else if (_destinationsById.containsKey(destinationId)) {
      final dest = _destinationsById[destinationId]!;
      _showFavoriteDestinationDetailsDialog(dest.lat, dest.lng, dest.name, true);
    } else if (_favoritesById.containsKey(favoriteId)) {
      final fav = _favoritesById[favoriteId]!;
      _showFavoriteDestinationDetailsDialog(fav.lat, fav.lng, fav.name, false);
    } else {
      AppLogger.warning('Tapped annotation not found in POI maps', tag: 'MAP', data: {
        'lat': lat,
        'lng': lng,
        'osmId': osmId,
        'communityId': communityId,
        'warningId': warningId,
        'destinationId': destinationId,
        'favoriteId': favoriteId,
      });
    }
  }

  /// Show OSM POI details dialog
  void _showPOIDetails(OSMPOI poi) {
    POIDialogHandler.showPOIDetails(
      context: context,
      poi: poi,
      onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude, destinationName: poi.name),
      compact: true,
      transparentBarrier: false,
    );
  }

  /// Show warning details dialog
  void _showWarningDetails(CommunityWarning warning) {
    POIDialogHandler.showWarningDetails(
      context: context,
      ref: ref,
      warning: warning,
      onDataChanged: () {
        if (mounted && _isMapReady) {
          _loadAllPOIData();
          _addMarkers();
        }
      },
      transparentBarrier: false,
      compact: true,
    );
  }

  /// Show Community POI details dialog
  void _showCommunityPOIDetails(CyclingPOI poi) {
    POIDialogHandler.showCommunityPOIDetails(
      context: context,
      ref: ref,
      poi: poi,
      onRouteTo: () => _calculateRouteTo(poi.latitude, poi.longitude, destinationName: poi.name),
      onDataChanged: () {
        if (mounted && _isMapReady) {
          _loadAllPOIData();
          _addMarkers();
        }
      },
      compact: true,
      transparentBarrier: false,
    );
  }

  /// Show dialog for favorites/destinations markers
  void _showFavoriteDestinationDetailsDialog(double latitude, double longitude, String name, bool isDestination) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Text(isDestination ? '📍' : '⭐', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Coordinates: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            Column(
              children: [
                // First row: Route To and Close
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _calculateRouteTo(latitude, longitude, destinationName: name);
                      },
                      icon: const Text('🚴‍♂️', style: TextStyle(fontSize: 18)),
                      label: const Text('ROUTE TO'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('CLOSE'),
                    ),
                  ],
                ),
                // Second row: Remove button (left-aligned)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
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
                    icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                    label: Text(
                      isDestination ? 'REMOVE FROM DESTINATIONS' : 'REMOVE FROM FAVORITES',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch location updates to keep camera centered
    final mapState = ref.watch(mapProvider);

    // Listen for POI data changes and refresh markers
    ref.listen<AsyncValue<List<dynamic>>>(osmPOIsNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        _addMarkers();
      }
    });

    ref.listen<AsyncValue<List<dynamic>>>(communityWarningsBoundsNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        _addMarkers();
      }
    });

    ref.listen<AsyncValue<List<dynamic>>>(cyclingPOIsBoundsNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        _addMarkers();
      }
    });

    // Listen for favorites visibility changes and refresh markers
    ref.listen<bool>(favoritesVisibilityProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        _addMarkers();
      }
    });

    // Listen for user profile changes (destinations/favorites added/removed) and refresh markers
    ref.listen<AsyncValue<dynamic>>(userProfileProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        _addMarkers();
      }
    });

    // Listen for map state changes (toggle buttons) and refresh markers INSTANTLY
    ref.listen<MapState>(mapProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        // Check if visibility toggles changed OR if selected types changed
        // Type changes trigger marker refresh to filter client-side (no API reload)
        if (previous?.showOSMPOIs != next.showOSMPOIs ||
            previous?.showPOIs != next.showPOIs ||
            previous?.showWarnings != next.showWarnings ||
            previous?.selectedOSMPOITypes != next.selectedOSMPOITypes) {
          _addMarkers(); // This is already instant - no delay, filters client-side
        }

        // Only reload POI data from API when first enabled
        final osmJustEnabled = (previous?.showOSMPOIs ?? false) == false && next.showOSMPOIs;
        if (osmJustEnabled) {
          AppLogger.map('OSM POIs enabled, loading data');
          _loadAllPOIData();
        }
      }
    });

    // Listen for compass changes to rotate the map (with toggle + threshold)
    // Compass listener removed - navigation mode uses GPS-based rotation instead

    // Listen for location changes to update user marker
    ref.listen(locationNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        next.whenData((location) {
          if (location != null) {
            _handleGPSLocationChange(location);
          } else {
            AppLogger.warning('Location is null', tag: 'MAP');
          }
        });
      } else {
        AppLogger.warning('Map not ready or annotation manager null', tag: 'MAP');
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

    // Use cached initial camera or default
    final initialCamera = _initialCamera ?? _getDefaultCamera();

    // Watch navigation state to determine layout
    final navState = ref.watch(navigationProvider);
    final isNavigating = navState.isNavigating;

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
                    children: _buildMapAndControls(context, mapState),
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
                    children: _buildMapAndControls(context, mapState),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  /// Build map and controls (reused in both orientations)
  List<Widget> _buildMapAndControls(BuildContext context, MapState mapState) {
    return [
      // Mapbox Map Widget (Simplified) with long-press gesture
      GestureDetector(
            onLongPressStart: (details) async {
              if (!_isMapReady || _mapboxMap == null) return;

              // Convert screen coordinates to geographic coordinates
              try {
                final screenCoordinate = ScreenCoordinate(
                  x: details.localPosition.dx,
                  y: details.localPosition.dy,
                );
                final point = await _mapboxMap!.coordinateForPixel(screenCoordinate);
                _onMapLongPress(point);
              } catch (e) {
                AppLogger.error('Failed to convert coordinates', error: e);
              }
            },
            child: MapWidget(
              key: const ValueKey("mapboxWidgetSimple"),
              cameraOptions: _initialCamera ?? _getDefaultCamera(),
              styleUri: mapState.mapboxStyleUri,
              onMapCreated: _onMapCreated,
            ),
          ),

          // Loading indicator
          if (!_isMapReady)
            Container(
              color: AppColors.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.mossGreen,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading 3D Map...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),

          // Simple controls (only show when map is ready)
          if (_isMapReady) ...[
            // Toggle buttons and zoom controls on the right side
            Positioned(
              top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
              right: 10,
              child: Column(
                children: [
                  // Check zoom level - disable toggles if zoom <= 12
                  Builder(
                    builder: (context) {
                      final togglesEnabled = _currentZoom > 12.0;

                      return Column(
                        children: [
                          // OSM POI selector (multi-choice dropdown)
                          OSMPOISelectorButton(
                            count: ref.watch(osmPOIsNotifierProvider).value != null
                                ? POIUtils.filterPOIsByType(
                                    ref.watch(osmPOIsNotifierProvider).value!.cast<OSMPOI>(),
                                    mapState.selectedOSMPOITypes,
                                  ).length
                                : 0,
                            enabled: togglesEnabled,
                          ),
                          const SizedBox(height: 8),
                          // Community POI toggle (hidden in navigation mode)
                          Consumer(
                            builder: (context, ref, child) {
                              final navState = ref.watch(navigationProvider);
                              if (navState.isNavigating) return const SizedBox.shrink();

                              return Column(
                                children: [
                                  MapToggleButton(
                                    isActive: mapState.showPOIs,
                                    icon: Icons.location_on,
                                    activeColor: Colors.green,
                                    count: ref.watch(cyclingPOIsBoundsNotifierProvider).value?.length ?? 0,
                                    enabled: togglesEnabled,
                                    onPressed: () {
                                      AppLogger.map('Community POI toggle pressed');
                                      final wasOff = !mapState.showPOIs;
                                      ref.read(mapProvider.notifier).togglePOIs();
                                      if (wasOff) {
                                        _loadCommunityPOIsIfNeeded();
                                      }
                                    },
                                    tooltip: 'Toggle Community POIs',
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              );
                            },
                          ),
                          // Warning toggle
                          MapToggleButton(
                            isActive: mapState.showWarnings,
                            icon: Icons.warning,
                            activeColor: Colors.orange,
                            count: ref.watch(communityWarningsBoundsNotifierProvider).value?.length ?? 0,
                            enabled: togglesEnabled,
                            onPressed: () {
                              AppLogger.map('Warning toggle pressed');
                              final wasOff = !mapState.showWarnings;
                              ref.read(mapProvider.notifier).toggleWarnings();
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
                  // Favorites and destinations toggle (hidden in navigation mode or when user not logged in)
                  Consumer(
                    builder: (context, ref, child) {
                      final navState = ref.watch(navigationProvider);
                      final authUser = ref.watch(authStateProvider).value;

                      // Hide if in navigation mode or user not logged in
                      if (navState.isNavigating || authUser == null) {
                        return const SizedBox.shrink();
                      }

                      final favoritesVisible = ref.watch(favoritesVisibilityProvider);
                      final userProfile = ref.watch(userProfileProvider).value;
                      final destinationsCount = userProfile?.recentDestinations.length ?? 0;
                      final favoritesCount = userProfile?.favoriteLocations.length ?? 0;
                      final totalCount = destinationsCount + favoritesCount;

                      return Column(
                        children: [
                          const SizedBox(height: 8),
                          MapToggleButton(
                            isActive: favoritesVisible,
                            icon: Icons.star,
                            activeColor: Colors.yellow.shade700,
                            count: totalCount,
                            enabled: true, // Always enabled (not zoom-dependent)
                            onPressed: () {
                              AppLogger.map('Favorites/destinations toggle pressed');
                              ref.read(favoritesVisibilityProvider.notifier).toggle();
                            },
                            tooltip: 'Toggle Favorites & Destinations',
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                  // Zoom in
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'zoom_in_3d',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    onPressed: () async {
                      final currentZoom = await _mapboxMap?.getCameraState().then((state) => state.zoom);
                      if (currentZoom != null) {
                        // Use floor to get integer zoom: 17.6 -> 18
                        final newZoom = currentZoom.floor() + 1.0;
                        await _mapboxMap?.setCamera(CameraOptions(
                          zoom: newZoom,
                          pitch: _currentPitch, // Maintain pitch angle
                        ));
                        setState(() {
                          _currentZoom = newZoom;
                        });
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 2),

                  // Zoom level display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _currentZoom.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),

                  // Zoom out
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'zoom_out_3d',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    onPressed: () async {
                      final currentZoom = await _mapboxMap?.getCameraState().then((state) => state.zoom);
                      if (currentZoom != null) {
                        // Use floor to get integer zoom: 17.6 -> 17
                        final newZoom = currentZoom.floor() - 1.0;
                        await _mapboxMap?.setCamera(CameraOptions(
                          zoom: newZoom,
                          pitch: _currentPitch, // Maintain pitch angle
                        ));

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

                        setState(() {
                          _currentZoom = newZoom;
                        });
                      }
                    },
                    child: const Icon(Icons.remove),
                  ),
                  const SizedBox(height: 8),

                  // Profile button
                  const ProfileButton(),
                ],
              ),
            ),

            // Bottom-left controls: compass, center, reload
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
                        heroTag: 'auto_zoom_toggle_3d',
                        onPressed: () {
                          ref.read(mapProvider.notifier).toggleAutoZoom();
                          AppLogger.map('Auto-zoom ${mapState.autoZoomEnabled ? "disabled" : "enabled"} (3D)');
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
                  // GPS center button
                  FloatingActionButton(
                    mini: true, // Match zoom button size
                    heroTag: 'gps_center_button_3d',
                    onPressed: _centerOnUserLocation,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.urbanBlue,
                    tooltip: 'Center on Location',
                    child: const Icon(Icons.my_location),
                  ),
                  // Reload POIs button (hidden in navigation mode)
                  Consumer(
                    builder: (context, ref, child) {
                      final navState = ref.watch(navigationProvider);
                      if (navState.isNavigating) return const SizedBox.shrink();

                      return Column(
                        children: [
                          const SizedBox(height: 8),
                          FloatingActionButton(
                            mini: true, // Match zoom button size
                            heroTag: 'reload_pois_button',
                            onPressed: () async {
                              AppLogger.map('Manual POI reload requested');
                              await _loadAllPOIData();
                              _addMarkers();
                              _lastPOILoadTime = DateTime.now();
                            },
                            backgroundColor: Colors.orange,
                            tooltip: 'Reload POIs',
                            child: const Icon(Icons.refresh),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                  // Debug toggle button
                  Builder(
                    builder: (context) {
                      final debugState = ref.watch(debugProvider);
                      return FloatingActionButton(
                        mini: true,
                        heroTag: 'debug_toggle_3d',
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
                    onNavigationEnded: () async {
                      AppLogger.debug('Navigation ended - starting cleanup', tag: 'NAVIGATION');

                      setState(() {
                        _activeRoute = null;
                      });

                      // Stop turn-by-turn navigation
                      ref.read(navigationProvider.notifier).stopNavigation();
                      AppLogger.debug('Stopped turn-by-turn navigation', tag: 'NAVIGATION');

                      // Stop route navigation mode
                      ref.read(navigationModeProvider.notifier).stopRouteNavigation();
                      AppLogger.debug('Stopped route navigation mode', tag: 'NAVIGATION');

                      // Clear route from search provider to remove from map
                      ref.read(searchProvider.notifier).clearRoute();
                      AppLogger.debug('Cleared route from search provider', tag: 'NAVIGATION');

                      // Log search provider state after clearing
                      final searchState = ref.read(searchProvider);
                      AppLogger.debug('Search provider state after clearRoute', tag: 'NAVIGATION', data: {
                        'hasRoutePoints': searchState.routePoints != null && searchState.routePoints!.isNotEmpty,
                        'routePointsCount': searchState.routePoints?.length ?? 0,
                        'hasPreviewRoutes': searchState.previewFastestRoute != null,
                      });

                      // Refresh markers to remove route polyline
                      _addMarkers();
                      AppLogger.debug('Refreshed markers after navigation ended', tag: 'NAVIGATION');

                      // Restore pitch and reset bearing to North
                      if (_mapboxMap != null && _pitchBeforeNavigation != null) {
                        await _mapboxMap!.easeTo(
                          CameraOptions(
                            pitch: _pitchBeforeNavigation!,
                            bearing: 0.0, // Reset to North up (exploration mode)
                          ),
                          MapAnimationOptions(duration: 500),
                        );
                        _currentPitch = _pitchBeforeNavigation!;
                        AppLogger.debug('Restored pitch and reset bearing after navigation', tag: 'NAVIGATION', data: {
                          'pitch': '${_pitchBeforeNavigation!}°',
                          'bearing': '0° (North)',
                        });
                        _pitchBeforeNavigation = null;
                      }

                      AppLogger.success('Navigation ended, route cleared', tag: 'NAVIGATION');
                    },
                  ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom-right controls: tiles selector, pitch selector, 2D/3D switch (hidden in navigation mode)
            Consumer(
              builder: (context, ref, child) {
                final navState = ref.watch(navigationProvider);
                if (navState.isNavigating) return const SizedBox.shrink();

                return Positioned(
                  bottom: kIsWeb ? 10 : 30,
                  right: 10,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Style picker button (tiles selector)
                      FloatingActionButton(
                        mini: true, // Match zoom button size
                        heroTag: 'style_picker_button',
                        onPressed: _showStylePicker,
                        backgroundColor: Colors.blue,
                        tooltip: 'Change Map Style',
                        child: const Icon(Icons.layers),
                      ),
                      const SizedBox(height: 8),
                      // Pitch selector button
                      FloatingActionButton(
                        mini: true, // Match zoom button size
                        heroTag: 'pitch_selector_button',
                        onPressed: _showPitchPicker,
                        backgroundColor: Colors.deepPurple,
                        tooltip: 'Change Pitch: ${_currentPitch.toInt()}°',
                        child: Text('${_currentPitch.toInt()}°', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      // Switch to 2D button
                      FloatingActionButton(
                        mini: true, // Match zoom button size
                        heroTag: 'switch_to_2d_button',
                        onPressed: _switchTo2DMap,
                        backgroundColor: Colors.green,
                        tooltip: 'Switch to 2D Map',
                        child: const Icon(Icons.map),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],

          // Search button (top-left, yellow) - rendered on top
          if (_isMapReady)
            Positioned(
              top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
              left: 10,
              child: FloatingActionButton(
                mini: true,
                heroTag: 'search_button_3d',
                backgroundColor: const Color(0xFFFFEB3B), // Yellow
                foregroundColor: Colors.black87,
                onPressed: () {
                  AppLogger.map('Search button pressed (3D)');
                  ref.read(searchProvider.notifier).toggleSearchBar();
                },
                tooltip: 'Search',
                child: const Icon(Icons.search),
              ),
            ),

          // Search bar widget (slides down from top) - rendered on top of everything
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SearchBarWidget(
              mapCenter: latlong.LatLng(
                (_lastCameraCenter?.coordinates.lat ?? 0.0).toDouble(),
                (_lastCameraCenter?.coordinates.lng ?? 0.0).toDouble(),
              ),
              onResultTap: (lat, lon, label) async {
                AppLogger.map('Search result tapped - navigating to location', data: {
                  'lat': lat,
                  'lon': lon,
                  'label': label,
                });
                // Set selected location to show marker with proper label
                ref.read(searchProvider.notifier).setSelectedLocation(lat, lon, label);

                if (_mapboxMap != null) {
                  await _mapboxMap!.flyTo(
                    CameraOptions(
                      center: Point(coordinates: Position(lon, lat)),
                      zoom: 16.0,
                      pitch: _currentPitch,
                    ),
                    MapAnimationOptions(duration: 1000),
                  );
                  // Reload POIs after navigation
                  await _loadAllPOIData();
                  _addMarkers();

                  // Show routing-only dialog
                  _showRoutingDialog(lat, lon);
                }
              },
            ),
          ),

      // Route navigation sheet (persistent bottom sheet, non-modal)
      // Hidden when turn-by-turn navigation is active (new NavigationCard is used instead)

      // Debug overlay - on top of everything
      const DebugOverlay(),
    ]; // End map and controls list
  }

  /// Called when the Mapbox map is created and ready
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    AppLogger.map('Mapbox map created');

    // Initialize current zoom from camera
    final cameraState = await mapboxMap.getCameraState();
    setState(() {
      _isMapReady = true;
      _currentZoom = cameraState.zoom;
    });

    // Disable pitch gestures to lock the 3D angle at 70°
    try {
      await mapboxMap.gestures.updateSettings(GesturesSettings(
        pitchEnabled: false, // Lock pitch - user cannot tilt the map
      ));
      AppLogger.success('Pitch gestures disabled - locked at 80°', tag: 'MAP');
    } catch (e) {
      AppLogger.error('Failed to disable pitch gestures', error: e);
    }

    // Enable built-in location component with default 2D puck
    try {
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true, // Show direction arrow with bearing
        pulsingEnabled: false, // Disable pulsing for cleaner look
      ));
      AppLogger.success('Default location puck with bearing enabled', tag: 'MAP');
    } catch (e) {
      AppLogger.error('Failed to enable 3D location component', error: e);
    }

    // Initialize annotation managers
    // All markers now use PointAnnotation with emoji icons
    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    AppLogger.success('Point annotation manager created', tag: 'MAP');

    // Add click listener for tap handling
    _pointAnnotationManager!.addOnPointAnnotationClickListener(
      _OnPointClickListener(onTap: _handleMarkerTap),
    );
    AppLogger.success('Click listener added for point annotations', tag: 'MAP');

    // Center on user location or fit to saved bounds, then load POIs
    final locationState = ref.read(locationNotifierProvider);
    final mapState = ref.read(mapProvider);
    final hasBounds = mapState.southWest != null && mapState.northEast != null;
    bool hasCentered = false;

    if (hasBounds) {
      // Use saved bounds from 2D map
      AppLogger.map('Fitting 3D map to saved bounds');

      // Create coordinate bounds from saved state
      final coordinateBounds = CoordinateBounds(
        southwest: Point(coordinates: Position(
          mapState.southWest!.longitude,
          mapState.southWest!.latitude,
        )),
        northeast: Point(coordinates: Position(
          mapState.northEast!.longitude,
          mapState.northEast!.latitude,
        )),
        infiniteBounds: false,
      );

      // Calculate camera for bounds, then add pitch
      final boundsCamera = await mapboxMap.cameraForCoordinateBounds(
        coordinateBounds,
        MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        null, // bearing
        _currentPitch, // pitch
        null, // maxZoom
        null, // offset
      );

      // Apply the camera with animation
      await mapboxMap.flyTo(boundsCamera, MapAnimationOptions(duration: 1000));
      hasCentered = true;

      await Future.delayed(const Duration(milliseconds: 500));
      await _loadAllPOIData();
      _lastPOILoadTime = DateTime.now();
      _addMarkers();
    } else {
      locationState.whenData((location) async {
        if (location != null && mounted) {
          AppLogger.map('Centering map on user location at startup');
          await mapboxMap.flyTo(
            CameraOptions(
              center: Point(
                coordinates: Position(location.longitude, location.latitude),
              ),
              zoom: 16.0, // Mapbox zoom 16 = 2D zoom 15
              pitch: _currentPitch,
            ),
            MapAnimationOptions(duration: 1000),
          );
          hasCentered = true;

          // Wait a bit for camera to settle, then load POIs
          await Future.delayed(const Duration(milliseconds: 500));

          AppLogger.map('Loading POIs after centering on user location');
          await _loadAllPOIData();
          _lastPOILoadTime = DateTime.now();
          _addMarkers();
        }
      });
    }

    // If no location available, load POIs immediately at default position
    if (!hasCentered) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!hasCentered && mounted) {
        AppLogger.map('Loading POIs at default location (no GPS)');
        await _loadAllPOIData();
        _lastPOILoadTime = DateTime.now();
        _addMarkers();
      }
    }

    // Get initial camera state (with error handling)
    try {
      final initialState = await mapboxMap.getCameraState();
      _lastCameraCenter = initialState.center;
      _lastCameraZoom = initialState.zoom;
    } catch (e) {
      AppLogger.warning('Could not get initial camera state: $e', tag: 'MAP');
    }

    // Start periodic camera check to detect map movement
    _startCameraMonitoring();

    // Delayed GPS centering (retry after 2 seconds in case first attempt failed)
    Future.delayed(const Duration(seconds: 2), () {
      final locationState = ref.read(locationNotifierProvider);
      locationState.whenData((location) {
        if (location != null && mounted && _mapboxMap != null) {
          AppLogger.map('Delayed GPS centering (retry)');
          _mapboxMap!.flyTo(
            CameraOptions(
              center: Point(
                coordinates: Position(location.longitude, location.latitude),
              ),
              zoom: 16.0, // Mapbox zoom 16 = 2D zoom 15
              pitch: _currentPitch,
            ),
            MapAnimationOptions(duration: 1000),
          );
        }
      });
    });

    AppLogger.success('Mapbox map ready with camera monitoring', tag: 'MAP');
  }

  /// Load all POI data (OSM POIs, Community POIs, Warnings)
  Future<void> _loadAllPOIData() async {
    AppLogger.separator('Loading POI Data for 3D Map');

    try {
      // Get current camera position for bounds
      final cameraState = await _mapboxMap?.getCameraState();
      if (cameraState == null) {
        AppLogger.warning('Camera state not available, using default bounds', tag: 'MAP');
        return;
      }

      // Get actual visible coordinate bounds from camera
      final coordinateBounds = await _mapboxMap?.coordinateBoundsForCamera(
        CameraOptions(
          center: cameraState.center,
          zoom: cameraState.zoom,
          pitch: cameraState.pitch,
          bearing: cameraState.bearing,
        )
      );

      if (coordinateBounds == null) {
        AppLogger.warning('Could not calculate coordinate bounds', tag: 'MAP');
        return;
      }

      // Extract bounds from CoordinateBounds
      final south = coordinateBounds.southwest.coordinates.lat.toDouble();
      final west = coordinateBounds.southwest.coordinates.lng.toDouble();
      final north = coordinateBounds.northeast.coordinates.lat.toDouble();
      final east = coordinateBounds.northeast.coordinates.lng.toDouble();

      // Calculate extended bounds (2x in each direction, same as 2D map)
      final latDiff = north - south;
      final lngDiff = east - west;
      final extendedSouth = south - latDiff;
      final extendedNorth = north + latDiff;
      final extendedWest = west - lngDiff;
      final extendedEast = east + lngDiff;

      AppLogger.map('Loading POIs for extended bounds', data: {
        'visible_S': south.toStringAsFixed(4),
        'visible_N': north.toStringAsFixed(4),
        'visible_W': west.toStringAsFixed(4),
        'visible_E': east.toStringAsFixed(4),
        'extended_S': extendedSouth.toStringAsFixed(4),
        'extended_N': extendedNorth.toStringAsFixed(4),
        'extended_W': extendedWest.toStringAsFixed(4),
        'extended_E': extendedEast.toStringAsFixed(4),
        'zoom': cameraState.zoom.toStringAsFixed(1),
      });

      final bounds = BoundingBox(
        south: extendedSouth,
        west: extendedWest,
        north: extendedNorth,
        east: extendedEast,
      );

      final mapState = ref.read(mapProvider);
      final loadTypes = <String>[];

      // Only load OSM POIs if toggle is ON
      if (mapState.showOSMPOIs) {
        final osmNotifier = ref.read(osmPOIsNotifierProvider.notifier);
        await osmNotifier.loadPOIsWithBounds(bounds);
        loadTypes.add('OSM POIs');
      }

      // Only load Community POIs if toggle is ON
      if (mapState.showPOIs) {
        final communityPOIsNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
        await communityPOIsNotifier.loadPOIsWithBounds(bounds);
        loadTypes.add('Community POIs');
      }

      // Only load Community Warnings if toggle is ON
      if (mapState.showWarnings) {
        final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
        await warningsNotifier.loadWarningsWithBounds(bounds);
        loadTypes.add('Warnings');
      }

      AppLogger.success('POI data loaded', tag: 'MAP', data: {
        'types': loadTypes.isEmpty ? 'None (all toggles OFF)' : loadTypes.join(', '),
      });
    } catch (e) {
      AppLogger.error('Failed to load POI data', error: e);
    }

    AppLogger.separator();
  }

  /// Load OSM POIs only if needed (cache empty)
  void _loadOSMPOIsIfNeeded() async {
    try {
      final cameraState = await _mapboxMap?.getCameraState();
      if (cameraState == null) return;

      final coordinateBounds = await _mapboxMap?.coordinateBoundsForCamera(
        CameraOptions(
          center: cameraState.center,
          zoom: cameraState.zoom,
          pitch: cameraState.pitch,
          bearing: cameraState.bearing,
        )
      );

      if (coordinateBounds == null) return;

      final south = coordinateBounds.southwest.coordinates.lat.toDouble();
      final west = coordinateBounds.southwest.coordinates.lng.toDouble();
      final north = coordinateBounds.northeast.coordinates.lat.toDouble();
      final east = coordinateBounds.northeast.coordinates.lng.toDouble();

      final latDiff = north - south;
      final lngDiff = east - west;

      final bounds = BoundingBox(
        south: south - latDiff,
        west: west - lngDiff,
        north: north + latDiff,
        east: east + lngDiff,
      );

      await ConditionalPOILoader.loadOSMPOIsIfNeeded(
        ref: ref,
        extendedBounds: bounds,
        onComplete: _addMarkers,
      );
    } catch (e) {
      AppLogger.error('Failed to load OSM POIs', error: e);
    }
  }

  /// Load Community POIs only if needed (cache empty)
  void _loadCommunityPOIsIfNeeded() async {
    try {
      final cameraState = await _mapboxMap?.getCameraState();
      if (cameraState == null) return;

      final coordinateBounds = await _mapboxMap?.coordinateBoundsForCamera(
        CameraOptions(
          center: cameraState.center,
          zoom: cameraState.zoom,
          pitch: cameraState.pitch,
          bearing: cameraState.bearing,
        )
      );

      if (coordinateBounds == null) return;

      final south = coordinateBounds.southwest.coordinates.lat.toDouble();
      final west = coordinateBounds.southwest.coordinates.lng.toDouble();
      final north = coordinateBounds.northeast.coordinates.lat.toDouble();
      final east = coordinateBounds.northeast.coordinates.lng.toDouble();

      final latDiff = north - south;
      final lngDiff = east - west;

      final bounds = BoundingBox(
        south: south - latDiff,
        west: west - lngDiff,
        north: north + latDiff,
        east: east + lngDiff,
      );

      await ConditionalPOILoader.loadCommunityPOIsIfNeeded(
        ref: ref,
        extendedBounds: bounds,
        onComplete: _addMarkers,
      );
    } catch (e) {
      AppLogger.error('Failed to load Community POIs', error: e);
    }
  }

  /// Load Warnings only if needed (cache empty)
  void _loadWarningsIfNeeded() async {
    try {
      final cameraState = await _mapboxMap?.getCameraState();
      if (cameraState == null) return;

      final coordinateBounds = await _mapboxMap?.coordinateBoundsForCamera(
        CameraOptions(
          center: cameraState.center,
          zoom: cameraState.zoom,
          pitch: cameraState.pitch,
          bearing: cameraState.bearing,
        )
      );

      if (coordinateBounds == null) return;

      final south = coordinateBounds.southwest.coordinates.lat.toDouble();
      final west = coordinateBounds.southwest.coordinates.lng.toDouble();
      final north = coordinateBounds.northeast.coordinates.lat.toDouble();
      final east = coordinateBounds.northeast.coordinates.lng.toDouble();

      final latDiff = north - south;
      final lngDiff = east - west;

      final bounds = BoundingBox(
        south: south - latDiff,
        west: west - lngDiff,
        north: north + latDiff,
        east: east + lngDiff,
      );

      await ConditionalPOILoader.loadWarningsIfNeeded(
        ref: ref,
        extendedBounds: bounds,
        onComplete: _addMarkers,
      );
    } catch (e) {
      AppLogger.error('Failed to load Warnings', error: e);
    }
  }

  /// Start periodic camera monitoring to detect map movement
  void _startCameraMonitoring() {
    _cameraCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_isMapReady || _mapboxMap == null || !mounted) {
        return;
      }

      try {
        final currentState = await _mapboxMap!.getCameraState();
        final currentCenter = currentState.center;
        final currentZoom = currentState.zoom;

        // Update current zoom for UI display
        if (mounted && _currentZoom != currentZoom) {
          setState(() {
            _currentZoom = currentZoom;
          });
        }

        // Check if camera moved significantly
        if (_lastCameraCenter != null && _lastCameraZoom != null) {
          final latDiff = (currentCenter.coordinates.lat - _lastCameraCenter!.coordinates.lat).abs();
          final lngDiff = (currentCenter.coordinates.lng - _lastCameraCenter!.coordinates.lng).abs();
          final zoomDiff = (currentZoom - _lastCameraZoom!).abs();

          // Trigger reload if moved more than ~100m or zoomed
          if (latDiff > 0.001 || lngDiff > 0.001 || zoomDiff > 0.5) {
            _lastCameraCenter = currentCenter;
            _lastCameraZoom = currentZoom;
            _onCameraChanged();
          }
        } else {
          // First check - initialize tracking
          _lastCameraCenter = currentCenter;
          _lastCameraZoom = currentZoom;
        }
      } catch (e) {
        AppLogger.error('Error checking camera state', error: e);
      }
    });
  }

  /// Handle camera change events (debounced to avoid excessive reloads)
  void _onCameraChanged() {
    // Cancel existing timer
    _debounceTimer?.cancel();

    // Set new timer for 1 second after user stops moving
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () async {
      // Don't reload if we just loaded recently (within 5 seconds)
      if (_lastPOILoadTime != null) {
        final timeSinceLastLoad = DateTime.now().difference(_lastPOILoadTime!);
        if (timeSinceLastLoad.inSeconds < 5) {
          AppLogger.debug('Skipping POI reload (loaded ${timeSinceLastLoad.inSeconds}s ago)', tag: 'MAP');
          return;
        }
      }

      AppLogger.map('Camera changed, reloading POIs');
      await _loadAllPOIData();
      _addMarkers();
      _lastPOILoadTime = DateTime.now();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cameraCheckTimer?.cancel();
    super.dispose();
  }

  /// Convert a color to a lighter version for traveled route segments
  /// Takes a Color object and returns a lighter int color value (ARGB)
  int _getLighterColor(Color color) {
    // Increase brightness by blending with white
    // Extract ARGB components
    final a = color.alpha;
    final r = color.red;
    final g = color.green;
    final b = color.blue;

    // Blend with white (70% original, 30% white) and reduce opacity to 60%
    final lighterR = (r * 0.7 + 255 * 0.3).round();
    final lighterG = (g * 0.7 + 255 * 0.3).round();
    final lighterB = (b * 0.7 + 255 * 0.3).round();
    final lighterA = (a * 0.6).round(); // Reduce opacity

    // Combine into ARGB int
    return (lighterA << 24) | (lighterR << 16) | (lighterG << 8) | lighterB;
  }

  /// Create an image from emoji text for use as marker icon
  /// Uses proper background and border colors matching the 2D map configuration
  Future<Uint8List> _createEmojiIcon(
    String emoji,
    POIMarkerType markerType,
    {double size = 48}
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Get colors from MarkerConfig
    final fillColor = MarkerConfig.getFillColorForType(markerType);
    final borderColor = MarkerConfig.getBorderColorForType(markerType);

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw emoji text
    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.6),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Create user location marker icon matching 2D map style
  /// White circle with purple border and Icons.navigation arrow
  Future<Uint8List> _createUserLocationIcon({double? heading, double size = 48}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Use white background with purple border (matching 2D map)
    final fillColor = Colors.white;
    final borderColor = Colors.purple;

    // Save canvas state for rotation
    canvas.save();

    // If we have a heading, rotate the entire marker
    final hasHeading = heading != null && heading >= 0;
    if (hasHeading) {
      // Rotate around center
      // Add 180° to flip direction (GPS heading was pointing opposite)
      canvas.translate(size / 2, size / 2);
      canvas.rotate((heading + 180) * 3.14159 / 180); // Convert to radians, flip 180°
      canvas.translate(-size / 2, -size / 2);
    }

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw navigation arrow or my_location icon
    // Match 2D map: icon size is 60% of marker size
    final iconSize = size * 0.6;

    if (hasHeading) {
      // Draw navigation arrow (custom path matching Icons.navigation)
      final arrowPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;

      // Create triangular navigation arrow pointing up
      final arrowPath = Path();
      final centerX = size / 2;
      final centerY = size / 2;
      final halfIcon = iconSize / 2;

      // Top point (pointing up/north)
      arrowPath.moveTo(centerX, centerY - halfIcon * 0.9);
      // Bottom right
      arrowPath.lineTo(centerX + halfIcon * 0.35, centerY + halfIcon * 0.9);
      // Bottom center notch
      arrowPath.lineTo(centerX, centerY + halfIcon * 0.5);
      // Bottom left
      arrowPath.lineTo(centerX - halfIcon * 0.35, centerY + halfIcon * 0.9);
      // Back to top
      arrowPath.close();

      canvas.drawPath(arrowPath, arrowPaint);
    } else {
      // Exploration mode: Purple dot inside purple circle with grey transparent background

      // Large grey transparent circle (background)
      final greyBgPaint = Paint()
        ..color = Colors.grey.withOpacity(0.1)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        size / 2 - 1, // Almost full size
        greyBgPaint,
      );

      // Purple outer circle (border)
      final purpleCirclePaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        iconSize / 2.5, // Medium circle
        purpleCirclePaint,
      );

      // Purple center dot (filled)
      final dotPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        iconSize / 5, // Small dot
        dotPaint,
      );
    }

    // Restore canvas state
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Create road sign warning image (orange circle matching community hazards style)
  Future<Uint8List> _createRoadSignImage(String surfaceType, {double size = 48}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Orange circle with ~20% opacity to match community hazard transparency
    final bgPaint = Paint()
      ..color = const Color(0x33FFE0B2) // orange.shade100 with ~20% opacity
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.orange // Orange border (solid)
      ..style = PaintingStyle.stroke
      ..strokeWidth = MarkerConfig.circleStrokeWidth;

    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - MarkerConfig.circleStrokeWidth;

    // Draw orange filled circle
    canvas.drawCircle(center, radius, bgPaint);
    // Draw orange border
    canvas.drawCircle(center, radius, borderPaint);

    // Get surface-specific icon (matching 2D map)
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

    // Draw Material Icon using TextPainter with icon font
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.orange.shade900,
          fontSize: size * 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size / 2 - textPainter.width / 2, size / 2 - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Add POI and warning markers to the map
  /// All markers use emoji icon images with proper colors
  Future<void> _addMarkers() async {
    if (_pointAnnotationManager == null || !_isMapReady) {
      AppLogger.warning('Annotation managers not ready', tag: 'MAP');
      return;
    }

    // Clear existing markers (with error handling)
    try {
      await _pointAnnotationManager!.deleteAll();
    } catch (e) {
      AppLogger.warning('Could not delete existing markers: $e', tag: 'MAP');
      // Continue anyway - might be first load
    }

    final mapState = ref.read(mapProvider);

    // Clear POI maps
    _osmPoiById.clear();
    _communityPoiById.clear();
    _warningById.clear();
    _destinationsById.clear();
    _favoritesById.clear();

    // Add user location marker (custom, matching 2D map style)
    await _addUserLocationMarker();

    // Add all POI markers as emoji icons
    await _addOSMPOIsAsIcons(mapState);
    await _addCommunityPOIsAsIcons(mapState);
    await _addWarningsAsIcons(mapState);

    // Add route hazards during turn-by-turn navigation
    await _addRouteHazards();

    // Add favorites and destinations markers if toggle is enabled
    await _addFavoritesAndDestinations();

    // Add search result marker if available
    await _addSearchResultMarker();

    // Add route polyline if available
    await _addRoutePolyline();

    // Add surface warning markers if navigation is active
    await _addSurfaceWarningMarkers();
  }

  /// Add search result marker (grey circle with + symbol)
  Future<void> _addSearchResultMarker() async {
    final searchState = ref.read(searchProvider);
    if (searchState.selectedLocation == null) return;

    final selectedLoc = searchState.selectedLocation!;
    AppLogger.debug('Adding search result marker', tag: 'MAP', data: {
      'lat': selectedLoc.latitude,
      'lon': selectedLoc.longitude,
    });

    // Create grey marker icon with + symbol (matching POI style)
    final markerIcon = await _createSearchResultIcon();

    final searchMarker = PointAnnotationOptions(
      geometry: Point(coordinates: Position(selectedLoc.longitude, selectedLoc.latitude)),
      image: markerIcon,
      iconSize: 1.8, // Match user location marker size
      iconAnchor: IconAnchor.CENTER, // Center-aligned like other POIs
    );

    await _pointAnnotationManager!.create(searchMarker);
    AppLogger.success('Search result marker added', tag: 'MAP');
  }

  /// Create search result marker icon (grey circle with + symbol)
  /// Matches user location marker size and uses same transparency
  Future<Uint8List> _createSearchResultIcon({double size = 48}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Grey colors with transparency matching user location marker
    final fillColor = const Color(0x33757575); // Grey with ~20% opacity (same as user location)
    final borderColor = Colors.grey.shade700;

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw + symbol in red
    final plusPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final plusSize = size * 0.5;
    final center = size / 2;

    // Horizontal line of +
    canvas.drawLine(
      Offset(center - plusSize / 2, center),
      Offset(center + plusSize / 2, center),
      plusPaint,
    );

    // Vertical line of +
    canvas.drawLine(
      Offset(center, center - plusSize / 2),
      Offset(center, center + plusSize / 2),
      plusPaint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Add route polyline to map
  Future<void> _addRoutePolyline() async {
    if (_mapboxMap == null) {
      AppLogger.warning('Cannot add route polyline - map not ready', tag: 'MAP');
      return;
    }

    final searchState = ref.read(searchProvider);
    final routePoints = searchState.routePoints;
    final previewFastest = searchState.previewFastestRoute;
    final previewSafest = searchState.previewSafestRoute;
    final previewShortest = searchState.previewShortestRoute;

    // Clear all route layers and sources
    // CRITICAL: Must remove layers BEFORE sources (Mapbox requirement)
    final layersToRemove = [
      'route-layer', // Single-color route
      'preview-fastest-layer',
      'preview-safest-layer',
      'preview-shortest-layer',
    ];
    final sourcesToRemove = [
      'route-source', // Single-color route
      'preview-fastest-source',
      'preview-safest-source',
      'preview-shortest-source',
    ];

    // Also remove surface-colored route layers (route-layer-0, route-layer-1, etc.)
    // During navigation, routes are split into segments by surface type
    for (int i = 0; i < 50; i++) {
      layersToRemove.add('route-layer-$i');
      sourcesToRemove.add('route-source-$i');
    }

    // Step 1: Remove all layers
    int layersRemoved = 0;
    for (final layer in layersToRemove) {
      try {
        await _mapboxMap!.style.removeStyleLayer(layer);
        layersRemoved++;
      } catch (e) {
        // Layer doesn't exist, that's fine
      }
    }

    // Wait for layer removals to complete
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 2: Remove all sources (only after layers are removed)
    int sourcesRemoved = 0;
    for (final source in sourcesToRemove) {
      try {
        await _mapboxMap!.style.removeStyleSource(source);
        sourcesRemoved++;
      } catch (e) {
        // Source doesn't exist, that's fine
      }
    }

    // Wait for source removals to complete before adding new ones
    await Future.delayed(const Duration(milliseconds: 100));

    // Show preview routes if at least 2 exist
    if (previewFastest != null && (previewSafest != null || previewShortest != null)) {
      AppLogger.debug('Adding preview route polylines', tag: 'MAP', data: {
        'fastest': previewFastest.length,
        'safest': previewSafest?.length ?? 0,
        'shortest': previewShortest?.length ?? 0,
      });

      try {
        // Add fastest route (blue)
        final fastestPositions = previewFastest.map((point) =>
          Position(point.longitude, point.latitude)
        ).toList();
        final fastestLineString = LineString(coordinates: fastestPositions);
        final fastestSource = GeoJsonSource(
          id: 'preview-fastest-source',
          data: jsonEncode(fastestLineString.toJson()),
        );
        await _mapboxMap?.style.addSource(fastestSource);
        final fastestLayer = LineLayer(
          id: 'preview-fastest-layer',
          sourceId: 'preview-fastest-source',
          lineColor: 0xFFF44336, // Red (car)
          lineWidth: 8.0,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
        );
        await _mapboxMap?.style.addLayer(fastestLayer);

        // Add safest route (green) if exists
        if (previewSafest != null) {
          final safestPositions = previewSafest.map((point) =>
            Position(point.longitude, point.latitude)
          ).toList();
          final safestLineString = LineString(coordinates: safestPositions);
          final safestSource = GeoJsonSource(
            id: 'preview-safest-source',
            data: jsonEncode(safestLineString.toJson()),
          );
          await _mapboxMap?.style.addSource(safestSource);
          final safestLayer = LineLayer(
            id: 'preview-safest-layer',
            sourceId: 'preview-safest-source',
            lineColor: 0xFF4CAF50, // Green
            lineWidth: 8.0,
            lineCap: LineCap.ROUND,
            lineJoin: LineJoin.ROUND,
          );
          await _mapboxMap?.style.addLayer(safestLayer);
        }

        // Add shortest route (red) if exists
        if (previewShortest != null) {
          final shortestPositions = previewShortest.map((point) =>
            Position(point.longitude, point.latitude)
          ).toList();
          final shortestLineString = LineString(coordinates: shortestPositions);
          final shortestSource = GeoJsonSource(
            id: 'preview-shortest-source',
            data: jsonEncode(shortestLineString.toJson()),
          );
          await _mapboxMap?.style.addSource(shortestSource);
          final shortestLayer = LineLayer(
            id: 'preview-shortest-layer',
            sourceId: 'preview-shortest-source',
            lineColor: 0xFF2196F3, // Blue (foot/walking)
            lineWidth: 8.0,
            lineCap: LineCap.ROUND,
            lineJoin: LineJoin.ROUND,
          );
          await _mapboxMap?.style.addLayer(shortestLayer);
        }

        AppLogger.success('Preview route polylines added', tag: 'MAP');
      } catch (e, stackTrace) {
        AppLogger.error('Failed to add preview route polylines', tag: 'MAP', error: e, stackTrace: stackTrace);
      }
      return;
    }

    // Check if turn-by-turn navigation is active
    final turnByTurnNavState = ref.read(navigationProvider);

    AppLogger.debug('Route rendering decision', tag: 'MAP', data: {
      'isNavigating': turnByTurnNavState.isNavigating,
      'hasActiveRoute': turnByTurnNavState.activeRoute != null,
      'hasRoutePoints': routePoints != null && routePoints!.isNotEmpty,
    });

    // Use navigation route if active, otherwise use selected route
    List<latlong.LatLng>? routeToRender;
    bool isNavigating = false;
    Map<String, dynamic>? pathDetails;
    int? currentPointIndex; // Index of current position in route coordinates

    if (turnByTurnNavState.isNavigating && turnByTurnNavState.activeRoute != null) {
      routeToRender = turnByTurnNavState.activeRoute!.points;
      pathDetails = turnByTurnNavState.activeRoute!.pathDetails;
      isNavigating = true;

      // Find current point index by finding closest point on route to GPS position
      final currentPos = turnByTurnNavState.currentPosition;
      if (currentPos != null && routeToRender.isNotEmpty) {
        double minDistance = double.infinity;
        int closestIndex = 0;

        for (int i = 0; i < routeToRender.length; i++) {
          final distance = GeoUtils.calculateDistance(
            currentPos.latitude,
            currentPos.longitude,
            routeToRender[i].latitude,
            routeToRender[i].longitude,
          );

          if (distance < minDistance) {
            minDistance = distance;
            closestIndex = i;
          }
        }

        currentPointIndex = closestIndex;
      }

      AppLogger.debug('Rendering navigation route (surface-colored)', tag: 'MAP', data: {
        'points': routeToRender.length,
        'currentPointIndex': currentPointIndex,
        'hasSurfaceData': pathDetails?.containsKey('surface') ?? false,
      });
    } else if (routePoints != null && routePoints.isNotEmpty) {
      routeToRender = routePoints;
      isNavigating = false;
      AppLogger.warning('STILL RENDERING selected route even though navigation ended!', tag: 'MAP', data: {
        'points': routeToRender.length,
        'routePointsFromSearchProvider': routePoints.length,
      });
    } else {
      AppLogger.debug('No route to render - layers/sources cleared', tag: 'MAP');
      return; // No route to render
    }

    try {
      // During navigation with surface data, render color-coded segments
      if (isNavigating && pathDetails != null && pathDetails.containsKey('surface')) {
        final segments = RouteSurfaceHelper.createSurfaceSegments(routeToRender, pathDetails);

        // Clear and rebuild segment metadata cache
        _routeSegments.clear();
        _traveledSegmentIndices.clear();

        AppLogger.debug('Rendering ${segments.length} surface segments', tag: 'MAP', data: {
          'currentPointIndex': currentPointIndex ?? 0,
        });

        for (int i = 0; i < segments.length; i++) {
          final segment = segments[i];

          // Convert LatLng points to Mapbox Position list
          final positions = segment.points.map((point) =>
            Position(point.longitude, point.latitude)
          ).toList();

          if (positions.length < 2) continue; // Skip segments with less than 2 points

          // Create LineString geometry
          final lineString = LineString(coordinates: positions);

          // Create GeoJSON source
          final geoJsonSource = GeoJsonSource(
            id: 'route-source-$i',
            data: jsonEncode(lineString.toJson()),
          );

          // Add source to map
          await _mapboxMap?.style.addSource(geoJsonSource);

          // Determine if this segment is behind the user (traveled) or ahead (remaining)
          // Compare segment's end coordinate index with current position's coordinate index
          final segmentEndIndex = segment.endIndex;
          final isTraveled = currentPointIndex != null && segmentEndIndex < currentPointIndex;

          // Cache segment metadata for efficient updates
          _routeSegments.add(_RouteSegmentMetadata(
            index: i,
            endIndex: segmentEndIndex,
            originalColor: segment.color,
          ));

          if (isTraveled) {
            _traveledSegmentIndices.add(i);
          }

          // Use lighter color for traveled segments, normal color for remaining
          final segmentColor = isTraveled
              ? _getLighterColor(segment.color) // Lighter version of surface color
              : segment.color.value; // Original surface color

          // Create line layer with surface color (lighter for traveled)
          final lineLayer = LineLayer(
            id: 'route-layer-$i',
            sourceId: 'route-source-$i',
            lineColor: segmentColor,
            lineWidth: isTraveled ? 4.0 : 6.0, // Slightly thinner for traveled
            lineCap: LineCap.ROUND,
            lineJoin: LineJoin.ROUND,
          );

          // Add layer to map
          await _mapboxMap?.style.addLayer(lineLayer);
        }

        AppLogger.success('Surface-colored route added (${segments.length} segments)', tag: 'MAP');
      } else {
        // Render single-color route (preview or no surface data)
        final routeColor = isNavigating ? 0xFF2196F3 : 0xFF85a78b; // Blue for navigation without data, green for preview

        // Convert LatLng points to Mapbox Position list
        final positions = routeToRender.map((point) =>
          Position(point.longitude, point.latitude)
        ).toList();

        // Create LineString geometry
        final lineString = LineString(coordinates: positions);

        // Create GeoJSON source with JSON string
        final geoJsonSource = GeoJsonSource(
          id: 'route-source',
          data: jsonEncode(lineString.toJson()),
        );

        // Add source to map
        await _mapboxMap?.style.addSource(geoJsonSource);

        // Create line layer for the route
        final lineLayer = LineLayer(
          id: 'route-layer',
          sourceId: 'route-source',
          lineColor: routeColor,
          lineWidth: 6.0,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
        );

        // Add layer to map
        await _mapboxMap?.style.addLayer(lineLayer);

        AppLogger.success('Single-color route added', tag: 'MAP', data: {
          'points': routeToRender.length,
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add route polyline', tag: 'MAP', error: e, stackTrace: stackTrace, data: {
        'routePointsCount': routeToRender?.length ?? 0,
        'errorType': e.runtimeType.toString(),
      });
    }
  }

  /// Add surface warning markers for poor/special surface segments
  Future<void> _addSurfaceWarningMarkers() async {
    if (_pointAnnotationManager == null) return;

    try {
      // Check if navigation is active
      final navState = ref.read(navigationProvider);
      if (!navState.isNavigating || navState.activeRoute == null) {
        return; // Only show during navigation
      }

      final pathDetails = navState.activeRoute!.pathDetails;
      if (pathDetails == null || !pathDetails.containsKey('surface')) {
        return; // No surface data
      }

      // Get warning marker positions
      final warningMarkers = RouteSurfaceHelper.getSurfaceWarningMarkers(
        navState.activeRoute!.points,
        pathDetails,
      );

      AppLogger.debug('Adding ${warningMarkers.length} surface warning markers', tag: 'MAP');

      // Create point annotations for each warning (using road sign style)
      List<PointAnnotationOptions> warningAnnotations = [];
      for (final marker in warningMarkers) {
        final pointAnnotation = PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(
              marker.position.longitude,
              marker.position.latitude,
            ),
          ),
          image: await _createRoadSignImage(marker.surfaceType),
          iconSize: 1.5, // Match community POI/warning size
          iconAnchor: IconAnchor.CENTER,
        );

        warningAnnotations.add(pointAnnotation);
      }

      // Batch create all warning annotations
      if (warningAnnotations.isNotEmpty) {
        await _pointAnnotationManager?.createMulti(warningAnnotations);
      }

      AppLogger.success('Surface warning markers added', tag: 'MAP', data: {
        'count': warningMarkers.length,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add surface warning markers', tag: 'MAP', error: e, stackTrace: stackTrace);
    }
  }

  /// Add custom user location marker matching 2D map style
  /// TEMPORARY: Disabled for testing with default Mapbox location puck
  Future<void> _addUserLocationMarker() async {
    // DISABLED FOR TESTING - using default Mapbox location puck
    AppLogger.debug('Custom user location marker disabled (using default puck)', tag: 'MAP');
    return;

    /* ORIGINAL CODE - COMMENTED OUT FOR TESTING
    final locationAsync = ref.read(locationNotifierProvider);
    final compassHeading = ref.read(compassNotifierProvider);
    final navState = ref.read(navigationModeProvider);
    final isNavigationMode = navState.mode == NavMode.navigation;

    await locationAsync.whenData((location) async {
      if (location != null) {
        // Use compass heading if available, otherwise GPS heading
        final heading = compassHeading ?? location.heading;
        final hasHeading = heading != null && heading >= 0;

        AppLogger.debug('Adding user location marker', tag: 'MAP', data: {
          'lat': location.latitude,
          'lng': location.longitude,
          'heading': heading,
          'navMode': isNavigationMode,
        });

        // Create custom location icon matching 2D map
        // In navigation mode with heading: show arrow
        // Otherwise: show dot
        final userIcon = await _createUserLocationIcon(
          heading: (isNavigationMode && hasHeading) ? heading : null,
        );

        final userMarker = PointAnnotationOptions(
          geometry: Point(coordinates: Position(location.longitude, location.latitude)),
          image: userIcon,
          iconSize: 1.8, // Match 2D map ratio (12:10 = 1.2, so 1.5 * 1.2 = 1.8)
        );

        await _pointAnnotationManager!.create(userMarker);
        AppLogger.success('User location marker added', tag: 'MAP');
      }
    });
    */
  }

  /// Add OSM POIs as emoji icons
  Future<void> _addOSMPOIsAsIcons(mapState) async {
    if (!mapState.showOSMPOIs) return;

    final osmPOIs = ref.read(osmPOIsNotifierProvider).value ?? [];

    // Filter POIs based on selected types using shared utility
    final filteredPOIs = POIUtils.filterPOIsByType(osmPOIs, mapState.selectedOSMPOITypes);

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding OSM POIs as icons', tag: 'MAP', data: {
      'total': osmPOIs.length,
      'filtered': filteredPOIs.length,
      'selectedTypes': mapState.selectedOSMPOITypes?.join(', ') ?? 'all',
    });

    for (var poi in filteredPOIs) {
      final id = 'osm_${poi.latitude}_${poi.longitude}';
      _osmPoiById[id] = poi;

      // Get emoji for this POI type
      final emoji = POITypeConfig.getOSMPOIEmoji(poi.type);

      // Create icon image from emoji with proper colors
      final iconImage = await _createEmojiIcon(emoji, POIMarkerType.osmPOI);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
          image: iconImage,
          iconSize: 1.5, // Optimized icon size
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(pointOptions);
      AppLogger.success('Added OSM POI icons', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Add Community POIs as emoji icons
  Future<void> _addCommunityPOIsAsIcons(mapState) async {
    if (!mapState.showPOIs) return;

    final communityPOIs = ref.read(cyclingPOIsBoundsNotifierProvider).value ?? [];
    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding Community POIs as icons', tag: 'MAP', data: {'count': communityPOIs.length});
    for (var poi in communityPOIs) {
      final id = 'community_${poi.latitude}_${poi.longitude}';
      _communityPoiById[id] = poi;

      // Get emoji for this POI type
      final emoji = POITypeConfig.getCommunityPOIEmoji(poi.type);

      // Create icon image from emoji with proper colors
      final iconImage = await _createEmojiIcon(emoji, POIMarkerType.communityPOI);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
          image: iconImage,
          iconSize: 1.5, // Optimized icon size
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(pointOptions);
      AppLogger.success('Added Community POI icons', tag: 'MAP', data: {'count': pointOptions.length});
    } else {
      AppLogger.warning('No Community POI icons to add', tag: 'MAP');
    }
  }

  /// Add Warnings as emoji icons
  Future<void> _addWarningsAsIcons(mapState) async {
    if (!mapState.showWarnings) return;

    final warnings = ref.read(communityWarningsBoundsNotifierProvider).value ?? [];
    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding Warnings as icons', tag: 'MAP', data: {'count': warnings.length});
    for (var warning in warnings) {
      final id = 'warning_${warning.latitude}_${warning.longitude}';
      _warningById[id] = warning;

      // Get emoji for this warning type
      final emoji = POITypeConfig.getWarningEmoji(warning.type);

      // Create icon image from emoji with proper colors
      final iconImage = await _createEmojiIcon(emoji, POIMarkerType.warning);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(warning.longitude, warning.latitude)),
          image: iconImage,
          iconSize: 1.5, // Optimized icon size
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(pointOptions);
      AppLogger.success('Added Warning icons', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Add route hazards as warning markers (only during turn-by-turn navigation)
  Future<void> _addRouteHazards() async {
    if (_pointAnnotationManager == null) return;

    final navState = ref.read(navigationProvider);
    if (!navState.isNavigating || navState.activeRoute?.routeHazards == null) {
      return;
    }

    final routeHazards = navState.activeRoute!.routeHazards!;
    if (routeHazards.isEmpty) return;

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding route hazards as markers', tag: 'MAP', data: {'count': routeHazards.length});
    for (var hazard in routeHazards) {
      final warning = hazard.warning;
      final id = 'route_hazard_${warning.latitude}_${warning.longitude}';
      _warningById[id] = warning;

      // Get emoji for this warning type
      final emoji = POITypeConfig.getWarningEmoji(warning.type);

      // Create icon image from emoji with warning colors (red circle)
      final iconImage = await _createEmojiIcon(emoji, POIMarkerType.warning);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(warning.longitude, warning.latitude)),
          image: iconImage,
          iconSize: 1.5, // Same size as regular warnings
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(pointOptions);
      AppLogger.success('Added route hazard markers', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Add favorites and destinations markers to map
  Future<void> _addFavoritesAndDestinations() async {
    if (_pointAnnotationManager == null) return;

    final favoritesVisible = ref.read(favoritesVisibilityProvider);
    if (!favoritesVisible) return;

    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) return;

    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding favorites and destinations as markers', tag: 'MAP', data: {
      'destinations': userProfile.recentDestinations.length,
      'favorites': userProfile.favoriteLocations.length,
    });

    // Add destination markers (orange teardrop)
    for (var destination in userProfile.recentDestinations) {
      final id = 'destination_${destination.latitude}_${destination.longitude}';
      _destinationsById[id] = (lat: destination.latitude, lng: destination.longitude, name: destination.name);

      final iconImage = await _createFavoritesIcon(isDestination: true);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(destination.longitude, destination.latitude)),
          image: iconImage,
          iconSize: 1.5,
          iconAnchor: IconAnchor.CENTER,
        ),
      );
    }

    // Add favorite markers (yellow star)
    for (var favorite in userProfile.favoriteLocations) {
      final id = 'favorite_${favorite.latitude}_${favorite.longitude}';
      _favoritesById[id] = (lat: favorite.latitude, lng: favorite.longitude, name: favorite.name);

      final iconImage = await _createFavoritesIcon(isDestination: false);

      pointOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(favorite.longitude, favorite.latitude)),
          image: iconImage,
          iconSize: 1.5,
          iconAnchor: IconAnchor.CENTER,
        ),
      );
    }

    if (pointOptions.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(pointOptions);
      AppLogger.success('Added favorites/destinations markers', tag: 'MAP', data: {'count': pointOptions.length});
    }
  }

  /// Create favorites/destinations icon (teardrop for destinations, star for favorites)
  Future<Uint8List> _createFavoritesIcon({required bool isDestination, double size = 48}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Colors based on type
    final fillColor = isDestination
        ? const Color(0xE6FFCC80) // Orange with ~90% opacity
        : const Color(0xE6FFD54F); // Amber with ~90% opacity
    final borderColor = isDestination
        ? Colors.orange.shade700
        : Colors.amber.shade700;

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw emoji icon (teardrop for destinations, star for favorites)
    final textPainter = TextPainter(
      text: TextSpan(
        text: isDestination ? '📍' : '⭐',
        style: TextStyle(fontSize: size * 0.5, fontFamily: 'sans-serif'),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ============================================================================
  // NAVIGATION MODE METHODS (GPS-based rotation, auto-center, breadcrumbs)
  // ============================================================================

  /// Handle GPS location changes for navigation mode
  void _handleGPSLocationChange(LocationData location) async {
    if (!_isMapReady || _mapboxMap == null) {
      return;
    }

    final newGPSPosition = latlong.LatLng(location.latitude, location.longitude);
    final navState = ref.read(navigationModeProvider);
    final isNavigationMode = navState.mode == NavMode.navigation;

    // Add breadcrumb for navigation mode
    if (isNavigationMode) {
      _addBreadcrumb(location);
    }

    // Turn-by-turn navigation camera auto-follow (user at 3/4 from top)
    final turnByTurnNavState = ref.read(navigationProvider);
    AppLogger.debug('Checking turn-by-turn nav state', tag: 'CAMERA', data: {
      'isNavigating': turnByTurnNavState.isNavigating,
    });
    if (turnByTurnNavState.isNavigating) {
      AppLogger.success('Starting camera follow for turn-by-turn', tag: 'CAMERA');
      _lastGPSPosition = newGPSPosition;
      await _handleTurnByTurnCameraFollow(location);

      // Update traveled route segments only when position changes significantly
      await _updateTraveledRouteIfNeeded(location);

      return; // Skip regular navigation mode camera (turn-by-turn takes priority)
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
          final targetZoom = NavigationUtils.calculateNavigationZoom(location.speed);
          _targetAutoZoom = targetZoom;

          // Determine actual zoom to use (with throttling if auto-zoom enabled)
          final currentCamera = await _mapboxMap!.getCameraState();
          double actualZoom = currentCamera.zoom;

          if (mapState.autoZoomEnabled) {
            final now = DateTime.now();
            final canChangeZoom = _lastZoomChangeTime == null ||
                now.difference(_lastZoomChangeTime!) >= _zoomChangeInterval;

            if (canChangeZoom) {
              final currentZoom = _currentAutoZoom ?? currentCamera.zoom;
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
              actualZoom = _currentAutoZoom ?? currentCamera.zoom;
            }
          }

          // Rotate map based on travel direction (keep last rotation if stationary)
          final travelBearing = _calculateTravelDirection();
          if (travelBearing != null) {
            await _mapboxMap!.easeTo(
              CameraOptions(
                center: Point(coordinates: Position(location.longitude, location.latitude)),
                zoom: actualZoom,
                bearing: -travelBearing, // Negative: up = direction of travel
                pitch: _currentPitch,
              ),
              MapAnimationOptions(duration: 500), // 500ms smooth animation
            );
            _lastNavigationBearing = travelBearing;
          } else if (_lastNavigationBearing != null) {
            // Keep last bearing when stationary
            await _mapboxMap!.easeTo(
              CameraOptions(
                center: Point(coordinates: Position(location.longitude, location.latitude)),
                zoom: actualZoom,
                bearing: -_lastNavigationBearing!,
                pitch: _currentPitch,
              ),
              MapAnimationOptions(duration: 500),
            );
          } else {
            // No bearing yet, just center
            await _mapboxMap!.easeTo(
              CameraOptions(
                center: Point(coordinates: Position(location.longitude, location.latitude)),
                zoom: actualZoom,
                pitch: _currentPitch,
              ),
              MapAnimationOptions(duration: 500),
            );
          }
        } else {
          // Exploration mode: simple auto-center, keep zoom and rotation
          final currentCamera = await _mapboxMap!.getCameraState();
          await _mapboxMap!.easeTo(
            CameraOptions(
              center: Point(coordinates: Position(location.longitude, location.latitude)),
              zoom: currentCamera.zoom,
              bearing: currentCamera.bearing,
              pitch: currentCamera.pitch,
            ),
            MapAnimationOptions(duration: 500),
          );
        }

        await _loadAllPOIData();
        _originalGPSReference = newGPSPosition;
      }
    } else {
      // First GPS fix - set reference
      _originalGPSReference = newGPSPosition;
    }

    _lastGPSPosition = newGPSPosition;

    // Don't call _addMarkers() here - it causes blinking!
    // User location is shown by default Mapbox location puck (auto-updated)
    // POIs/warnings/route don't need to be redrawn on every GPS update
    // They are already on the map and update via listeners when data changes
  }

  /// Add breadcrumb for navigation mode rotation
  void _addBreadcrumb(LocationData location) {
    final now = DateTime.now();
    final newPosition = latlong.LatLng(location.latitude, location.longitude);

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

  /// Calculate travel direction from breadcrumbs with smoothing
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

    AppLogger.debug('Bearing calculation', tag: 'BEARING', data: {
      'startLat': start.latitude.toStringAsFixed(6),
      'startLon': start.longitude.toStringAsFixed(6),
      'endLat': end.latitude.toStringAsFixed(6),
      'endLon': end.longitude.toStringAsFixed(6),
      'calculatedBearing': '${bearing.toStringAsFixed(1)}°',
      'direction': GeoUtils.formatBearing(bearing),
    });

    // Smooth bearing with last value (90% new, 10% old) - very responsive
    double finalBearing = bearing;
    if (_lastNavigationBearing != null) {
      final diff = (bearing - _lastNavigationBearing!).abs();
      if (diff < 180) {
        finalBearing = bearing * 0.9 + _lastNavigationBearing! * 0.1;
        AppLogger.debug('Bearing smoothed', tag: 'BEARING', data: {
          'oldBearing': '${_lastNavigationBearing!.toStringAsFixed(1)}°',
          'newBearing': '${bearing.toStringAsFixed(1)}°',
          'smoothedBearing': '${finalBearing.toStringAsFixed(1)}°',
          'appliedToMap': '${(-finalBearing).toStringAsFixed(1)}°',
        });
      }
    } else {
      AppLogger.debug('First bearing (no smoothing)', tag: 'BEARING', data: {
        'bearing': '${finalBearing.toStringAsFixed(1)}°',
        'appliedToMap': '${(-finalBearing).toStringAsFixed(1)}°',
      });
    }

    return finalBearing;
  }

  /// Update traveled route segments efficiently by only updating changed segments
  /// Only updates individual layer properties instead of redrawing entire route
  Future<void> _updateTraveledRouteIfNeeded(LocationData location) async {
    if (_mapboxMap == null || _routeSegments.isEmpty) return;

    final navState = ref.read(navigationProvider);
    if (!navState.isNavigating || navState.activeRoute == null) return;

    final routePoints = navState.activeRoute!.points;
    if (routePoints.isEmpty) return;

    // Find current point index
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < routePoints.length; i++) {
      final distance = GeoUtils.calculateDistance(
        location.latitude,
        location.longitude,
        routePoints[i].latitude,
        routePoints[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // Only update if position changed significantly
    if (_lastRoutePointIndex == null || closestIndex == _lastRoutePointIndex) {
      _lastRoutePointIndex = closestIndex;
      return;
    }

    _lastRoutePointIndex = closestIndex;

    // Find segments that changed state (from remaining → traveled)
    final segmentsToUpdate = <int>[];

    for (final segment in _routeSegments) {
      final shouldBeTraveled = segment.endIndex < closestIndex;
      final isTraveled = _traveledSegmentIndices.contains(segment.index);

      // State changed: need to update this segment
      if (shouldBeTraveled != isTraveled) {
        segmentsToUpdate.add(segment.index);

        if (shouldBeTraveled) {
          _traveledSegmentIndices.add(segment.index);
        } else {
          _traveledSegmentIndices.remove(segment.index);
        }
      }
    }

    // Update only the segments that changed
    if (segmentsToUpdate.isNotEmpty) {
      for (final segmentIndex in segmentsToUpdate) {
        final segment = _routeSegments[segmentIndex];
        final isTraveled = _traveledSegmentIndices.contains(segmentIndex);

        // Calculate new color and width
        final newColor = isTraveled
            ? _getLighterColor(segment.originalColor)
            : segment.originalColor.value;
        final newWidth = isTraveled ? 4.0 : 6.0;

        try {
          // Update layer properties efficiently (no redraw needed)
          await _mapboxMap!.style.setStyleLayerProperty(
            'route-layer-$segmentIndex',
            'line-color',
            newColor,
          );
          await _mapboxMap!.style.setStyleLayerProperty(
            'route-layer-$segmentIndex',
            'line-width',
            newWidth,
          );
        } catch (e) {
          AppLogger.warning('Failed to update segment $segmentIndex: $e', tag: 'MAP');
        }
      }

      AppLogger.debug('Updated ${segmentsToUpdate.length} route segments', tag: 'MAP', data: {
        'pointIndex': closestIndex,
        'segmentsChanged': segmentsToUpdate.length,
        'totalSegments': _routeSegments.length,
      });
    }
  }

  /// Handle camera auto-follow for turn-by-turn navigation
  /// Positions user at 3/4 from top of screen for better forward view
  Future<void> _handleTurnByTurnCameraFollow(LocationData location) async {
    if (_mapboxMap == null) return;

    // Calculate target zoom based on speed
    final targetZoom = NavigationUtils.calculateNavigationZoom(location.speed);

    // Calculate bearing from travel direction (breadcrumbs) - matches 2D behavior
    // NOTE: Do NOT use location.heading for map rotation, only for marker arrow
    final bearing = _calculateTravelDirection();

    AppLogger.debug('Turn-by-turn camera update', tag: 'CAMERA', data: {
      'speed': '${((location.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h',
      'zoom': targetZoom.toStringAsFixed(1),
      'heading': location.heading?.toStringAsFixed(0) ?? 'null',
      'bearing': bearing?.toStringAsFixed(0) ?? 'null',
      'pitch': _currentPitch.toStringAsFixed(0),
    });

    // Camera centered on user position
    await _mapboxMap!.easeTo(
      CameraOptions(
        center: Point(coordinates: Position(location.longitude, location.latitude)),
        zoom: targetZoom,
        bearing: bearing ?? 0, // Positive bearing: direction at top of screen
        pitch: _currentPitch,
        padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      ),
      MapAnimationOptions(duration: 500), // Smooth 500ms animation
    );

    AppLogger.debug('Turn-by-turn camera follow', tag: 'NAVIGATION', data: {
      'zoom': targetZoom.toStringAsFixed(1),
      'bearing': bearing?.toStringAsFixed(1) ?? 'none',
      'speed': '${(location.speed ?? 0) * 3.6}km/h',
    });
  }

  /// Stop navigation and clear route
  void _stopNavigation() {
    // Clear route from provider
    ref.read(searchProvider.notifier).clearRoute();

    // Stop turn-by-turn navigation
    ref.read(navigationProvider.notifier).stopNavigation();

    // Exit navigation mode (return to exploration)
    ref.read(navigationModeProvider.notifier).stopRouteNavigation();

    // Keep current map rotation (don't reset to north)

    // Clear breadcrumbs
    _breadcrumbs.clear();
    _lastNavigationBearing = null;

    // Clear active route sheet
    setState(() {
      _activeRoute = null;
    });

    // Refresh markers to remove route from map
    // Add small delay to ensure provider state propagates
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _addMarkers();
        AppLogger.map('Navigation stopped - route cleared from map');
      }
    });
  }
}

/// Click listener for PointAnnotations (all POI icons)
class _OnPointClickListener extends OnPointAnnotationClickListener {
  final void Function(double lat, double lng) onTap;

  _OnPointClickListener({required this.onTap});

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    final coords = annotation.geometry.coordinates;
    AppLogger.map('Point annotation clicked', data: {'lat': coords.lat, 'lng': coords.lng});
    onTap(coords.lat.toDouble(), coords.lng.toDouble());
  }
}

/// Helper class for GPS breadcrumb tracking
class _LocationBreadcrumb {
  final latlong.LatLng position;
  final DateTime timestamp;
  final double? speed; // m/s

  _LocationBreadcrumb({
    required this.position,
    required this.timestamp,
    this.speed,
  });
}

/// Helper class to cache route segment metadata for efficient updates
class _RouteSegmentMetadata {
  final int index;
  final int endIndex;
  final Color originalColor;

  _RouteSegmentMetadata({
    required this.index,
    required this.endIndex,
    required this.originalColor,
  });
}

/// Route stat widget for navigation sheet
class _RouteStatWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RouteStatWidget({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}