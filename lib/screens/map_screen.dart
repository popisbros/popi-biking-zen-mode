import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../providers/location_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../providers/map_provider.dart';
import '../services/map_service.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../models/location_data.dart';
import '../utils/poi_icons.dart';
import 'mapbox_map_screen_simple.dart';

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

  @override
  void initState() {
    super.initState();
    print('🗺️ iOS DEBUG [MapScreen]: ========== initState called ==========');
    print('🗺️ iOS DEBUG [MapScreen]: Timestamp = ${DateTime.now().toIso8601String()}');

    // Initialize map when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🗺️ iOS DEBUG [MapScreen]: PostFrameCallback executing...');
      _onMapReady();
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

          // Add a small delay to ensure map is fully positioned before loading POIs
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              print('🗺️ iOS DEBUG [MapScreen]: Triggering POI load at user location (after delay)...');
              _loadAllMapDataWithBounds();
            }
          });

          // Initialize GPS position tracking
          _lastGPSPosition = newPosition;
          _originalGPSReference = newPosition;
          print('✅ iOS DEBUG [MapScreen]: GPS references initialized');
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
  void _loadAllMapDataWithBounds() {
    if (!_isMapReady) {
      print('⚠️ iOS DEBUG [MapScreen]: Map not ready, skipping data load');
      return;
    }

    try {
      print('🗺️ iOS DEBUG [MapScreen]: ========== Loading map data ==========');

      final camera = _mapController.camera;
      final latLngBounds = camera.visibleBounds;

      // Check if we should reload
      if (!_shouldReloadData(latLngBounds)) {
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

    // Load Warnings in background
    final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
    print('🔄 iOS DEBUG [MapScreen]: Calling community warnings background load...');
    warningsNotifier.loadWarningsWithBounds(extendedBounds);

    print('✅ iOS DEBUG [MapScreen]: Background loading calls completed');
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  style: const TextStyle(fontSize: 16),
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

  @override
  Widget build(BuildContext context) {
    print('🗺️ iOS DEBUG [MapScreen]: Building widget...');

    final locationAsync = ref.watch(locationNotifierProvider);
    final poisAsync = ref.watch(osmPOIsNotifierProvider);
    final warningsAsync = ref.watch(communityWarningsBoundsNotifierProvider);
    final mapState = ref.watch(mapProvider);

    // Listen to location changes for auto-centering
    locationAsync.whenData((location) => _handleGPSLocationChange(location));

    // Build marker list
    List<Marker> markers = [];

    // Add user location marker
    locationAsync.whenData((location) {
      if (location != null) {
        print('🗺️ iOS DEBUG [MapScreen]: Adding user location marker at ${location.latitude}, ${location.longitude}');
        markers.add(
          Marker(
            point: LatLng(location.latitude, location.longitude),
            width: 50,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue, width: 3),
              ),
              child: const Icon(
                Icons.my_location,
                color: Colors.blue,
                size: 30,
              ),
            ),
          ),
        );
      }
    });

    // Add POI markers
    poisAsync.whenData((pois) {
      print('🗺️ iOS DEBUG [MapScreen]: Adding ${pois.length} POI markers to map');
      markers.addAll(pois.map((poi) => _buildPOIMarker(poi)));
    });

    // Add warning markers
    warningsAsync.whenData((warnings) {
      print('🗺️ iOS DEBUG [MapScreen]: Adding ${warnings.length} warning markers to map');
      markers.addAll(warnings.map((warning) => _buildWarningMarker(warning)));
    });

    print('🗺️ iOS DEBUG [MapScreen]: Total markers on map: ${markers.length}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Popi Biking'),
        backgroundColor: Colors.green,
        actions: [
          // POI count indicator
          poisAsync.when(
            data: (pois) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('POIs: ${pois.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
            error: (_, __) => const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('POIs: Error'))),
          ),
        ],
      ),
      body: locationAsync.when(
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'layer_picker',
            onPressed: _showLayerPicker,
            backgroundColor: Colors.blue,
            child: const Icon(Icons.layers),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: '3d_map',
            onPressed: _open3DMap,
            backgroundColor: Colors.green,
            child: const Icon(Icons.terrain),
          ),
          const SizedBox(height: 16),
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
