import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../services/map_service.dart';

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
    print('🗺️ iOS DEBUG [Mapbox3D]: initState called');
    // Move provider reading to initState to avoid modifying provider during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🗺️ iOS DEBUG [Mapbox3D]: PostFrameCallback - getting initial camera');
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
            print('✅ iOS DEBUG [Mapbox3D]: Initial camera set to ${location?.latitude}, ${location?.longitude}');

            // Auto-center on GPS after map is ready (wait 1s for map initialization)
            if (location != null) {
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && _mapboxMap != null) {
                  print('🎯 iOS DEBUG [Mapbox3D]: Auto-centering on GPS location');
                  _centerOnUserLocation();
                }
              });
            }
          }
        },
        loading: () {
          print('⏳ iOS DEBUG [Mapbox3D]: Location still loading, using default camera');
          if (mounted) {
            setState(() {
              _initialCamera = _getDefaultCamera();
            });
          }
        },
        error: (_, __) {
          print('❌ iOS DEBUG [Mapbox3D]: Location error, using default camera');
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
    print('🗺️ iOS DEBUG [Mapbox3D]: GPS button clicked');
    setState(() => _debugMessage = 'GPS button clicked...');

    if (_mapboxMap == null) {
      print('❌ iOS DEBUG [Mapbox3D]: Map not ready');
      setState(() => _debugMessage = 'ERROR: Map not ready');
      return;
    }

    try {
      setState(() => _debugMessage = 'Requesting location...');
      print('🗺️ iOS DEBUG [Mapbox3D]: Reading location from provider');

      final locationAsync = ref.read(locationNotifierProvider);

      locationAsync.when(
        data: (location) {
          if (location != null) {
            print('✅ iOS DEBUG [Mapbox3D]: Got location ${location.latitude}, ${location.longitude}');
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
            print('❌ iOS DEBUG [Mapbox3D]: Location is NULL');
            setState(() => _debugMessage = 'ERROR: Location is null (permission denied?)');
          }
        },
        loading: () {
          print('⏳ iOS DEBUG [Mapbox3D]: Location still loading');
          setState(() => _debugMessage = 'Location is loading...');
        },
        error: (error, _) {
          print('❌ iOS DEBUG [Mapbox3D]: Location error: $error');
          setState(() => _debugMessage = 'ERROR: $error');
        },
      );
    } catch (e) {
      print('❌ iOS DEBUG [Mapbox3D]: Exception: $e');
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
      case MapboxStyleType.outdoors:
        return Icons.terrain;
      case MapboxStyleType.streets:
        return Icons.map;
      case MapboxStyleType.satellite:
        return Icons.satellite;
      case MapboxStyleType.satelliteStreets:
        return Icons.satellite_alt;
      case MapboxStyleType.light:
        return Icons.wb_sunny;
      case MapboxStyleType.dark:
        return Icons.nights_stay;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch location updates to keep camera centered
    final locationAsync = ref.watch(locationNotifierProvider);
    final mapState = ref.watch(mapProvider);

    // Use cached initial camera or default
    final initialCamera = _initialCamera ?? _getDefaultCamera();

    return Scaffold(
      body: Stack(
        children: [
          // Mapbox Map Widget (Simplified)
          MapWidget(
            key: const ValueKey("mapboxWidgetSimple"),
            cameraOptions: initialCamera,
            styleUri: mapState.mapboxStyleUri,
            onMapCreated: _onMapCreated,
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
                  // Back to 2D button (matching 3D button position from 2D map)
                  FloatingActionButton(
                    mini: false,
                    heroTag: 'back_to_2d_button',
                    onPressed: () => Navigator.pop(context),
                    backgroundColor: AppColors.urbanBlue,
                    tooltip: 'Back to 2D Map',
                    child: const Icon(Icons.map),
                  ),
                  const SizedBox(height: 16),
                  // GPS center button (matching 2D map style)
                  FloatingActionButton(
                    mini: false,
                    heroTag: 'gps_center_button_3d',
                    onPressed: _centerOnUserLocation,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
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
    print('🗺️ Mapbox map created!');

    setState(() {
      _isMapReady = true;
    });

    // Initialize point annotation manager for markers
    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    _addMarkers();

    print('✅ Mapbox map ready!');
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
      print('✅ Added ${annotationOptions.length} markers to 3D map');
    }
  }
}