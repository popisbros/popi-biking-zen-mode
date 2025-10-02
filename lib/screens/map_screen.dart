import 'dart:async';
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

  @override
  void initState() {
    super.initState();
    // Initialize map when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onMapReady();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onMapReady() {
    setState(() {
      _isMapReady = true;
    });
    // Load POIs when map is ready
    _loadAllMapData();
  }

  void _loadAllMapData() {
    if (!_isMapReady) return;

    try {
      final camera = _mapController.camera;
      final bounds = camera.visibleBounds;

      final bbox = BoundingBox(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      print('MapScreen: Loading OSM POIs with bounds=$bbox');

      // Load OSM POIs
      final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
      osmPOIsNotifier.loadPOIsWithBounds(bbox);
    } catch (e) {
      print('MapScreen: Error loading map data: $e');
    }
  }

  void _onMapEvent(MapEvent mapEvent) {
    if (mapEvent is MapEventMove || mapEvent is MapEventMoveEnd) {
      // Debounce the reload to avoid too many API calls
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
        if (_isMapReady) {
          _loadAllMapData();
        }
      });
    }
  }

  void _open3DMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapboxMapScreenSimple(),
      ),
    );
  }

  void _showLayerPicker() {
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...MapLayerType.values.map((layer) {
              return ListTile(
                leading: Icon(
                  _getLayerIcon(layer),
                  color: currentLayer == layer ? Colors.green : Colors.grey,
                ),
                title: Text(mapService.getLayerName(layer)),
                trailing: currentLayer == layer
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
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

  Marker _buildPOIMarker(CyclingPOI poi) {
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: 30,
      height: 30,
      child: GestureDetector(
        onTap: () => _showPOIDetails(poi),
        child: Icon(
          _getPOIIcon(poi.type),
          color: Colors.green,
          size: 30,
        ),
      ),
    );
  }

  Marker _buildWarningMarker(CommunityWarning warning) {
    return Marker(
      point: LatLng(warning.latitude, warning.longitude),
      width: 30,
      height: 30,
      child: GestureDetector(
        onTap: () => _showWarningDetails(warning),
        child: Icon(
          _getWarningIcon(warning.type),
          color: Colors.red,
          size: 30,
        ),
      ),
    );
  }

  IconData _getPOIIcon(String type) {
    switch (type) {
      case 'bicycle_parking':
        return Icons.local_parking;
      case 'bicycle_repair_station':
        return Icons.build;
      case 'drinking_water':
        return Icons.water_drop;
      case 'toilets':
        return Icons.wc;
      case 'bicycle_shop':
        return Icons.store;
      default:
        return Icons.place;
    }
  }

  IconData _getWarningIcon(String type) {
    switch (type) {
      case 'road_hazard':
        return Icons.warning;
      case 'construction':
        return Icons.construction;
      case 'accident':
        return Icons.car_crash;
      default:
        return Icons.report_problem;
    }
  }

  void _showPOIDetails(CyclingPOI poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${poi.type}'),
            if (poi.description != null) Text(poi.description!),
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
    final locationState = ref.watch(locationProvider);
    final poisAsync = ref.watch(osmPOIsNotifierProvider);
    final warningsAsync = ref.watch(communityWarningsNotifierProvider);
    final mapState = ref.watch(mapProvider);

    // Build marker list
    List<Marker> markers = [];

    // Add user location marker
    if (locationState.position != null) {
      markers.add(
        Marker(
          point: LatLng(
            locationState.position!.latitude,
            locationState.position!.longitude,
          ),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 40,
          ),
        ),
      );
    }

    // Add POI markers
    poisAsync.whenData((pois) {
      markers.addAll(pois.map((poi) => _buildPOIMarker(poi)));
    });

    // Add warning markers
    warningsAsync.whenData((warnings) {
      markers.addAll(warnings.map((warning) => _buildWarningMarker(warning)));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Popi Biking'),
        backgroundColor: Colors.green,
      ),
      body: locationState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : locationState.error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error: ${locationState.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: locationState.position != null
                        ? LatLng(
                            locationState.position!.latitude,
                            locationState.position!.longitude,
                          )
                        : const LatLng(37.7749, -122.4194), // San Francisco default
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
              if (locationState.position != null) {
                _mapController.move(
                  LatLng(
                    locationState.position!.latitude,
                    locationState.position!.longitude,
                  ),
                  15,
                );
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}
