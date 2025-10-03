import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../providers/compass_provider.dart';
import '../services/map_service.dart';
import '../utils/app_logger.dart';
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
          final camera = location != null
              ? CameraOptions(
                  center: Point(
                    coordinates: Position(
                      location.longitude,
                      location.latitude,
                    ),
                  ),
                  zoom: 15.0,
                  pitch: 60.0,
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
    return CameraOptions(
      center: Point(
        coordinates: Position(2.3522, 48.8566), // Paris
      ),
      zoom: 15.0,
      pitch: 60.0,
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
                zoom: 15.0,
                pitch: 60.0,
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

  IconData _getStyleIcon(MapboxStyleType style) {
    switch (style) {
      case MapboxStyleType.streets:
        return Icons.map;
      case MapboxStyleType.outdoors:
        return Icons.terrain;
      case MapboxStyleType.satelliteStreets:
        return Icons.satellite_alt;
    }
  }

  void _switchTo2DMap() {
    AppLogger.map('Switching to 2D map');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapScreen(),
      ),
    );
  }

  /// Handle long press on map to show context menu
  void _onMapLongPress(Point coordinates) {
    AppLogger.map('Map long-pressed', data: {
      'lat': coordinates.coordinates.lat,
      'lng': coordinates.coordinates.lng,
    });

    // Provide haptic feedback for mobile users
    HapticFeedback.mediumImpact();

    _showContextMenu(coordinates);
  }

  /// Show context menu for adding Community POI or reporting hazard
  void _showContextMenu(Point coordinates) {
    final lat = coordinates.coordinates.lat.toDouble();
    final lng = coordinates.coordinates.lng.toDouble();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Map'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.add_location, color: Colors.green[700]),
              title: const Text('Add Community POI'),
              onTap: () {
                Navigator.pop(context);
                _showAddPOIDialog(lat, lng);
              },
            ),
            ListTile(
              leading: Icon(Icons.warning, color: Colors.orange[700]),
              title: const Text('Report Hazard'),
              onTap: () {
                Navigator.pop(context);
                _showReportHazardDialog(lat, lng);
              },
            ),
          ],
        ),
      ),
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

    AppLogger.map('Returned from POI screen, refreshing markers');
    if (mounted) {
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

    AppLogger.map('Returned from Warning screen, refreshing markers');
    if (mounted) {
      _addMarkers();
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

  @override
  Widget build(BuildContext context) {
    // Watch location updates to keep camera centered
    final locationAsync = ref.watch(locationNotifierProvider);
    final mapState = ref.watch(mapProvider);
    final compassHeading = ref.watch(compassNotifierProvider);

    // Listen for compass changes to rotate the map
    ref.listen<double?>(compassNotifierProvider, (previous, next) {
      if (next != null && _mapboxMap != null && _isMapReady) {
        // Rotate map based on compass heading
        _mapboxMap!.setCamera(CameraOptions(bearing: -next));
        AppLogger.debug('Map rotated to bearing', tag: 'Mapbox3D', data: {'bearing': -next});
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
                        _mapboxMap?.setCamera(CameraOptions(zoom: currentZoom + 1));
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
                        _mapboxMap?.setCamera(CameraOptions(zoom: currentZoom - 1));
                      }
                    },
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),

            // Floating action buttons in bottom-right (matching 2D layout)
            Positioned(
              bottom: 16,
              right: 16,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Style picker button
                  FloatingActionButton(
                    mini: false,
                    heroTag: 'style_picker_button',
                    onPressed: _showStylePicker,
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.layers),
                  ),
                  const SizedBox(height: 16),
                  // Switch to 2D button (matching 3D button style from 2D map)
                  FloatingActionButton(
                    mini: false,
                    heroTag: 'switch_to_2d_button',
                    onPressed: _switchTo2DMap,
                    backgroundColor: Colors.green,
                    tooltip: 'Switch to 2D Map',
                    child: const Icon(Icons.map),
                  ),
                  const SizedBox(height: 16),
                  // GPS center button (matching 2D map style)
                  FloatingActionButton(
                    mini: false,
                    heroTag: 'gps_center_button_3d',
                    onPressed: _centerOnUserLocation,
                    backgroundColor: AppColors.signalYellow,
                    foregroundColor: AppColors.urbanBlue,
                    child: const Icon(Icons.my_location),
                  ),
                ],
              ),
            ),
          ],
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

    // Enable location component to show user position with bearing arrow
    try {
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: true,
        pulsingEnabled: false, // Disable pulsing for cleaner arrow display
        showAccuracyRing: false,
        puckBearingEnabled: true, // Enable bearing/heading indicator
      ));
      AppLogger.success('Location component enabled with bearing arrow', tag: 'MAP');
    } catch (e) {
      AppLogger.error('Failed to enable location component', error: e);
    }

    // Initialize point annotation manager for markers
    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    _addMarkers();

    AppLogger.success('Mapbox map ready', tag: 'MAP');
  }

  /// Add POI and warning markers to the map
  Future<void> _addMarkers() async {
    if (_pointAnnotationManager == null) return;

    List<PointAnnotationOptions> annotationOptions = [];

    // Get POIs and warnings
    final pois = ref.read(osmPOIsNotifierProvider).value ?? [];
    final warnings = ref.read(communityWarningsNotifierProvider).value ?? [];

    // Add POI markers (green)
    for (var poi in pois) {
      annotationOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
          iconColor: Colors.green.value,
          iconSize: 1.0,
        ),
      );
    }

    // Add warning markers (red)
    for (var warning in warnings) {
      annotationOptions.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(warning.longitude, warning.latitude)),
          iconColor: Colors.red.value,
          iconSize: 1.2,
        ),
      );
    }

    if (annotationOptions.isNotEmpty) {
      await _pointAnnotationManager!.createMulti(annotationOptions);
      AppLogger.success('Added markers to 3D map', tag: 'MAP', data: {
        'count': annotationOptions.length,
      });
    }
  }
}