import 'dart:async';
import 'dart:convert';
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
import '../services/map_service.dart';
import '../services/routing_service.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/app_logger.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
import '../widgets/search_bar_widget.dart';
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

  // Compass rotation state
  bool _compassRotationEnabled = false;
  double? _lastBearing;
  static const double _compassThreshold = 5.0; // Only rotate if change > 5°

  // Pitch angle state
  double _currentPitch = 60.0; // Default pitch
  static const List<double> _pitchOptions = [10.0, 35.0, 60.0, 85.0];

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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...MapboxStyleType.values.map((style) {
              return ListTile(
                leading: Icon(
                  _getStyleIcon(style),
                  color: currentStyle == style ? Colors.green : Colors.grey,
                ),
                title: Text(mapService.getStyleName(style)),
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._pitchOptions.map((pitch) {
              return ListTile(
                leading: Icon(
                  Icons.height,
                  color: _currentPitch == pitch ? Colors.deepPurple : Colors.grey,
                ),
                title: Text('${pitch.toInt()}°'),
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
      case MapboxStyleType.satelliteStreets:
        return Icons.satellite_alt;
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

    // Toggle all POIs ON (OSM, Community, Hazards)
    ref.read(mapProvider.notifier).setPOIVisibility(
      showOSM: true,
      showCommunity: true,
      showHazards: true,
    );

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
                  titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  title: const Text('Possible Actions for this Location', style: TextStyle(fontSize: 16)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Debug info
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DEBUG: Y=${alignmentData['screenY']?.toStringAsFixed(1)} / ${alignmentData['screenHeight']?.toStringAsFixed(1)} = ${alignmentData['normalizedY']?.toStringAsFixed(3)}, Middle=${alignmentData['inMiddleThird']}, Pos=${inMiddleThird ? "60%" : "28%"}',
                          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                        leading: Icon(Icons.add_location, color: Colors.green[700]),
                        title: const Text('Add Community here', style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          _showAddPOIDialog(lat, lng);
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                        leading: Icon(Icons.warning, color: Colors.orange[700]),
                        title: const Text('Report Hazard here', style: TextStyle(fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          _showReportHazardDialog(lat, lng);
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
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
                  titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  title: const Text('Possible Actions for this Location', style: TextStyle(fontSize: 16)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Debug info
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DEBUG: Y=${alignmentData['screenY']?.toStringAsFixed(1)} / ${alignmentData['screenHeight']?.toStringAsFixed(1)} = ${alignmentData['normalizedY']?.toStringAsFixed(3)}, Middle=${alignmentData['inMiddleThird']}, Pos=${inMiddleThird ? "60%" : "28%"}',
                          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
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

    AppLogger.map('Calculating route', data: {
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
              Text('Calculating route...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    final routingService = RoutingService();
    final routePoints = await routingService.calculateRoute(
      startLat: location!.latitude,
      startLon: location!.longitude,
      endLat: destLat,
      endLon: destLon,
    );

    // Hide loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (routePoints == null || routePoints.isEmpty) {
      AppLogger.warning('Route calculation failed', tag: 'ROUTING');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to calculate route'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Store route in provider
    ref.read(searchProvider.notifier).setRoute(routePoints);

    // Toggle POIs: OSM OFF, Community OFF, Hazards ON
    ref.read(mapProvider.notifier).setPOIVisibility(
      showOSM: false,
      showCommunity: false,
      showHazards: true,
    );

    // Zoom map to fit the entire route
    await _fitRouteBounds(routePoints);

    AppLogger.success('Route calculated and displayed', tag: 'ROUTING', data: {
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
    if (routePoints.isEmpty || _mapboxMap == null) return;

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
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FloatingActionButton(
            mini: true,
            backgroundColor: isActive ? activeColor : Colors.grey.shade300,
            foregroundColor: Colors.white,
            onPressed: onPressed,
            heroTag: tooltip,
            child: Icon(icon),
          ),
          if (count > 0)
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
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
        title: Text(poi.name, style: const TextStyle(fontSize: 16)),
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
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
        title: Text(warning.title, style: const TextStyle(fontSize: 16)),
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
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
        title: Text(poi.name, style: const TextStyle(fontSize: 16)),
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
    ref.listen<double?>(compassNotifierProvider, (previous, next) {
      if (!_compassRotationEnabled || next == null || _mapboxMap == null || !_isMapReady) {
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

      // Rotate map based on compass heading, keeping pitch locked at 80°
      _mapboxMap!.setCamera(CameraOptions(
        bearing: -next,
        pitch: _currentPitch, // Maintain pitch angle
      ));
      AppLogger.debug('Map rotated to bearing', tag: 'Mapbox3D', data: {
        'bearing': -next,
        'threshold': _compassThreshold,
      });

      // Update user location marker with new heading
      _addMarkers();
    });

    // Listen for location changes to update user marker
    ref.listen(locationNotifierProvider, (previous, next) {
      if (_isMapReady && _pointAnnotationManager != null) {
        next.whenData((location) {
          if (location != null) {
            AppLogger.debug('Location updated, refreshing user marker', tag: 'MAP');
            _addMarkers();
          }
        });
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
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Column(
                children: [
                  // OSM POI toggle
                  _buildToggleButton(
                    isActive: mapState.showOSMPOIs,
                    icon: Icons.public,
                    activeColor: Colors.blue,
                    count: ref.watch(osmPOIsNotifierProvider).value?.length ?? 0,
                    showFullCount: true,
                    onPressed: () => ref.read(mapProvider.notifier).toggleOSMPOIs(),
                    tooltip: 'Toggle OSM POIs',
                  ),
                  const SizedBox(height: 12),
                  // Community POI toggle
                  _buildToggleButton(
                    isActive: mapState.showPOIs,
                    icon: Icons.location_on,
                    activeColor: Colors.green,
                    count: ref.watch(cyclingPOIsBoundsNotifierProvider).value?.length ?? 0,
                    onPressed: () => ref.read(mapProvider.notifier).togglePOIs(),
                    tooltip: 'Toggle Community POIs',
                  ),
                  const SizedBox(height: 12),
                  // Warning toggle
                  _buildToggleButton(
                    isActive: mapState.showWarnings,
                    icon: Icons.warning,
                    activeColor: Colors.orange,
                    count: ref.watch(communityWarningsBoundsNotifierProvider).value?.length ?? 0,
                    onPressed: () => ref.read(mapProvider.notifier).toggleWarnings(),
                    tooltip: 'Toggle Warnings',
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
                        _mapboxMap?.setCamera(CameraOptions(
                          zoom: currentZoom + 1,
                          pitch: _currentPitch, // Maintain pitch angle
                        ));
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  // Zoom out
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'zoom_out_3d',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    onPressed: () async {
                      final currentZoom = await _mapboxMap?.getCameraState().then((state) => state.zoom);
                      if (currentZoom != null) {
                        _mapboxMap?.setCamera(CameraOptions(
                          zoom: currentZoom - 1,
                          pitch: _currentPitch, // Maintain pitch angle
                        ));
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
                  // Compass rotation toggle button
                  FloatingActionButton(
                    mini: true, // Match zoom button size
                    heroTag: 'compass_rotation_toggle',
                    onPressed: () {
                      setState(() {
                        _compassRotationEnabled = !_compassRotationEnabled;
                        if (!_compassRotationEnabled) {
                          // Reset map to north when disabling
                          _mapboxMap?.setCamera(CameraOptions(
                            bearing: 0,
                            pitch: _currentPitch,
                          ));
                          _lastBearing = null;
                        }
                      });
                      AppLogger.map('Compass rotation ${_compassRotationEnabled ? "enabled" : "disabled"}');
                    },
                    backgroundColor: _compassRotationEnabled ? Colors.purple : Colors.grey.shade300,
                    foregroundColor: _compassRotationEnabled ? Colors.white : Colors.grey.shade600,
                    tooltip: 'Toggle Compass Rotation',
                    child: Icon(_compassRotationEnabled ? Icons.explore : Icons.explore_off),
                  ),
                  const SizedBox(height: 8), // Match zoom spacing
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
              top: MediaQuery.of(context).padding.top + 16,
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

                // Toggle all POIs ON (OSM, Community, Hazards)
                ref.read(mapProvider.notifier).setPOIVisibility(
                  showOSM: true,
                  showCommunity: true,
                  showHazards: true,
                );

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
        ],
      ),
    );
  }

  /// Called when the Mapbox map is created and ready
  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    AppLogger.map('Mapbox map created');

    setState(() {
      _isMapReady = true;
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

    // Disable built-in location component - we'll use custom marker matching 2D map
    try {
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: false, // Disable to use custom marker
      ));
      AppLogger.success('Built-in location component disabled (using custom marker)', tag: 'MAP');
    } catch (e) {
      AppLogger.error('Failed to disable location component', error: e);
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

      final center = cameraState.center;
      final zoom = cameraState.zoom;

      // Calculate bounds based on zoom level
      // At zoom 15, roughly 0.01 degrees = ~1km
      final latDelta = 0.05 / (zoom / 10);
      final lngDelta = 0.05 / (zoom / 10);

      final south = center.coordinates.lat - latDelta;
      final north = center.coordinates.lat + latDelta;
      final west = center.coordinates.lng - lngDelta;
      final east = center.coordinates.lng + lngDelta;

      AppLogger.map('Loading POIs for bounds', data: {
        'south': south.toStringAsFixed(4),
        'north': north.toStringAsFixed(4),
        'west': west.toStringAsFixed(4),
        'east': east.toStringAsFixed(4),
        'zoom': zoom.toStringAsFixed(1),
      });

      // Load OSM POIs
      final osmNotifier = ref.read(osmPOIsNotifierProvider.notifier);
      await osmNotifier.loadPOIsWithBounds(BoundingBox(
        south: south,
        west: west,
        north: north,
        east: east,
      ));

      final bounds = BoundingBox(
        south: south,
        west: west,
        north: north,
        east: east,
      );

      // Load Community Warnings
      final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
      await warningsNotifier.loadWarningsWithBounds(bounds);

      // Load Community POIs
      final communityPOIsNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
      await communityPOIsNotifier.loadPOIsWithBounds(bounds);

      AppLogger.success('All POI data loaded', tag: 'MAP');
    } catch (e) {
      AppLogger.error('Failed to load POI data', error: e);
    }

    AppLogger.separator();
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
      canvas.translate(size / 2, size / 2);
      canvas.rotate(heading * 3.14159 / 180); // Convert to radians
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
      // Draw my_location icon (concentric circles)
      final iconPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Outer ring
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        iconSize / 3,
        iconPaint,
      );

      // Center dot
      final dotPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        iconSize / 6,
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

    // Add search result marker if available
    await _addSearchResultMarker();

    // Add route polyline if available
    await _addRoutePolyline();
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
    final searchState = ref.read(searchProvider);
    final routePoints = searchState.routePoints;

    if (routePoints == null || routePoints.isEmpty) {
      // Clear any existing route layer
      try {
        await _mapboxMap?.style.removeStyleLayer('route-layer');
        await _mapboxMap?.style.removeStyleSource('route-source');
      } catch (e) {
        // Layer/source doesn't exist, that's fine
      }
      return;
    }

    AppLogger.debug('Adding route polyline', tag: 'MAP', data: {
      'points': routePoints.length,
    });

    try {
      // Remove existing route layer and source if they exist
      try {
        await _mapboxMap?.style.removeStyleLayer('route-layer');
        await _mapboxMap?.style.removeStyleSource('route-source');
      } catch (e) {
        // Layer/source doesn't exist yet
      }

      // Convert LatLng points to Mapbox Position list
      final positions = routePoints.map((point) =>
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
        lineColor: 0xFF85a78b,
        lineWidth: 4.0,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
      );

      // Add layer to map (below POI labels if they exist)
      await _mapboxMap?.style.addLayer(lineLayer);

      AppLogger.success('Route polyline added', tag: 'MAP');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add route polyline', tag: 'MAP', error: e, stackTrace: stackTrace);
    }
  }

  /// Add custom user location marker matching 2D map style
  Future<void> _addUserLocationMarker() async {
    final locationAsync = ref.read(locationNotifierProvider);
    final compassHeading = ref.read(compassNotifierProvider);

    await locationAsync.whenData((location) async {
      if (location != null) {
        // Use compass heading if available, otherwise GPS heading
        final heading = compassHeading ?? location.heading;

        AppLogger.debug('Adding user location marker', tag: 'MAP', data: {
          'lat': location.latitude,
          'lng': location.longitude,
          'heading': heading,
        });

        // Create custom location icon matching 2D map
        final userIcon = await _createUserLocationIcon(heading: heading);

        final userMarker = PointAnnotationOptions(
          geometry: Point(coordinates: Position(location.longitude, location.latitude)),
          image: userIcon,
          iconSize: 1.8, // Match 2D map ratio (12:10 = 1.2, so 1.5 * 1.2 = 1.8)
        );

        await _pointAnnotationManager!.create(userMarker);
        AppLogger.success('User location marker added', tag: 'MAP');
      }
    });
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