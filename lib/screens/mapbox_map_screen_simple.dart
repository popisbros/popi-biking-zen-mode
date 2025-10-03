import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../utils/app_logger.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
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
  CircleAnnotationManager? _circleAnnotationManager;
  dynamic _symbolAnnotationManager; // Use dynamic for web compatibility
  Timer? _debounceTimer;
  DateTime? _lastPOILoadTime;
  Timer? _cameraCheckTimer;
  Point? _lastCameraCenter;
  double? _lastCameraZoom;

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
          final camera = location != null
              ? CameraOptions(
                  center: Point(
                    coordinates: Position(
                      location.longitude,
                      location.latitude,
                    ),
                  ),
                  zoom: 15.0,
                  pitch: 70.0, // Locked 3D angle at 70°
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
        coordinates: Position(5.826000, 40.643944), // Custom default location
      ),
      zoom: 15.0,
      pitch: 70.0, // Locked 3D angle at 70°
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
                pitch: 70.0, // Locked 3D angle at 70°
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
        title: Text(poi.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(typeEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}'),
              if (poi.description != null && poi.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.description!),
              ],
              if (poi.address != null && poi.address!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Address:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.address!),
              ],
              if (poi.phone != null && poi.phone!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Phone:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.phone!),
              ],
              if (poi.website != null && poi.website!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Website:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.website!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
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
        title: Text(warning.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type with icon
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.urbanBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(typeEmoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 4),
                        Text(
                          typeLabel,
                          style: const TextStyle(
                            color: AppColors.surface,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Severity with colored badge
              Row(
                children: [
                  const Text('Severity: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: severityColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      warning.severity.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coordinates: ${warning.latitude.toStringAsFixed(6)}, ${warning.longitude.toStringAsFixed(6)}'),
              if (warning.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(warning.description),
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
            child: const Text('EDIT'),
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
            child: const Text('DELETE'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
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
        title: Text(poi.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(typeEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}'),
              if (poi.description != null && poi.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.description!),
              ],
              if (poi.address != null && poi.address!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Address:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.address!),
              ],
              if (poi.phone != null && poi.phone!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Phone:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.phone!),
              ],
              if (poi.website != null && poi.website!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Website:', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(poi.website!),
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
            child: const Text('EDIT'),
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
            child: const Text('DELETE'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
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

    // Watch POI data changes and rebuild markers
    final osmPOIs = ref.watch(osmPOIsNotifierProvider);
    final communityPOIs = ref.watch(cyclingPOIsBoundsNotifierProvider);
    final warnings = ref.watch(communityWarningsBoundsNotifierProvider);

    // Listen for POI data changes and refresh markers
    ref.listen<AsyncValue<List<dynamic>>>(osmPOIsNotifierProvider, (previous, next) {
      if (_isMapReady && _symbolAnnotationManager != null) {
        AppLogger.debug('OSM POIs updated, refreshing markers', tag: 'MAP');
        _addMarkers();
      }
    });

    ref.listen<AsyncValue<List<dynamic>>>(communityWarningsBoundsNotifierProvider, (previous, next) {
      if (_isMapReady && _symbolAnnotationManager != null) {
        AppLogger.debug('Warnings updated, refreshing markers', tag: 'MAP');
        _addMarkers();
      }
    });

    ref.listen<AsyncValue<List<dynamic>>>(cyclingPOIsBoundsNotifierProvider, (previous, next) {
      if (_isMapReady && _symbolAnnotationManager != null) {
        AppLogger.debug('Community POIs updated, refreshing markers', tag: 'MAP');
        _addMarkers();
      }
    });

    // Listen for map state changes (toggle buttons) and refresh markers INSTANTLY
    ref.listen<MapState>(mapProvider, (previous, next) {
      if (_isMapReady && _symbolAnnotationManager != null) {
        if (previous?.showOSMPOIs != next.showOSMPOIs ||
            previous?.showPOIs != next.showPOIs ||
            previous?.showWarnings != next.showWarnings) {
          AppLogger.debug('Map toggles changed, instantly refreshing markers', tag: 'MAP');
          _addMarkers(); // This is already instant - no delay
        }
      }
    });

    // Listen for compass changes to rotate the map
    ref.listen<double?>(compassNotifierProvider, (previous, next) {
      if (next != null && _mapboxMap != null && _isMapReady) {
        // Rotate map based on compass heading, keeping pitch locked at 70°
        _mapboxMap!.setCamera(CameraOptions(
          bearing: -next,
          pitch: 70.0, // Maintain locked 3D angle
        ));
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
                        _mapboxMap?.setCamera(CameraOptions(
                          zoom: currentZoom + 1,
                          pitch: 70.0, // Maintain locked 3D angle
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
                          pitch: 70.0, // Maintain locked 3D angle
                        ));
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
                  // Reload POIs button
                  FloatingActionButton(
                    mini: false,
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

    // Disable pitch gestures to lock the 3D angle at 70°
    try {
      await mapboxMap.gestures.updateSettings(GesturesSettings(
        pitchEnabled: false, // Lock pitch - user cannot tilt the map
      ));
      AppLogger.success('Pitch gestures disabled - locked at 70°', tag: 'MAP');
    } catch (e) {
      AppLogger.error('Failed to disable pitch gestures', error: e);
    }

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

    // Initialize symbol annotation manager for markers with emojis (not available on Web)
    if (!kIsWeb) {
      try {
        _symbolAnnotationManager = await mapboxMap.annotations.createSymbolAnnotationManager();
        AppLogger.success('Symbol annotation manager created', tag: 'MAP');

        // Add tap listener for symbol annotations
        _symbolAnnotationManager!.addOnSymbolAnnotationClickListener(_OnSymbolClickListener(
          onTap: _handleMarkerTap,
        ));
      } catch (e) {
        AppLogger.warning('Symbol annotations not supported on this platform', tag: 'MAP', error: e);
      }
    } else {
      AppLogger.warning('Symbol annotations not available on Web - using circle markers instead', tag: 'MAP');
      _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    }

    // Center on user location if available
    final locationState = ref.read(locationNotifierProvider);
    locationState.whenData((location) {
      if (location != null && mounted) {
        AppLogger.map('Centering map on user location at startup');
        mapboxMap.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(location.longitude, location.latitude),
            ),
            zoom: 15.0,
            pitch: 70.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    });

    // Load POI data initially
    await _loadAllPOIData();
    _lastPOILoadTime = DateTime.now(); // Track initial load time

    // Get initial camera state
    final initialState = await mapboxMap.getCameraState();
    _lastCameraCenter = initialState.center;
    _lastCameraZoom = initialState.zoom;

    // Add markers after data is loaded
    _addMarkers();

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
              zoom: 15.0,
              pitch: 70.0,
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

  /// Add POI and warning markers to the map using symbols (native) or circles (web)
  Future<void> _addMarkers() async {
    if (kIsWeb) {
      // Use circle markers for Web
      await _addCircleMarkers();
    } else {
      // Use symbol markers with emojis for native platforms
      await _addSymbolMarkers();
    }
  }

  /// Add markers using SymbolAnnotations with emojis (native platforms only)
  Future<void> _addSymbolMarkers() async {
    if (_symbolAnnotationManager == null) {
      AppLogger.warning('Symbol annotation manager not ready', tag: 'MAP');
      return;
    }

    // Clear existing markers first
    await _symbolAnnotationManager!.deleteAll();

    List<dynamic> symbolOptions = [];

    final mapState = ref.read(mapProvider);

    // Clear POI maps
    _osmPoiById.clear();
    _communityPoiById.clear();
    _warningById.clear();

    // Get OSM POIs (if enabled)
    if (mapState.showOSMPOIs) {
      final osmPOIs = ref.read(osmPOIsNotifierProvider).value ?? [];
      AppLogger.debug('Adding OSM POIs as symbols with emojis', tag: 'MAP', data: {'count': osmPOIs.length});
      for (var poi in osmPOIs) {
        final id = 'osm_${poi.latitude}_${poi.longitude}';
        _osmPoiById[id] = poi;
        final emoji = POITypeConfig.getOSMPOIEmoji(poi.type);
        symbolOptions.add({
          'geometry': Point(coordinates: Position(poi.longitude, poi.latitude)),
          'textField': emoji,
          'textSize': MarkerConfig.getRadiusForType(POIMarkerType.osmPOI),
          'textColor': Colors.black.value,
          'iconAllowOverlap': true,
          'textAllowOverlap': true,
        });
      }
    }

    // Get Community POIs (if enabled)
    if (mapState.showPOIs) {
      final communityPOIs = ref.read(cyclingPOIsBoundsNotifierProvider).value ?? [];
      AppLogger.debug('Adding Community POIs as symbols with emojis', tag: 'MAP', data: {'count': communityPOIs.length});
      for (var poi in communityPOIs) {
        final id = 'community_${poi.latitude}_${poi.longitude}';
        _communityPoiById[id] = poi;
        final emoji = POITypeConfig.getCommunityPOIEmoji(poi.type);
        symbolOptions.add({
          'geometry': Point(coordinates: Position(poi.longitude, poi.latitude)),
          'textField': emoji,
          'textSize': MarkerConfig.getRadiusForType(POIMarkerType.communityPOI),
          'textColor': Colors.black.value,
          'iconAllowOverlap': true,
          'textAllowOverlap': true,
        });
      }
    }

    // Get Warnings (if enabled)
    if (mapState.showWarnings) {
      final warnings = ref.read(communityWarningsBoundsNotifierProvider).value ?? [];
      AppLogger.debug('Adding Warnings as symbols with emojis', tag: 'MAP', data: {'count': warnings.length});
      for (var warning in warnings) {
        final id = 'warning_${warning.latitude}_${warning.longitude}';
        _warningById[id] = warning;
        final emoji = POITypeConfig.getWarningEmoji(warning.type);
        symbolOptions.add({
          'geometry': Point(coordinates: Position(warning.longitude, warning.latitude)),
          'textField': emoji,
          'textSize': MarkerConfig.getRadiusForType(POIMarkerType.warning),
          'textColor': Colors.black.value,
          'iconAllowOverlap': true,
          'textAllowOverlap': true,
        });
      }
    }

    if (symbolOptions.isNotEmpty) {
      // Use reflection/dynamic to call createMulti since type is not available at compile time on Web
      await (_symbolAnnotationManager as dynamic).createMulti(
        symbolOptions.map((opts) => SymbolAnnotationOptions(
          geometry: opts['geometry'],
          textField: opts['textField'],
          textSize: opts['textSize'],
          textColor: opts['textColor'],
          iconAllowOverlap: opts['iconAllowOverlap'],
          textAllowOverlap: opts['textAllowOverlap'],
        )).toList(),
      );
      AppLogger.success('Added symbol markers with emojis to 3D map', tag: 'MAP', data: {
        'count': symbolOptions.length,
      });
    } else {
      AppLogger.warning('No markers to add - all toggles might be off or no data loaded', tag: 'MAP', data: {
        'showOSMPOIs': mapState.showOSMPOIs,
        'showPOIs': mapState.showPOIs,
        'showWarnings': mapState.showWarnings,
      });
    }
  }

  /// Add markers using CircleAnnotations (Web fallback - emojis not supported)
  Future<void> _addCircleMarkers() async {
    if (_circleAnnotationManager == null) {
      AppLogger.warning('Circle annotation manager not ready', tag: 'MAP');
      return;
    }

    // Clear existing markers first
    await _circleAnnotationManager!.deleteAll();

    List<CircleAnnotationOptions> circleOptions = [];

    final mapState = ref.read(mapProvider);

    // Clear POI maps
    _osmPoiById.clear();
    _communityPoiById.clear();
    _warningById.clear();

    // Get OSM POIs (if enabled)
    if (mapState.showOSMPOIs) {
      final osmPOIs = ref.read(osmPOIsNotifierProvider).value ?? [];
      AppLogger.debug('Adding OSM POIs as circles (Web)', tag: 'MAP', data: {'count': osmPOIs.length});
      for (var poi in osmPOIs) {
        final id = 'osm_${poi.latitude}_${poi.longitude}';
        _osmPoiById[id] = poi;
        circleOptions.add(
          CircleAnnotationOptions(
            geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
            circleRadius: MarkerConfig.getRadiusForType(POIMarkerType.osmPOI),
            circleColor: MarkerConfig.getFillColorValueForType(POIMarkerType.osmPOI),
            circleStrokeWidth: MarkerConfig.circleStrokeWidth,
            circleStrokeColor: MarkerConfig.getBorderColorValueForType(POIMarkerType.osmPOI),
          ),
        );
      }
    }

    // Get Community POIs (if enabled)
    if (mapState.showPOIs) {
      final communityPOIs = ref.read(cyclingPOIsBoundsNotifierProvider).value ?? [];
      AppLogger.debug('Adding Community POIs as circles (Web)', tag: 'MAP', data: {'count': communityPOIs.length});
      for (var poi in communityPOIs) {
        final id = 'community_${poi.latitude}_${poi.longitude}';
        _communityPoiById[id] = poi;
        circleOptions.add(
          CircleAnnotationOptions(
            geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
            circleRadius: MarkerConfig.getRadiusForType(POIMarkerType.communityPOI),
            circleColor: MarkerConfig.getFillColorValueForType(POIMarkerType.communityPOI),
            circleStrokeWidth: MarkerConfig.circleStrokeWidth,
            circleStrokeColor: MarkerConfig.getBorderColorValueForType(POIMarkerType.communityPOI),
          ),
        );
      }
    }

    // Get Warnings (if enabled)
    if (mapState.showWarnings) {
      final warnings = ref.read(communityWarningsBoundsNotifierProvider).value ?? [];
      AppLogger.debug('Adding Warnings as circles (Web)', tag: 'MAP', data: {'count': warnings.length});
      for (var warning in warnings) {
        final id = 'warning_${warning.latitude}_${warning.longitude}';
        _warningById[id] = warning;
        circleOptions.add(
          CircleAnnotationOptions(
            geometry: Point(coordinates: Position(warning.longitude, warning.latitude)),
            circleRadius: MarkerConfig.getRadiusForType(POIMarkerType.warning),
            circleColor: MarkerConfig.getFillColorValueForType(POIMarkerType.warning),
            circleStrokeWidth: MarkerConfig.circleStrokeWidth,
            circleStrokeColor: MarkerConfig.getBorderColorValueForType(POIMarkerType.warning),
          ),
        );
      }
    }

    if (circleOptions.isNotEmpty) {
      await _circleAnnotationManager!.createMulti(circleOptions);
      AppLogger.success('Added circle markers to 3D map (Web)', tag: 'MAP', data: {
        'count': circleOptions.length,
      });
    } else {
      AppLogger.warning('No markers to add - all toggles might be off or no data loaded', tag: 'MAP', data: {
        'showOSMPOIs': mapState.showOSMPOIs,
        'showPOIs': mapState.showPOIs,
        'showWarnings': mapState.showWarnings,
      });
    }
  }
}

/// Click listener for circle annotations
class _OnSymbolClickListener extends OnSymbolAnnotationClickListener {
  final void Function(double lat, double lng) onTap;

  _OnSymbolClickListener({required this.onTap});

  @override
  void onSymbolAnnotationClick(SymbolAnnotation annotation) {
    // Use geometry coordinates to identify the POI
    final coords = annotation.geometry.coordinates;
    AppLogger.map('Symbol annotation clicked', data: {'lat': coords.lat, 'lng': coords.lng});
    onTap(coords.lat.toDouble(), coords.lng.toDouble());
  }
}