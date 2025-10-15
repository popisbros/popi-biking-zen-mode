import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
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
import '../services/map_service.dart';
import '../services/routing_service.dart';
import '../services/ios_navigation_service.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/app_logger.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/navigation_card.dart';
import '../services/route_surface_helper.dart';
import '../widgets/navigation_controls.dart';
import '../widgets/arrival_dialog.dart';
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
  String _debugMessage = 'Tap GPS button to test';
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
    );
  }

  Future<void> _centerOnUserLocation() async {
    AppLogger.map('GPS button clicked');
    setState(() => _debugMessage = 'GPS button clicked...');

    if (_mapboxMap == null) {
      AppLogger.error('Map not ready', tag: 'Mapbox3D');
      setState(() => _debugMessage = 'ERROR: Map not ready');
      return;
    }

    try {
      setState(() => _debugMessage = 'Requesting location...');
      AppLogger.map('Reading location from provider');

      final locationAsync = ref.read(locationNotifierProvider);

      locationAsync.when(
        data: (location) {
          if (location != null) {
            AppLogger.success('Got location', tag: 'Mapbox3D', data: {
              'lat': location.latitude,
              'lng': location.longitude,
            });
            setState(() => _debugMessage = 'Got location: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}');

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
                setState(() => _debugMessage = 'SUCCESS! Centered on your location');
              }
            });
          } else {
            AppLogger.error('Location is NULL', tag: 'Mapbox3D');
            setState(() => _debugMessage = 'ERROR: Location is null (permission denied?)');
          }
        },
        loading: () {
          AppLogger.ios('Location still loading', data: {'screen': 'Mapbox3D'});
          setState(() => _debugMessage = 'Location is loading...');
        },
        error: (error, _) {
          AppLogger.error('Location error', tag: 'Mapbox3D', error: error);
          setState(() => _debugMessage = 'ERROR: $error');
        },
      );
    } catch (e) {
      AppLogger.error('Exception', tag: 'Mapbox3D', error: e);
      setState(() => _debugMessage = 'ERROR: $e');
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
            const SizedBox(height: 16),
            ...MapboxStyleType.values.map((style) {
              return ListTile(
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
                  setState(() => _debugMessage = 'Style changed to ${mapService.getStyleName(style)}');
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
            const SizedBox(height: 16),
            ..._pitchOptions.map((pitch) {
              return ListTile(
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

      AppLogger.debug('Dialog alignment calculation', tag: 'MAP', data: {
        'screenY': screenCoordinate.y,
        'screenHeight': size.height,
        'normalizedY': normalizedY,
        'inMiddleThird': inMiddleThird,
      });

      // If marker is in middle third (0.33 to 0.67), show dialog at bottom
      Alignment alignment;
      if (inMiddleThird) {
        AppLogger.debug('Marker in middle third - showing dialog at bottom', tag: 'MAP');
        alignment = const Alignment(0.0, 0.6); // Position at bottom third
      } else {
        AppLogger.debug('Marker not in middle third - showing dialog centered', tag: 'MAP');
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
  Future<void> _calculateRouteTo(double destLat, double destLon) async {
    final locationAsync = ref.read(locationNotifierProvider);

    // Extract location from AsyncValue
    LocationData? location;
    locationAsync.whenData((data) {
      location = data;
    });

    if (location == null) {
      AppLogger.warning('Cannot calculate route - user location not available', tag: 'ROUTING');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to calculate route - location not available'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    AppLogger.map('Calculating multiple routes', data: {
      'from': '${location!.latitude},${location!.longitude}',
      'to': '$destLat,$destLon',
    });

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Calculating routes...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    final routingService = RoutingService();
    final routes = await routingService.calculateMultipleRoutes(
      startLat: location!.latitude,
      startLon: location!.longitude,
      endLat: destLat,
      endLon: destLon,
    );

    // Hide loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (routes == null || routes.isEmpty) {
      AppLogger.warning('Route calculation failed', tag: 'ROUTING');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to calculate routes'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Store current pitch and set to 10° BEFORE zooming to routes
    _pitchBeforeRouteCalculation = _currentPitch;
    if (_mapboxMap != null) {
      await _mapboxMap!.easeTo(
        CameraOptions(pitch: 10.0),
        MapAnimationOptions(duration: 500),
      );
      _currentPitch = 10.0;
    }

    // Set preview routes in state (to display on map)
    if (routes.length >= 2) {
      final fastest = routes.firstWhere((r) => r.type == RouteType.fastest);
      final safest = routes.where((r) => r.type == RouteType.safest).firstOrNull;
      final shortest = routes.where((r) => r.type == RouteType.shortest).firstOrNull;

      ref.read(searchProvider.notifier).setPreviewRoutes(
        fastest.points,
        safest?.points ?? shortest!.points, // Use safest or shortest as second route
        routes.length == 3 ? shortest?.points : null, // Add third route if we have 3
      );

      // Refresh markers to show preview routes on map
      _addMarkers();

      // Auto-zoom to fit all routes on screen (AFTER pitch is set)
      final allPoints = [
        ...fastest.points,
        if (safest != null) ...safest.points,
        if (shortest != null) ...shortest.points,
      ];
      await _fitRouteBounds(allPoints);
    }

    // Show route selection dialog
    if (mounted) {
      _showRouteSelectionDialog(routes);
    }
  }

  /// Show dialog to select between multiple routes
  void _showRouteSelectionDialog(List<RouteResult> routes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.05, // 5% from bottom
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 400, // Maximum width
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6), // 60% opacity
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: const Text(
                        'Choose Your Route',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    // Routes list
                    ...routes.map((route) {
                      // Determine icon, color, label based on route type
                      final IconData icon;
                      final Color color;
                      final String label;
                      final String description;

                      switch (route.type) {
                        case RouteType.fastest:
                          icon = Icons.directions_car;
                          color = Colors.red;
                          label = 'Fastest Route (car)';
                          description = 'Optimized for speed';
                          break;
                        case RouteType.safest:
                          icon = Icons.shield;
                          color = Colors.green;
                          label = 'Safest Route (bike)';
                          description = 'Prioritizes cycle lanes & quiet roads';
                          break;
                        case RouteType.shortest:
                          icon = Icons.directions_walk;
                          color = Colors.blue;
                          label = 'Walking Route (foot)';
                          description = 'Walking/pedestrian route';
                          break;
                      }

                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          // Clear preview routes before showing selected route
                          ref.read(searchProvider.notifier).clearPreviewRoutes();
                          _displaySelectedRoute(route);
                        },
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                          leading: Icon(icon, color: color, size: 28),
                          title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(description, style: const TextStyle(fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                '${route.distanceKm} km • ${route.durationMin} min',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    // Cancel button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            // Clear preview routes when canceling
                            ref.read(searchProvider.notifier).clearPreviewRoutes();
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
                          child: const Text('CANCEL', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Display the selected route on the map
  Future<void> _displaySelectedRoute(RouteResult route) async {
    // Store route in provider
    ref.read(searchProvider.notifier).setRoute(route.points);

    // Toggle POIs: OSM OFF, Community OFF, Hazards ON
    ref.read(mapProvider.notifier).setPOIVisibility(
      showOSM: false,
      showCommunity: false,
      showHazards: true,
    );

    // Activate navigation mode and set active route
    ref.read(navigationModeProvider.notifier).startRouteNavigation();
    setState(() {
      _activeRoute = route;
    });

    // Refresh map to show selected route and clear preview routes
    _addMarkers();

    // Restore previous pitch (pitch was already set to 10° before dialog)
    if (_mapboxMap != null && _pitchBeforeRouteCalculation != null) {
      await _mapboxMap!.easeTo(
        CameraOptions(pitch: _pitchBeforeRouteCalculation!),
        MapAnimationOptions(duration: 500),
      );
      _currentPitch = _pitchBeforeRouteCalculation!;
      _pitchBeforeRouteCalculation = null;
    }

    AppLogger.success('Route displayed', tag: 'ROUTING', data: {
      'type': route.type.name,
      'points': route.points.length,
      'distance': route.distanceKm,
      'duration': route.durationMin,
    });

    // Start turn-by-turn navigation automatically
    ref.read(navigationProvider.notifier).startNavigation(route);
    AppLogger.success('Turn-by-turn navigation started', tag: 'NAVIGATION');

    // Store current pitch and set navigation pitch (35° for better forward view)
    _pitchBeforeNavigation = _currentPitch;
    const navigationPitch = 35.0;
    _currentPitch = navigationPitch;

    // Zoom to current GPS position for navigation view (close-up)
    final currentLocation = ref.read(locationNotifierProvider).value;
    if (currentLocation != null && _mapboxMap != null) {
      final navigationZoom = _calculateNavigationZoom(currentLocation.speed);
      final bearing = currentLocation.heading ?? 0.0;
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Route calculated (${routePoints.length} points)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
        null, // bearing
        _currentPitch, // pitch
      );

      // Fly to the calculated camera position
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: cameraOptions.center,
          zoom: cameraOptions.zoom,
          pitch: _currentPitch,
          bearing: cameraOptions.bearing,
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

  /// Build toggle button with count badge (matching 2D map style)
  Widget _buildToggleButton({
    required bool isActive,
    required IconData icon,
    required Color activeColor,
    required int count,
    required VoidCallback onPressed,
    required String tooltip,
    bool showFullCount = false,
    bool enabled = true,
  }) {
    return Tooltip(
      message: enabled ? tooltip : '$tooltip (disabled at zoom ≤ 11)',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FloatingActionButton(
            mini: true,
            backgroundColor: enabled
                ? (isActive ? activeColor : Colors.grey.shade300)
                : Colors.grey.shade200,
            foregroundColor: enabled ? Colors.white : Colors.grey.shade400,
            onPressed: enabled ? onPressed : null,
            heroTag: tooltip,
            child: Icon(icon),
          ),
          // Only show count when toggle is active AND count > 0
          if (isActive && count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                child: Center(
                  child: Text(
                    showFullCount ? count.toString() : (count > 99 ? '99+' : count.toString()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Handle marker tap - show appropriate dialog based on marker type
  void _handleMarkerTap(double lat, double lng) {
    AppLogger.map('Handling marker tap', data: {'lat': lat, 'lng': lng});

    // Try all three types of IDs
    final osmId = 'osm_${lat}_$lng';
    final communityId = 'community_${lat}_$lng';
    final warningId = 'warning_${lat}_$lng';

    if (_osmPoiById.containsKey(osmId)) {
      _showPOIDetails(_osmPoiById[osmId]!);
    } else if (_communityPoiById.containsKey(communityId)) {
      _showCommunityPOIDetails(_communityPoiById[communityId]!);
    } else if (_warningById.containsKey(warningId)) {
      _showWarningDetails(_warningById[warningId]!);
    } else {
      AppLogger.warning('Tapped annotation not found in POI maps', tag: 'MAP', data: {
        'lat': lat,
        'lng': lng,
        'osmId': osmId,
        'communityId': communityId,
        'warningId': warningId,
      });
    }
  }

  /// Show OSM POI details dialog
  void _showPOIDetails(OSMPOI poi) {
    final typeEmoji = POITypeConfig.getOSMPOIEmoji(poi.type);
    final typeLabel = POITypeConfig.getOSMPOILabel(poi.type);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
        title: Text(poi.name, style: const TextStyle(fontSize: 14)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                  Text(typeEmoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}', style: const TextStyle(fontSize: 12)),
              if (poi.description != null && poi.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.description!, style: const TextStyle(fontSize: 12)),
              ],
              if (poi.address != null && poi.address!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Address:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.address!, style: const TextStyle(fontSize: 12)),
              ],
              if (poi.phone != null && poi.phone!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Phone:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.phone!, style: const TextStyle(fontSize: 12)),
              ],
              if (poi.website != null && poi.website!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Website:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.website!, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _calculateRouteTo(poi.latitude, poi.longitude);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🚴‍♂️', style: TextStyle(fontSize: 14)),
                SizedBox(width: 4),
                Text('ROUTE TO', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Show warning details dialog
  void _showWarningDetails(CommunityWarning warning) {
    // Get warning type emoji and label
    final typeEmoji = POITypeConfig.getWarningEmoji(warning.type);
    final typeLabel = POITypeConfig.getWarningLabel(warning.type);

    // Get severity color
    final severityColors = {
      'low': AppColors.successGreen,
      'medium': Colors.yellow[700],
      'high': Colors.orange[700],
      'critical': AppColors.dangerRed,
    };
    final severityColor = severityColors[warning.severity] ?? Colors.yellow[700];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
        title: Text(warning.title, style: const TextStyle(fontSize: 14)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type with icon
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.urbanBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(typeEmoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 3),
                        Text(
                          typeLabel,
                          style: const TextStyle(
                            color: AppColors.surface,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Severity with colored badge
              Row(
                children: [
                  const Text('Severity: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: severityColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      warning.severity.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coordinates: ${warning.latitude.toStringAsFixed(6)}, ${warning.longitude.toStringAsFixed(6)}', style: const TextStyle(fontSize: 12)),
              if (warning.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(warning.description, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to edit screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HazardReportScreenWithLocation(
                    initialLatitude: warning.latitude,
                    initialLongitude: warning.longitude,
                    editingWarningId: warning.id,
                  ),
                ),
              ).then((_) {
                // Reload map data after edit
                if (mounted && _isMapReady) {
                  _loadAllPOIData();
                  _addMarkers();
                }
              });
            },
            child: const Text('EDIT', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (warning.id != null) {
                AppLogger.map('Deleting warning', data: {'id': warning.id});
                await ref.read(communityWarningsNotifierProvider.notifier).deleteWarning(warning.id!);
                // Reload map data
                if (mounted && _isMapReady) {
                  _loadAllPOIData();
                  _addMarkers();
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Show Community POI details dialog
  void _showCommunityPOIDetails(CyclingPOI poi) {
    final typeEmoji = POITypeConfig.getCommunityPOIEmoji(poi.type);
    final typeLabel = POITypeConfig.getCommunityPOILabel(poi.type);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
        title: Text(poi.name, style: const TextStyle(fontSize: 14)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                  Text(typeEmoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}', style: const TextStyle(fontSize: 12)),
              if (poi.description != null && poi.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.description!, style: const TextStyle(fontSize: 12)),
              ],
              if (poi.address != null && poi.address!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Address:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.address!, style: const TextStyle(fontSize: 12)),
              ],
              if (poi.phone != null && poi.phone!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Phone:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.phone!, style: const TextStyle(fontSize: 12)),
              ],
              if (poi.website != null && poi.website!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Website:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                Text(poi.website!, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _calculateRouteTo(poi.latitude, poi.longitude);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🚴‍♂️', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 4),
                    Text('ROUTE TO', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to edit screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => POIManagementScreenWithLocation(
                        initialLatitude: poi.latitude,
                        initialLongitude: poi.longitude,
                        editingPOIId: poi.id,
                      ),
                    ),
                  ).then((_) {
                    // Reload map data after edit
                    if (mounted && _isMapReady) {
                      _loadAllPOIData();
                      _addMarkers();
                    }
                  });
                },
                child: const Text('EDIT', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if (poi.id != null) {
                    AppLogger.map('Deleting POI', data: {'id': poi.id});
                    await ref.read(cyclingPOIsNotifierProvider.notifier).deletePOI(poi.id!);
                    // Reload map data
                    if (mounted && _isMapReady) {
                      _loadAllPOIData();
                      _addMarkers();
                    }
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('DELETE', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch location updates to keep camera centered
    final mapState = ref.watch(mapProvider);

    // Listen for POI data changes and refresh markers
    ref.listen<AsyncValue<List<dynamic>>>(osmPOIsNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        AppLogger.debug('OSM POIs updated, refreshing markers', tag: 'MAP');
        _addMarkers();
      }
    });

    ref.listen<AsyncValue<List<dynamic>>>(communityWarningsBoundsNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        AppLogger.debug('Warnings updated, refreshing markers', tag: 'MAP');
        _addMarkers();
      }
    });

    ref.listen<AsyncValue<List<dynamic>>>(cyclingPOIsBoundsNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        AppLogger.debug('Community POIs updated, refreshing markers', tag: 'MAP');
        _addMarkers();
      }
    });

    // Listen for map state changes (toggle buttons) and refresh markers INSTANTLY
    ref.listen<MapState>(mapProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        if (previous?.showOSMPOIs != next.showOSMPOIs ||
            previous?.showPOIs != next.showPOIs ||
            previous?.showWarnings != next.showWarnings) {
          AppLogger.debug('Map toggles changed, instantly refreshing markers', tag: 'MAP');
          _addMarkers(); // This is already instant - no delay
        }
      }
    });

    // Listen for compass changes to rotate the map (with toggle + threshold)
    // Compass listener removed - navigation mode uses GPS-based rotation instead

    // Listen for location changes to update user marker
    ref.listen(locationNotifierProvider, (previous, next) {
      AppLogger.debug('Location listener triggered', tag: 'MAP', data: {
        'isMapReady': _isMapReady,
        'hasAnnotationManager': _pointAnnotationManager != null,
      });
      if (_isMapReady && _pointAnnotationManager != null) {
        next.whenData((location) {
          if (location != null) {
            AppLogger.debug('Location updated, refreshing user marker', tag: 'MAP');
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
          ),
        );
      }
    });

    // Use cached initial camera or default
    final initialCamera = _initialCamera ?? _getDefaultCamera();

    return Scaffold(
      body: Stack(
        children: [
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
              cameraOptions: initialCamera,
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
              top: MediaQuery.of(context).padding.top + 96, // 16 + 80
              right: 16,
              child: Column(
                children: [
                  // Check zoom level - disable toggles if zoom <= 11
                  Builder(
                    builder: (context) {
                      final togglesEnabled = _currentZoom > 11.0;

                      return Column(
                        children: [
                          // OSM POI toggle
                          _buildToggleButton(
                            isActive: mapState.showOSMPOIs,
                            icon: Icons.public,
                            activeColor: Colors.blue,
                            count: ref.watch(osmPOIsNotifierProvider).value?.length ?? 0,
                            showFullCount: true,
                            enabled: togglesEnabled,
                            onPressed: () {
                              AppLogger.map('OSM POI toggle pressed');
                              final wasOff = !mapState.showOSMPOIs;
                              ref.read(mapProvider.notifier).toggleOSMPOIs();
                              if (wasOff) {
                                _loadOSMPOIsIfNeeded();
                              }
                            },
                            tooltip: 'Toggle OSM POIs',
                          ),
                          const SizedBox(height: 12),
                          // Community POI toggle
                          _buildToggleButton(
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
                          const SizedBox(height: 12),
                          // Warning toggle
                          _buildToggleButton(
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
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 4),

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
                  const SizedBox(height: 4),

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

                        // Auto-turn OFF all POI toggles if zooming to <= 11
                        if (newZoom <= 11.0) {
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
                          AppLogger.map('Auto-disabled all POI toggles at zoom <= 11');
                        }

                        setState(() {
                          _currentZoom = newZoom;
                        });
                      }
                    },
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),

            // Bottom-left controls: compass, center, reload
            Positioned(
              bottom: 16,
              left: 16,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Navigation mode toggle button
                  Consumer(
                    builder: (context, ref, child) {
                      final navState = ref.watch(navigationModeProvider);
                      final isNavigationMode = navState.mode == NavMode.navigation;

                      return FloatingActionButton(
                        mini: true,
                        heroTag: 'navigation_mode_toggle',
                        onPressed: () {
                          ref.read(navigationModeProvider.notifier).toggleMode();
                        },
                        backgroundColor: isNavigationMode ? Colors.purple : Colors.grey.shade300,
                        foregroundColor: isNavigationMode ? Colors.white : Colors.grey.shade600,
                        tooltip: isNavigationMode ? 'Exit Navigation Mode' : 'Enter Navigation Mode',
                        child: Icon(isNavigationMode ? Icons.navigation : Icons.navigation_outlined),
                      );
                    },
                  ),
                  const SizedBox(height: 8), // Match zoom spacing
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
                  const SizedBox(height: 8), // Match zoom spacing
                  // Reload POIs button
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
                  const SizedBox(height: 8),
                  // iOS Native Navigation Test Button (Phase 1, Step 1.2)
                  if (Platform.isIOS)
                    FloatingActionButton(
                      mini: true,
                      heroTag: 'test_ios_nav',
                      onPressed: () async {
                        AppLogger.map('Testing iOS native navigation with real route data');

                        // Check if we have an active route
                        if (_activeRoute == null) {
                          AppLogger.warning('No route available - please calculate a route first');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please calculate a route first (tap a POI → Calculate Route)'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                          return;
                        }

                        AppLogger.map('Using active route', data: {
                          'type': _activeRoute!.type.toString(),
                          'points': _activeRoute!.points.length,
                          'distance': _activeRoute!.distanceKm,
                          'duration': _activeRoute!.durationMin,
                        });

                        final navService = IOSNavigationService();

                        try {
                          await navService.startNavigation(
                            routePoints: _activeRoute!.points,
                            destinationName: 'Route Destination (${_activeRoute!.distanceKm}km)',
                          );
                        } catch (e) {
                          AppLogger.error('Navigation test failed', error: e);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Navigation failed: $e'),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      },
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      tooltip: 'Test iOS Navigation (Step 1.2)',
                      child: const Icon(Icons.navigation),
                    ),
                  const SizedBox(height: 8),
                  // Navigation controls (End + Mute buttons)
                  NavigationControls(
                    onNavigationEnded: () async {
                      setState(() {
                        _activeRoute = null;
                      });
                      // Clear route from search provider to remove from map
                      ref.read(searchProvider.notifier).clearRoute();
                      // Refresh markers to remove route polyline
                      _addMarkers();

                      // Restore pitch to previous value (only in 3D mode)
                      if (_mapboxMap != null && _pitchBeforeNavigation != null) {
                        await _mapboxMap!.easeTo(
                          CameraOptions(pitch: _pitchBeforeNavigation!),
                          MapAnimationOptions(duration: 500),
                        );
                        _currentPitch = _pitchBeforeNavigation!;
                        AppLogger.debug('Restored pitch after navigation', tag: 'NAVIGATION', data: {
                          'pitch': '${_pitchBeforeNavigation!}°',
                        });
                        _pitchBeforeNavigation = null;
                      }

                      AppLogger.success('Navigation ended, route cleared', tag: 'NAVIGATION');
                    },
                  ),
                ],
              ),
            ),

            // Bottom-right controls: tiles selector, pitch selector, 2D/3D switch
            Positioned(
              bottom: 16,
              right: 16,
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
                  const SizedBox(height: 8), // Match zoom spacing
                  // Pitch selector button
                  FloatingActionButton(
                    mini: true, // Match zoom button size
                    heroTag: 'pitch_selector_button',
                    onPressed: _showPitchPicker,
                    backgroundColor: Colors.deepPurple,
                    tooltip: 'Change Pitch: ${_currentPitch.toInt()}°',
                    child: Text('${_currentPitch.toInt()}°', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8), // Match zoom spacing
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
            ),
          ],

          // Search button (top-left, yellow) - rendered on top
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 96, // 16 + 80
              left: 16,
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
              onResultTap: (lat, lon) async {
                AppLogger.map('Search result tapped - navigating to location', data: {
                  'lat': lat,
                  'lon': lon,
                });
                // Set selected location to show marker
                ref.read(searchProvider.notifier).setSelectedLocation(lat, lon, 'Search Result');

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

          // Turn-by-turn navigation card overlay
          const NavigationCard(),

          // Debug overlay - on top of everything
          const DebugOverlay(),
        ],
      ),
    );
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

    // TEMPORARY: Enable built-in location component for testing with 3D puck
    try {
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: true, // TESTING: Enable default Mapbox 3D location puck
        puckBearingEnabled: true, // Show direction arrow
        pulsingEnabled: true, // Add pulsing effect for better visibility
        locationPuck: LocationPuck(
          locationPuck3D: LocationPuck3D(
            // Using Duck model - simple and easy to see direction
            modelUri: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Duck/glTF-Embedded/Duck.gltf",
            modelScale: [10.0, 10.0, 10.0], // 10x scale for visibility
            modelRotation: [0.0, 0.0, -90.0], // Rotate -90° to correct direction (beak was pointing right)
          ),
        ),
      ));
      AppLogger.success('Built-in 3D location puck ENABLED (10x scale) for testing', tag: 'MAP');
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
    final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
    final currentData = ref.read(osmPOIsNotifierProvider).value;

    if (currentData == null || currentData.isEmpty) {
      AppLogger.map('OSM POIs: No data, loading...');

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

        await osmPOIsNotifier.loadPOIsInBackground(bounds);
        _addMarkers();
      } catch (e) {
        AppLogger.error('Failed to load OSM POIs', error: e);
      }
    } else {
      AppLogger.map('OSM POIs: Data exists (${currentData.length} items), showing without reload');
      _addMarkers();
    }
  }

  /// Load Community POIs only if needed (cache empty)
  void _loadCommunityPOIsIfNeeded() async {
    final communityPOIsNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
    final currentData = ref.read(cyclingPOIsBoundsNotifierProvider).value;

    if (currentData == null || currentData.isEmpty) {
      AppLogger.map('Community POIs: No data, loading...');

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

        await communityPOIsNotifier.loadPOIsInBackground(bounds);
        _addMarkers();
      } catch (e) {
        AppLogger.error('Failed to load Community POIs', error: e);
      }
    } else {
      AppLogger.map('Community POIs: Data exists (${currentData.length} items), showing without reload');
      _addMarkers();
    }
  }

  /// Load Warnings only if needed (cache empty)
  void _loadWarningsIfNeeded() async {
    final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
    final currentData = ref.read(communityWarningsBoundsNotifierProvider).value;

    if (currentData == null || currentData.isEmpty) {
      AppLogger.map('Warnings: No data, loading...');

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

        await warningsNotifier.loadWarningsInBackground(bounds);
        _addMarkers();
      } catch (e) {
        AppLogger.error('Failed to load Warnings', error: e);
      }
    } else {
      AppLogger.map('Warnings: Data exists (${currentData.length} items), showing without reload');
      _addMarkers();
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

        // Check if camera moved significantly
        if (_lastCameraCenter != null && _lastCameraZoom != null) {
          final latDiff = (currentCenter.coordinates.lat - _lastCameraCenter!.coordinates.lat).abs();
          final lngDiff = (currentCenter.coordinates.lng - _lastCameraCenter!.coordinates.lng).abs();
          final zoomDiff = (currentZoom - _lastCameraZoom!).abs();

          // Trigger reload if moved more than ~100m or zoomed
          if (latDiff > 0.001 || lngDiff > 0.001 || zoomDiff > 0.5) {
            AppLogger.debug('Camera moved, triggering debounced reload', tag: 'MAP');
            _lastCameraCenter = currentCenter;
            _lastCameraZoom = currentZoom;
            _onCameraChanged();
          }
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

    // Add user location marker (custom, matching 2D map style)
    await _addUserLocationMarker();

    // Add all POI markers as emoji icons
    await _addOSMPOIsAsIcons(mapState);
    await _addCommunityPOIsAsIcons(mapState);
    await _addWarningsAsIcons(mapState);

    // Add route hazards during turn-by-turn navigation
    await _addRouteHazards();

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
    final layersToRemove = ['route-layer', 'preview-fastest-layer', 'preview-safest-layer', 'preview-shortest-layer'];
    final sourcesToRemove = ['route-source', 'preview-fastest-source', 'preview-safest-source', 'preview-shortest-source'];

    // Step 1: Remove all layers
    for (final layer in layersToRemove) {
      try {
        await _mapboxMap!.style.removeStyleLayer(layer);
        AppLogger.debug('Removed layer: $layer', tag: 'MAP');
      } catch (e) {
        // Layer doesn't exist, that's fine
      }
    }

    // Wait for layer removals to complete
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 2: Remove all sources (only after layers are removed)
    for (final source in sourcesToRemove) {
      try {
        await _mapboxMap!.style.removeStyleSource(source);
        AppLogger.debug('Removed source: $source', tag: 'MAP');
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

    // Use navigation route if active, otherwise use selected route
    List<latlong.LatLng>? routeToRender;
    bool isNavigating = false;
    Map<String, dynamic>? pathDetails;

    if (turnByTurnNavState.isNavigating && turnByTurnNavState.activeRoute != null) {
      routeToRender = turnByTurnNavState.activeRoute!.points;
      pathDetails = turnByTurnNavState.activeRoute!.pathDetails;
      isNavigating = true;
      AppLogger.debug('Rendering navigation route (surface-colored)', tag: 'MAP', data: {
        'points': routeToRender.length,
        'hasSurfaceData': pathDetails?.containsKey('surface') ?? false,
      });
    } else if (routePoints != null && routePoints.isNotEmpty) {
      routeToRender = routePoints;
      isNavigating = false;
      AppLogger.debug('Rendering selected route (green)', tag: 'MAP', data: {
        'points': routeToRender.length,
      });
    } else {
      return; // No route to render
    }

    try {
      // During navigation with surface data, render color-coded segments
      if (isNavigating && pathDetails != null && pathDetails.containsKey('surface')) {
        final segments = RouteSurfaceHelper.createSurfaceSegments(routeToRender, pathDetails);

        AppLogger.debug('Rendering ${segments.length} surface segments', tag: 'MAP');

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

          // Create line layer with surface color
          final lineLayer = LineLayer(
            id: 'route-layer-$i',
            sourceId: 'route-source-$i',
            lineColor: segment.color.value,
            lineWidth: 6.0,
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

      // Create point annotations for each warning
      for (final marker in warningMarkers) {
        final pointAnnotation = PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(
              marker.position.longitude,
              marker.position.latitude,
            ),
          ),
          iconImage: '⚠️', // Warning emoji
          iconSize: 1.5,
          iconAnchor: IconAnchor.BOTTOM,
        );

        await _pointAnnotationManager?.create(pointAnnotation);
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
    List<PointAnnotationOptions> pointOptions = [];

    AppLogger.debug('Adding OSM POIs as icons', tag: 'MAP', data: {'count': osmPOIs.length});
    for (var poi in osmPOIs) {
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

  // ============================================================================
  // NAVIGATION MODE METHODS (GPS-based rotation, auto-center, breadcrumbs)
  // ============================================================================

  /// Handle GPS location changes for navigation mode
  void _handleGPSLocationChange(LocationData location) async {
    AppLogger.debug('GPS location changed', tag: 'GPS', data: {
      'lat': location.latitude.toStringAsFixed(6),
      'lng': location.longitude.toStringAsFixed(6),
      'speed': '${((location.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h',
    });

    if (!_isMapReady || _mapboxMap == null) {
      AppLogger.warning('Map not ready, skipping GPS update', tag: 'GPS');
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
      _addMarkers(); // Update user marker position
      return; // Skip regular navigation mode camera (turn-by-turn takes priority)
    }

    // Auto-center logic (threshold: navigation 3m, exploration 25m)
    if (_originalGPSReference != null) {
      final distance = _calculateDistance(
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
          final targetZoom = _calculateNavigationZoom(location.speed);
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

    // Update marker
    _addMarkers();
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
      final distance = _calculateDistance(
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

    final totalDistance = _calculateDistance(
      start.latitude, start.longitude,
      end.latitude, end.longitude,
    );

    // Need at least 8m total movement (slightly more than GPS accuracy)
    if (totalDistance < 8) return null;

    final bearing = _calculateBearing(start, end);

    // Smooth bearing with last value (70% new, 30% old) - 3x more responsive
    if (_lastNavigationBearing != null) {
      final diff = (bearing - _lastNavigationBearing!).abs();
      if (diff < 180) {
        return bearing * 0.7 + _lastNavigationBearing! * 0.3;
      }
    }

    return bearing;
  }

  /// Calculate dynamic zoom based on speed (navigation mode)
  /// Optimized for walking/biking with 0.5 zoom steps
  double _calculateNavigationZoom(double? speedMps) {
    if (speedMps == null || speedMps < 0.28) return 19.0; // Stationary (< 1 km/h) - closer view
    if (speedMps < 1.39) return 18.5;  // 1-5 km/h (walking) - closer view
    if (speedMps < 2.78) return 18.0;  // 5-10 km/h (slow biking) - closer view
    if (speedMps < 4.17) return 17.5;  // 10-15 km/h (normal biking) - closer view
    if (speedMps < 5.56) return 17.0;  // 15-20 km/h (fast biking) - closer view
    if (speedMps < 6.94) return 16.5;  // 20-25 km/h (very fast) - closer view
    if (speedMps < 8.33) return 16.0;  // 25-30 km/h (racing) - closer view
    if (speedMps < 11.11) return 15.5; // 30-40 km/h (electric bike) - closer view
    return 15.0;                       // 40+ km/h (crazy fast!) - closer view
  }

  /// Handle camera auto-follow for turn-by-turn navigation
  /// Positions user at 3/4 from top of screen for better forward view
  Future<void> _handleTurnByTurnCameraFollow(LocationData location) async {
    if (_mapboxMap == null) return;

    // Calculate target zoom based on speed
    final targetZoom = _calculateNavigationZoom(location.speed);

    // Calculate bearing from travel direction (breadcrumbs) - matches 2D behavior
    // NOTE: Do NOT use location.heading for map rotation, only for marker arrow
    final bearing = _calculateTravelDirection();

    // Position user at 3/4 from top (offset camera northward)
    // This requires calculating a point offset in the direction of travel
    final screenHeight = MediaQuery.of(context).size.height;
    final offsetPixels = screenHeight / 4; // Offset by 1/4 of screen height

    AppLogger.debug('Turn-by-turn camera update', tag: 'CAMERA', data: {
      'speed': '${((location.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h',
      'zoom': targetZoom.toStringAsFixed(1),
      'heading': location.heading?.toStringAsFixed(0) ?? 'null',
      'bearing': bearing?.toStringAsFixed(0) ?? 'null',
      'offset': '${offsetPixels.toStringAsFixed(0)}px',
      'pitch': _currentPitch.toStringAsFixed(0),
    });

    // Camera target is user position (marker will appear at 3/4 from top due to padding)
    await _mapboxMap!.easeTo(
      CameraOptions(
        center: Point(coordinates: Position(location.longitude, location.latitude)),
        zoom: targetZoom,
        bearing: bearing ?? 0, // Positive bearing: direction at top of screen
        pitch: _currentPitch,
        // Note: Mapbox doesn't support anchor offset directly, so we use padding
        padding: MbxEdgeInsets(
          top: offsetPixels,
          left: 0,
          bottom: 0,
          right: 0,
        ),
      ),
      MapAnimationOptions(duration: 500), // Smooth 500ms animation
    );

    AppLogger.debug('Turn-by-turn camera follow', tag: 'NAVIGATION', data: {
      'zoom': targetZoom.toStringAsFixed(1),
      'bearing': bearing?.toStringAsFixed(1) ?? 'none',
      'speed': '${(location.speed ?? 0) * 3.6}km/h',
    });
  }

  /// Calculate bearing between two points (0-360°, 0=North, 90=East)
  double _calculateBearing(latlong.LatLng start, latlong.LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final dLon = (end.longitude - start.longitude) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
              math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Calculate distance between two GPS coordinates in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(lat1 * math.pi / 180) *
              math.cos(lat2 * math.pi / 180) *
              math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }


  /// Stop navigation and clear route
  void _stopNavigation() {
    // Clear route from provider
    ref.read(searchProvider.notifier).clearRoute();

    // Exit navigation mode
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
    _addMarkers();

    AppLogger.map('Navigation stopped - route cleared from map');
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