import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../providers/compass_provider.dart';
import '../services/map_service.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/app_logger.dart';
import '../config/marker_config.dart';
import '../config/poi_type_config.dart';
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

  @override
  void initState() {
    super.initState();
    AppLogger.separator('MapScreen initState');
    AppLogger.ios('initState called', data: {
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Initialize map when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.ios('PostFrameCallback executing', data: {'screen': 'MapScreen'});
      _onMapReady();

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

          _mapController.move(newPosition, 15.0);
          AppLogger.success('Map moved', tag: 'MAP', data: {
            'lat': newPosition.latitude,
            'lng': newPosition.longitude,
            'zoom': 15.0,
          });

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

    // Load OSM POIs in background
    final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
    AppLogger.debug('Calling OSM POI background load', tag: 'MAP');
    osmPOIsNotifier.loadPOIsInBackground(extendedBounds);

    // Load Community POIs in background
    final communityPOIsNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
    AppLogger.debug('Calling community POIs background load', tag: 'MAP');
    communityPOIsNotifier.loadPOIsWithBounds(extendedBounds);

    // Load Warnings in background
    final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
    AppLogger.debug('Calling community warnings background load', tag: 'MAP');
    warningsNotifier.loadWarningsWithBounds(extendedBounds);

    AppLogger.success('Background loading calls completed', tag: 'MAP', data: {
      'types': 'OSM POIs, Community POIs, Warnings',
    });
  }

  /// Handle map events
  void _onMapEvent(MapEvent mapEvent) {
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

      // CRITICAL: If this is the first time we have location and haven't loaded POIs yet, do it now!
      if (!_hasTriggeredInitialPOILoad) {
        AppLogger.separator('FIRST LOCATION RECEIVED');
        AppLogger.location('Centering map and loading POIs', data: {
          'lat': location.latitude,
          'lng': location.longitude,
        });

        _mapController.move(newGPSPosition, 15.0);
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

      // Normal auto-center logic for subsequent location updates
      if (_originalGPSReference != null) {
        final distance = _calculateDistance(
          _originalGPSReference!.latitude,
          _originalGPSReference!.longitude,
          newGPSPosition.latitude,
          newGPSPosition.longitude,
        );

        // Auto-center if user moved > 50m
        if (distance > 50) {
          AppLogger.location('GPS moved, auto-centering', data: {
            'distance': '${distance.toStringAsFixed(1)}m',
          });
          _mapController.move(newGPSPosition, _mapController.camera.zoom);
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
      items: [
        PopupMenuItem<String>(
          value: 'add_poi',
          child: Row(
            children: [
              Icon(Icons.add_location, color: Colors.green[700]),
              const SizedBox(width: 8),
              const Text('Add Community POI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'report_hazard',
          child: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Report Hazard', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
        }
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

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742000 * math.asin(math.sqrt(a)); // 2 * R * asin, R = 6371km
  }

  void _open3DMap() {
    AppLogger.map('Opening 3D map');
    Navigator.push(
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
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Map Layer',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...MapLayerType.values.map((layer) {
              return ListTile(
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
                  Text(typeEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  _loadAllMapDataWithBounds(forceReload: true);
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
                  _loadAllMapDataWithBounds(forceReload: true);
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
                  _loadAllMapDataWithBounds(forceReload: true);
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
                  _loadAllMapDataWithBounds(forceReload: true);
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

  /// Build toggle button with count badge
  Widget _buildToggleButton({
    required bool isActive,
    required IconData icon,
    required Color activeColor,
    required int count,
    required VoidCallback onPressed,
    required String tooltip,
    bool showFullCount = false, // If true, shows actual count. If false, shows "99+" for counts > 99
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

    // Build marker list
    List<Marker> markers = [];

    // Add user location marker with direction indicator
    locationAsync.whenData((location) {
      if (location != null) {
        AppLogger.map('Adding user location marker', data: {
          'lat': location.latitude,
          'lng': location.longitude,
        });

        // Use compass heading on Native, or GPS heading as fallback
        final heading = !kIsWeb && compassHeading != null ? compassHeading : location.heading;
        final hasHeading = heading != null && heading >= 0;

        AppLogger.map('Marker heading', data: {
          'heading': heading?.toStringAsFixed(1),
          'hasHeading': hasHeading,
        });

        final userSize = MarkerConfig.getRadiusForType(POIMarkerType.userLocation) * 2;
        markers.add(
          Marker(
            point: LatLng(location.latitude, location.longitude),
            width: userSize,
            height: userSize,
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: hasHeading ? (heading * math.pi / 180) : 0, // Convert to radians
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
                  // Direction arrow (only if we have heading)
                  if (hasHeading)
                    Icon(
                      Icons.navigation,
                      color: MarkerConfig.getBorderColorForType(POIMarkerType.userLocation),
                      size: userSize * 0.6,
                    )
                  else
                    Icon(
                      Icons.my_location,
                      color: MarkerConfig.getBorderColorForType(POIMarkerType.userLocation),
                      size: userSize * 0.6,
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
        AppLogger.map('Adding OSM POI markers', data: {'count': pois.length});
        markers.addAll(pois.map((poi) => _buildPOIMarker(poi)));
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

    AppLogger.map('Total markers on map', data: {'count': markers.length});

    return Scaffold(
      body: Stack(
        children: [
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

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(location.latitude, location.longitude),
                  initialZoom: 15,
                  onMapEvent: _onMapEvent,
                  onLongPress: _onMapLongPress,
                ),
                children: [
                  TileLayer(
                    urlTemplate: mapState.tileUrl,
                    userAgentPackageName: 'com.popibiking.popiBikingFresh',
                    subdomains: const ['a', 'b', 'c'],
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
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Column(
              children: [
                // OSM POI toggle with count (no limit)
                _buildToggleButton(
                  isActive: mapState.showOSMPOIs,
                  icon: Icons.public,
                  activeColor: Colors.blue,
                  count: poisAsync.value?.length ?? 0,
                  showFullCount: true, // Show actual count, not 99+
                  onPressed: () {
                    AppLogger.map('OSM POI toggle pressed');
                    ref.read(mapProvider.notifier).toggleOSMPOIs();
                  },
                  tooltip: 'Toggle OSM POIs',
                ),
                const SizedBox(height: 12),

                // Community POI toggle with count
                _buildToggleButton(
                  isActive: mapState.showPOIs,
                  icon: Icons.location_on,
                  activeColor: Colors.green,
                  count: communityPOIsAsync.value?.length ?? 0,
                  onPressed: () {
                    AppLogger.map('Community POI toggle pressed');
                    ref.read(mapProvider.notifier).togglePOIs();
                  },
                  tooltip: 'Toggle Community POIs',
                ),
                const SizedBox(height: 12),

                // Warning toggle with count
                _buildToggleButton(
                  isActive: mapState.showWarnings,
                  icon: Icons.warning,
                  activeColor: Colors.orange,
                  count: warningsAsync.value?.length ?? 0,
                  onPressed: () {
                    AppLogger.map('Warning toggle pressed');
                    ref.read(mapProvider.notifier).toggleWarnings();
                  },
                  tooltip: 'Toggle Warnings',
                ),
                const SizedBox(height: 24),

                // Zoom controls
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  onPressed: () {
                    AppLogger.map('Zoom in pressed');
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom + 1,
                    );
                    AppLogger.map('Zoom changed', data: {
                      'from': currentZoom,
                      'to': currentZoom + 1,
                    });
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),

                // Zoom out button
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  onPressed: () {
                    AppLogger.map('Zoom out pressed');
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom - 1,
                    );
                    AppLogger.map('Zoom changed', data: {
                      'from': currentZoom,
                      'to': currentZoom - 1,
                    });
                  },
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'layer_picker',
            onPressed: _showLayerPicker,
            backgroundColor: Colors.blue,
            child: const Icon(Icons.layers),
          ),
          const SizedBox(height: 16), // Consistent spacing
          // Reload POIs button (matching 3D map)
          FloatingActionButton(
            heroTag: 'reload_pois_2d',
            onPressed: () {
              AppLogger.map('Manual POI reload requested (2D)');
              _loadAllMapDataWithBounds(forceReload: true);
            },
            backgroundColor: Colors.orange,
            tooltip: 'Reload POIs',
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 16), // Consistent spacing
          // 3D Map button - only show on Native (not on web/PWA)
          if (!kIsWeb) ...[
            FloatingActionButton(
              heroTag: '3d_map',
              onPressed: _open3DMap,
              backgroundColor: Colors.green,
              tooltip: 'Switch to 3D Map',
              child: const Icon(Icons.terrain),
            ),
            const SizedBox(height: 16), // Consistent spacing
            // Compass rotation toggle button (Native only)
            FloatingActionButton(
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
            const SizedBox(height: 16), // Consistent spacing
          ],
          FloatingActionButton(
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
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}
