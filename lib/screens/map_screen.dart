import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../providers/compass_provider.dart';
import '../services/map_service.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/poi_icons.dart';
import 'mapbox_map_screen_simple.dart';
import 'community/poi_management_screen.dart';
import 'community/hazard_report_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  final bool autoOpen3D;

  const MapScreen({super.key, this.autoOpen3D = false});

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
  bool _hasAutoOpened3D = false; // Track if we've already auto-opened 3D

  // Smart reload logic - store loaded bounds and buffer zone
  BoundingBox? _lastLoadedBounds;
  BoundingBox? _reloadTriggerBounds;

  @override
  void initState() {
    super.initState();
    print('🗺️ iOS DEBUG [MapScreen]: ========== initState called ==========');
    print('🗺️ iOS DEBUG [MapScreen]: Timestamp = ${DateTime.now().toIso8601String()}');

    // Initialize map when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🗺️ iOS DEBUG [MapScreen]: PostFrameCallback executing...');
      _onMapReady();

      // CRITICAL FIX: Manually trigger location handler for initial load
      // The ref.listen() in build() only fires on CHANGES, not initial value
      final locationAsync = ref.read(locationNotifierProvider);
      locationAsync.whenData((location) {
        if (location != null && !_hasTriggeredInitialPOILoad) {
          print('🗺️ iOS DEBUG [MapScreen]: MANUAL TRIGGER for initial location');
          // Give the map a moment to fully initialize before loading POIs
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              print('🗺️ iOS DEBUG [MapScreen]: Triggering initial POI load via manual handler');
              _handleGPSLocationChange(location);
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    print('🗑️ iOS DEBUG [MapScreen]: Disposing map screen...');
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onMapReady() {
    print('🗺️ iOS DEBUG [MapScreen]: ========== Map ready ==========');
    setState(() {
      _isMapReady = true;
    });
    print('🗺️ iOS DEBUG [MapScreen]: Map ready flag set to TRUE');

    // DON'T load POIs immediately - wait for GPS location first!
    print('🗺️ iOS DEBUG [MapScreen]: Waiting for GPS location before loading POIs...');
    _centerOnUserLocation();
  }

  /// Center map on user's GPS location (CRITICAL for OSM POIs to work)
  Future<void> _centerOnUserLocation() async {
    print('🗺️ iOS DEBUG [MapScreen]: ========== Centering on user location ==========');

    final locationAsync = ref.read(locationNotifierProvider);

    locationAsync.when(
      data: (location) {
        if (location != null) {
          print('✅ iOS DEBUG [MapScreen]: Got GPS location!');
          print('   Lat=${location.latitude}, Lng=${location.longitude}');
          print('   Accuracy=${location.accuracy}m');

          final newPosition = LatLng(location.latitude, location.longitude);
          print('🗺️ iOS DEBUG [MapScreen]: Moving map to user location...');

          _mapController.move(newPosition, 15.0);
          print('✅ iOS DEBUG [MapScreen]: Map moved to Lat=${newPosition.latitude}, Lng=${newPosition.longitude}, Zoom=15.0');

          // Initialize GPS position tracking
          _lastGPSPosition = newPosition;
          _originalGPSReference = newPosition;

          // NOTE: POI loading will be triggered automatically by the location listener in build()
          print('✅ iOS DEBUG [MapScreen]: GPS references initialized');

          // Auto-open 3D map if requested (Native app startup)
          if (widget.autoOpen3D && !_hasAutoOpened3D && !kIsWeb) {
            _hasAutoOpened3D = true;
            print('🚀 iOS DEBUG [MapScreen]: Auto-opening 3D map in 1 second...');
            print('   autoOpen3D=${widget.autoOpen3D}, hasAutoOpened=$_hasAutoOpened3D, kIsWeb=$kIsWeb');
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted) {
                print('🚀 iOS DEBUG [MapScreen]: NOW calling _open3DMap()...');
                _open3DMap();
                print('🚀 iOS DEBUG [MapScreen]: _open3DMap() called successfully');
              } else {
                print('❌ iOS DEBUG [MapScreen]: Cannot open 3D map - widget not mounted');
              }
            });
          } else {
            print('🔍 iOS DEBUG [MapScreen]: Auto-open 3D skipped:');
            print('   autoOpen3D=${widget.autoOpen3D}, hasAutoOpened=$_hasAutoOpened3D, kIsWeb=$kIsWeb');
          }
        } else {
          print('⚠️ iOS DEBUG [MapScreen]: Location is NULL - GPS not available yet');
          print('🔄 iOS DEBUG [MapScreen]: Will retry when location becomes available via build() listener');
        }
      },
      loading: () {
        print('⏳ iOS DEBUG [MapScreen]: Location still LOADING...');
        print('   Will load POIs automatically when location becomes available');
      },
      error: (error, stack) {
        print('❌ iOS DEBUG [MapScreen]: Location ERROR: $error');
        print('   Cannot load POIs without location');
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

    print('🗺️ iOS DEBUG [MapScreen]: Extended bounds calculated:');
    print('   Visible: S=${visibleBounds.south.toStringAsFixed(4)}, N=${visibleBounds.north.toStringAsFixed(4)}');
    print('   Visible: W=${visibleBounds.west.toStringAsFixed(4)}, E=${visibleBounds.east.toStringAsFixed(4)}');
    print('   Extended: S=${bbox.south.toStringAsFixed(4)}, N=${bbox.north.toStringAsFixed(4)}');
    print('   Extended: W=${bbox.west.toStringAsFixed(4)}, E=${bbox.east.toStringAsFixed(4)}');

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
      print('🗺️ iOS DEBUG [MapScreen]: First load - should reload = TRUE');
      return true;
    }

    final shouldReload = visibleBounds.south < _reloadTriggerBounds!.south ||
        visibleBounds.north > _reloadTriggerBounds!.north ||
        visibleBounds.west < _reloadTriggerBounds!.west ||
        visibleBounds.east > _reloadTriggerBounds!.east;

    print('🗺️ iOS DEBUG [MapScreen]: Should reload check = $shouldReload');
    if (!shouldReload) {
      print('   Still within buffer zone, skipping reload');
    }

    return shouldReload;
  }

  /// Load all map data (OSM POIs, Warnings) using extended bounds
  void _loadAllMapDataWithBounds({bool forceReload = false}) {
    if (!_isMapReady) {
      print('⚠️ iOS DEBUG [MapScreen]: Map not ready, skipping data load');
      return;
    }

    try {
      print('🗺️ iOS DEBUG [MapScreen]: ========== Loading map data ==========');

      final camera = _mapController.camera;
      final latLngBounds = camera.visibleBounds;

      // Check if we should reload (skip check if forceReload is true)
      if (!forceReload && !_shouldReloadData(latLngBounds)) {
        print('⏭️ iOS DEBUG [MapScreen]: Within loaded bounds, skipping reload');
        return;
      }

      // Calculate extended bounds
      final extendedBounds = _calculateExtendedBounds(latLngBounds);

      print('🗺️ iOS DEBUG [MapScreen]: Starting background data reload...');

      // Load data in background
      _loadDataInBackground(extendedBounds);

      // Update stored bounds
      _lastLoadedBounds = extendedBounds;
      _reloadTriggerBounds = _calculateReloadTriggerBounds(extendedBounds);

      print('✅ iOS DEBUG [MapScreen]: Background loading initiated');
    } catch (e, stackTrace) {
      print('❌ iOS DEBUG [MapScreen]: Error loading map data: $e');
      print(stackTrace.toString().split('\n').take(5).join('\n'));
    }
  }

  /// Load data in background without clearing existing data
  void _loadDataInBackground(BoundingBox extendedBounds) {
    print('🔄 iOS DEBUG [MapScreen]: Loading data in background...');
    print('   Bounds: S=${extendedBounds.south.toStringAsFixed(4)}, N=${extendedBounds.north.toStringAsFixed(4)}');
    print('   Bounds: W=${extendedBounds.west.toStringAsFixed(4)}, E=${extendedBounds.east.toStringAsFixed(4)}');

    // Load OSM POIs in background
    final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
    print('🔄 iOS DEBUG [MapScreen]: Calling OSM POI background load...');
    osmPOIsNotifier.loadPOIsInBackground(extendedBounds);

    // Load Community POIs in background
    final communityPOIsNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
    print('🔄 iOS DEBUG [MapScreen]: Calling community POIs background load...');
    communityPOIsNotifier.loadPOIsWithBounds(extendedBounds);

    // Load Warnings in background
    final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
    print('🔄 iOS DEBUG [MapScreen]: Calling community warnings background load...');
    warningsNotifier.loadWarningsWithBounds(extendedBounds);

    print('✅ iOS DEBUG [MapScreen]: Background loading calls completed (OSM POIs, Community POIs, Warnings)');
  }

  /// Handle map events
  void _onMapEvent(MapEvent mapEvent) {
    if (mapEvent is MapEventMove || mapEvent is MapEventMoveStart || mapEvent is MapEventMoveEnd) {
      _isUserMoving = true;

      // Debounce reload
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
        if (_isMapReady) {
          print('🗺️ iOS DEBUG [MapScreen]: Map moved, reloading data (debounced)...');
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
        print('🗺️ iOS DEBUG [MapScreen]: ========== FIRST LOCATION RECEIVED ==========');
        print('   Location: ${location.latitude}, ${location.longitude}');
        print('   Centering map and loading POIs...');

        _mapController.move(newGPSPosition, 15.0);
        _originalGPSReference = newGPSPosition;
        _lastGPSPosition = newGPSPosition;

        // Add delay to ensure map has moved before loading POIs
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            print('🗺️ iOS DEBUG [MapScreen]: Triggering INITIAL POI load...');
            _loadAllMapDataWithBounds();
            _hasTriggeredInitialPOILoad = true;
            print('✅ iOS DEBUG [MapScreen]: Initial POI load triggered');
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
          print('🗺️ iOS DEBUG [MapScreen]: GPS moved ${distance.toStringAsFixed(1)}m, auto-centering...');
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

    print('🗺️ iOS DEBUG [MapScreen]: Map long-pressed at: ${point.latitude}, ${point.longitude}');

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
    print('🗺️ iOS DEBUG [MapScreen]: Opening Add POI screen at: ${point.latitude}, ${point.longitude}');

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
    print('🗺️ iOS DEBUG [MapScreen]: Returned from POI screen, reloading map data...');
    if (mounted && _isMapReady) {
      _loadAllMapDataWithBounds(forceReload: true);
    }
  }

  /// Navigate to Hazard report screen
  void _showReportHazardDialog(LatLng point) async {
    print('🗺️ iOS DEBUG [MapScreen]: Opening Report Hazard screen at: ${point.latitude}, ${point.longitude}');

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
    print('🗺️ iOS DEBUG [MapScreen]: Returned from Warning screen, reloading map data...');
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
    print('🗺️ iOS DEBUG [MapScreen]: Opening 3D map...');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapboxMapScreenSimple(),
      ),
    );
  }

  void _showLayerPicker() {
    print('🗺️ iOS DEBUG [MapScreen]: Showing layer picker...');
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
                  print('🗺️ iOS DEBUG [MapScreen]: Layer changed to $layer');
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
    final icon = POIIcons.getPOIIcon(poi.type);
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          print('🗺️ iOS DEBUG [MapScreen]: POI tapped: ${poi.name} (${poi.type})');
          _showPOIDetails(poi);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              icon,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildWarningMarker(CommunityWarning warning) {
    return Marker(
      point: LatLng(warning.latitude, warning.longitude),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          print('🗺️ iOS DEBUG [MapScreen]: Warning tapped: ${warning.type}');
          _showWarningDetails(warning);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.red, width: 2),
          ),
          child: const Icon(
            Icons.warning,
            color: Colors.red,
            size: 24,
          ),
        ),
      ),
    );
  }

  Marker _buildCommunityPOIMarker(CyclingPOI poi) {
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          print('🗺️ iOS DEBUG [MapScreen]: Community POI tapped: ${poi.name}');
          _showCommunityPOIDetails(poi);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: const Icon(
            Icons.location_on,
            color: Colors.green,
            size: 24,
          ),
        ),
      ),
    );
  }

  void _showPOIDetails(OSMPOI poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${poi.type}'),
            if (poi.description != null) Text('Description: ${poi.description}'),
            if (poi.address != null) Text('Address: ${poi.address}'),
            Text('Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showWarningDetails(CommunityWarning warning) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(warning.type),
        content: Text(warning.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showCommunityPOIDetails(CyclingPOI poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${poi.type}'),
            if (poi.description != null && poi.description!.isNotEmpty)
              Text('Description: ${poi.description}'),
            if (poi.address != null && poi.address!.isNotEmpty)
              Text('Address: ${poi.address}'),
            if (poi.phone != null && poi.phone!.isNotEmpty)
              Text('Phone: ${poi.phone}'),
            if (poi.website != null && poi.website!.isNotEmpty)
              Text('Website: ${poi.website}'),
            Text('Coordinates: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
    print('🗺️ iOS DEBUG [MapScreen]: Building widget...');

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
          print('🗺️ iOS DEBUG [MapScreen]: Location changed via listener!');
          _handleGPSLocationChange(location);
        }
      });
    });

    // Listen for compass changes to rotate map (Native only)
    if (!kIsWeb) {
      ref.listen<double?>(compassNotifierProvider, (previous, next) {
        if (next != null && _isMapReady && !_isUserMoving) {
          // Rotate map to match compass heading
          // flutter_map rotation is counter-clockwise, compass is clockwise
          // So we need to negate the heading
          final rotation = -next;
          print('🧭 iOS DEBUG [MapScreen]: Rotating map to ${rotation.toStringAsFixed(1)}° (heading=$next°)');
          _mapController.rotate(rotation);
        }
      });
    }

    // Build marker list
    List<Marker> markers = [];

    // Add user location marker with direction indicator
    locationAsync.whenData((location) {
      if (location != null) {
        print('🗺️ iOS DEBUG [MapScreen]: Adding user location marker at ${location.latitude}, ${location.longitude}');

        // Use compass heading on Native, or GPS heading as fallback
        final heading = !kIsWeb && compassHeading != null ? compassHeading : location.heading;
        final hasHeading = heading != null && heading >= 0;

        print('🗺️ iOS DEBUG [MapScreen]: Marker heading = ${heading?.toStringAsFixed(1)}° (has heading: $hasHeading)');

        markers.add(
          Marker(
            point: LatLng(location.latitude, location.longitude),
            width: 50,
            height: 50,
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: hasHeading ? (heading * math.pi / 180) : 0, // Convert to radians
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer circle (accuracy indicator)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                  ),
                  // Direction arrow (only if we have heading)
                  if (hasHeading)
                    const Icon(
                      Icons.navigation,
                      color: Colors.blue,
                      size: 30,
                    )
                  else
                    const Icon(
                      Icons.my_location,
                      color: Colors.blue,
                      size: 30,
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
        print('🗺️ iOS DEBUG [MapScreen]: Adding ${pois.length} OSM POI markers to map');
        markers.addAll(pois.map((poi) => _buildPOIMarker(poi)));
      });
    } else {
      print('🗺️ iOS DEBUG [MapScreen]: OSM POIs hidden by toggle');
    }

    // Add Community POI markers (only if showPOIs is true)
    if (mapState.showPOIs) {
      communityPOIsAsync.when(
        data: (communityPOIs) {
          print('🗺️ iOS DEBUG [MapScreen]: Adding ${communityPOIs.length} Community POI markers to map');
          markers.addAll(communityPOIs.map((poi) => _buildCommunityPOIMarker(poi)));
        },
        loading: () {
          print('⏳ iOS DEBUG [MapScreen]: Community POIs still loading...');
        },
        error: (error, stackTrace) {
          print('❌ iOS DEBUG [MapScreen]: Community POIs error: $error');
          print('   Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        },
      );
    } else {
      print('🗺️ iOS DEBUG [MapScreen]: Community POIs hidden by toggle');
    }

    // Add warning markers (only if showWarnings is true)
    if (mapState.showWarnings) {
      warningsAsync.whenData((warnings) {
        print('🗺️ iOS DEBUG [MapScreen]: Adding ${warnings.length} warning markers to map');
        markers.addAll(warnings.map((warning) => _buildWarningMarker(warning)));
      });
    } else {
      print('🗺️ iOS DEBUG [MapScreen]: Warnings hidden by toggle');
    }

    print('🗺️ iOS DEBUG [MapScreen]: Total markers on map: ${markers.length}');

    return Scaffold(
      body: Stack(
        children: [
          // Main map content
          locationAsync.when(
            data: (location) {
              if (location == null) {
                print('⚠️ iOS DEBUG [MapScreen]: Location is NULL - showing loading indicator');
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

              print('🗺️ iOS DEBUG [MapScreen]: Building map with location ${location.latitude}, ${location.longitude}');

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
              print('⏳ iOS DEBUG [MapScreen]: Location LOADING - showing spinner');
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
              print('❌ iOS DEBUG [MapScreen]: Location ERROR - $error');
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
                        print('🔄 iOS DEBUG [MapScreen]: User requested permission retry');
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
                    print('🗺️ iOS DEBUG [MapScreen]: OSM POI toggle pressed');
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
                    print('🗺️ iOS DEBUG [MapScreen]: Community POI toggle pressed');
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
                    print('🗺️ iOS DEBUG [MapScreen]: Warning toggle pressed');
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
                    print('🗺️ iOS DEBUG [MapScreen]: Zoom in pressed');
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom + 1,
                    );
                    print('🗺️ iOS DEBUG [MapScreen]: Zoom changed from $currentZoom to ${currentZoom + 1}');
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
                    print('🗺️ iOS DEBUG [MapScreen]: Zoom out pressed');
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom - 1,
                    );
                    print('🗺️ iOS DEBUG [MapScreen]: Zoom changed from $currentZoom to ${currentZoom - 1}');
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
          ],
          FloatingActionButton(
            heroTag: 'my_location',
            onPressed: () {
              print('🗺️ iOS DEBUG [MapScreen]: My location button pressed');
              locationAsync.whenData((location) {
                if (location != null) {
                  print('🗺️ iOS DEBUG [MapScreen]: Centering on GPS location');
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
