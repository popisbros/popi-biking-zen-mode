import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/map_provider.dart';
import '../providers/community_provider.dart';
import '../services/map_service.dart';
import '../widgets/warning_report_modal.dart';
import 'community/poi_management_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final MapService _mapService = MapService();
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _initializeMap();
  }

  Future<void> _initializeLocation() async {
    // Request location permission and start tracking
    final locationNotifier = ref.read(locationNotifierProvider.notifier);
    await locationNotifier.requestPermission();
    await locationNotifier.startTracking();
  }

  void _initializeMap() {
    // Load cycling data and initialize map state
    final mapNotifier = ref.read(mapProvider.notifier);
    mapNotifier.loadCyclingData();
  }

  void _onMapReady() {
    setState(() {
      _isMapReady = true;
    });
    
    // Center map on user location when available
    _centerOnUserLocation();
  }

  Future<void> _centerOnUserLocation() async {
    final locationAsync = ref.read(locationNotifierProvider);
    locationAsync.whenData((location) {
      if (location != null) {
        _mapController.move(
          LatLng(location.latitude, location.longitude),
          15.0,
        );
      }
    });
  }

  void _onReportWarning() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const WarningReportModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationNotifierProvider);
    final mapState = ref.watch(mapProvider);
    final warningsAsync = ref.watch(communityWarningsProvider);
    final poisAsync = ref.watch(cyclingPOIsProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Enhanced Flutter Map with cycling features
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapState.center,
              initialZoom: mapState.zoom,
              minZoom: 10.0,
              maxZoom: 20.0,
              onMapReady: () => _onMapReady(),
              onTap: (tapPosition, point) => _onMapTap(point),
            ),
            children: [
              // Dynamic tile layer based on current selection
              TileLayer(
                urlTemplate: mapState.tileUrl,
                userAgentPackageName: _mapService.userAgent,
                maxZoom: 20,
                subdomains: const ['a', 'b', 'c'],
              ),
              
                      // Cycling routes
                      if (mapState.showRoutes)
                        PolylineLayer(
                          polylines: _buildRoutePolylines(mapState.routes),
                        ),
                      
                      // POI markers (from Firestore)
                      if (mapState.showPOIs)
                        poisAsync.when(
                          data: (pois) => MarkerLayer(
                            markers: _buildPOIMarkersFromFirestore(pois),
                          ),
                          loading: () => const MarkerLayer(markers: []),
                          error: (error, stack) => const MarkerLayer(markers: []),
                        ),
                      
                      // Warning markers (from Firestore)
                      if (mapState.showWarnings)
                        warningsAsync.when(
                          data: (warnings) => MarkerLayer(
                            markers: _buildWarningMarkersFromFirestore(warnings),
                          ),
                          loading: () => const MarkerLayer(markers: []),
                          error: (error, stack) => const MarkerLayer(markers: []),
                        ),
              
              // Attribution (simplified for now)
              // RichAttributionWidget(
              //   attributions: [
              //     TextSource('© OpenStreetMap contributors'),
              //   ],
              // ),
            ],
          ),

                  // Profile button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: Semantics(
                      label: 'Open user profile',
                      button: true,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.urbanBlue,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile feature coming soon'),
                            ),
                          );
                        },
                        child: const Icon(Icons.person),
                      ),
                    ),
                  ),

                  // POI Management button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 80,
                    left: 16,
                    child: Semantics(
                      label: 'Add new point of interest',
                      button: true,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: AppColors.mossGreen,
                        foregroundColor: AppColors.surface,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const POIManagementScreen(),
                            ),
                          );
                        },
                        child: const Icon(Icons.add_location),
                      ),
                    ),
                  ),

          // Location status indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: locationAsync.when(
                data: (location) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      location != null ? Icons.my_location : Icons.location_off,
                      color: location != null ? AppColors.mossGreen : AppColors.dangerRed,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      location != null ? 'GPS Active' : 'GPS Off',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: location != null ? AppColors.mossGreen : AppColors.dangerRed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                loading: () => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.urbanBlue),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Locating...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.urbanBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                error: (error, stack) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppColors.dangerRed,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Location Error',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.dangerRed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Map controls
          if (_isMapReady) ...[
                    // Layer switching button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 80,
                      right: 16,
                      child: Semantics(
                        label: 'Switch map layer',
                        button: true,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.urbanBlue,
                          onPressed: _showLayerSelector,
                          child: const Icon(Icons.layers),
                        ),
                      ),
                    ),

                    // POI toggle button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 140,
                      right: 16,
                      child: Semantics(
                        label: mapState.showPOIs ? 'Hide points of interest' : 'Show points of interest',
                        button: true,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: mapState.showPOIs ? AppColors.mossGreen : AppColors.surface,
                          foregroundColor: mapState.showPOIs ? AppColors.surface : AppColors.urbanBlue,
                          onPressed: () {
                            ref.read(mapProvider.notifier).togglePOIs();
                          },
                          child: const Icon(Icons.place),
                        ),
                      ),
                    ),

                    // Route toggle button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 200,
                      right: 16,
                      child: Semantics(
                        label: mapState.showRoutes ? 'Hide cycling routes' : 'Show cycling routes',
                        button: true,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: mapState.showRoutes ? AppColors.signalYellow : AppColors.surface,
                          foregroundColor: mapState.showRoutes ? AppColors.urbanBlue : AppColors.urbanBlue,
                          onPressed: () {
                            ref.read(mapProvider.notifier).toggleRoutes();
                          },
                          child: const Icon(Icons.route),
                        ),
                      ),
                    ),

                    // Warning toggle button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 260,
                      right: 16,
                      child: Semantics(
                        label: mapState.showWarnings ? 'Hide community warnings' : 'Show community warnings',
                        button: true,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: mapState.showWarnings ? AppColors.dangerRed : AppColors.surface,
                          foregroundColor: mapState.showWarnings ? AppColors.surface : AppColors.urbanBlue,
                          onPressed: () {
                            ref.read(mapProvider.notifier).toggleWarnings();
                          },
                          child: const Icon(Icons.warning),
                        ),
                      ),
                    ),

                    // Center on location button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 320,
                      right: 16,
                      child: Semantics(
                        label: 'Center map on current location',
                        button: true,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.urbanBlue,
                          onPressed: _centerOnUserLocation,
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ),

                    // Zoom controls
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 380,
                      right: 16,
                      child: Column(
                        children: [
                          Semantics(
                            label: 'Zoom in',
                            button: true,
                            child: FloatingActionButton(
                              mini: true,
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.urbanBlue,
                              onPressed: () {
                                _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom + 1,
                                );
                              },
                              child: const Icon(Icons.add),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            label: 'Zoom out',
                            button: true,
                            child: FloatingActionButton(
                              mini: true,
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.urbanBlue,
                              onPressed: () {
                                _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom - 1,
                                );
                              },
                              child: const Icon(Icons.remove),
                            ),
                          ),
                        ],
                      ),
                    ),
          ],
        ],
      ),
      floatingActionButton: Semantics(
        label: 'Report a community warning',
        button: true,
        child: FloatingActionButton(
          onPressed: _onReportWarning,
          backgroundColor: AppColors.signalYellow,
          foregroundColor: AppColors.urbanBlue,
          child: const Icon(Icons.warning),
        ),
      ),
    );
  }

  void _onMapTap(LatLng point) {
    // Handle map tap events
    print('Map tapped at: ${point.latitude}, ${point.longitude}');
  }

  void _showLayerSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Map Layer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.urbanBlue,
                ),
              ),
            ),
            ...MapLayerType.values.map((layer) => ListTile(
              leading: Icon(_getLayerIcon(layer)),
              title: Text(_getLayerName(layer)),
              onTap: () {
                ref.read(mapProvider.notifier).changeLayer(layer);
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _getLayerIcon(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return Icons.map;
      case MapLayerType.cycling:
        return Icons.directions_bike;
      case MapLayerType.satellite:
        return Icons.satellite;
    }
  }

  String _getLayerName(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return 'OpenStreetMap';
      case MapLayerType.cycling:
        return 'Cycling';
      case MapLayerType.satellite:
        return 'Satellite';
    }
  }

  List<Polyline> _buildRoutePolylines(List<Map<String, dynamic>> routes) {
    return routes.map((route) {
      final waypoints = route['waypoints'] as List<LatLng>;
      return Polyline(
        points: waypoints,
        color: Color(route['color'] as int),
        strokeWidth: 4.0,
        // Note: Pattern support varies by flutter_map version
        // pattern: route['type'] == 'commute' ? [10, 5] : null,
      );
    }).toList();
  }

  List<Marker> _buildPOIMarkers(List<Map<String, dynamic>> pois) {
    return pois.map((poi) {
      final position = poi['position'] as LatLng;
      return Marker(
        point: position,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showPOIDetails(poi),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.mossGreen,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                poi['icon'] as String,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildPOIMarkersFromFirestore(List<dynamic> pois) {
    return pois.map((poi) {
      final position = LatLng(poi.latitude, poi.longitude);
      return Marker(
        point: position,
        width: 40,
        height: 40,
        child: Semantics(
          label: 'Point of interest: ${poi.name}',
          button: true,
          child: GestureDetector(
            onTap: () => _showPOIDetailsFromFirestore(poi),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.mossGreen,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _getPOIIcon(poi.type),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildWarningMarkers(List<Map<String, dynamic>> warnings) {
    return warnings.map((warning) {
      final position = warning['position'] as LatLng;
      final severity = warning['severity'] as String;
      Color color = AppColors.dangerRed;
      if (severity == 'medium') color = AppColors.signalYellow;
      if (severity == 'low') color = AppColors.mossGreen;

      return Marker(
        point: position,
        width: 30,
        height: 30,
        child: GestureDetector(
          onTap: () => _showWarningDetails(warning),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                warning['icon'] as String,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildWarningMarkersFromFirestore(List<dynamic> warnings) {
    return warnings.map((warning) {
      final position = LatLng(warning.latitude, warning.longitude);
      final severity = warning.severity as String;
      Color color = AppColors.dangerRed;
      if (severity == 'medium') color = AppColors.signalYellow;
      if (severity == 'low') color = AppColors.mossGreen;

      return Marker(
        point: position,
        width: 30,
        height: 30,
        child: Semantics(
          label: 'Community warning: ${warning.title} (${warning.severity} severity)',
          button: true,
          child: GestureDetector(
            onTap: () => _showWarningDetailsFromFirestore(warning),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _getWarningIcon(warning.type),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _showPOIDetails(Map<String, dynamic> poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi['name'] as String),
        content: Text(poi['description'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showWarningDetails(Map<String, dynamic> warning) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${warning['icon']} ${warning['type']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warning['description'] as String),
            const SizedBox(height: 8),
            Text(
              'Severity: ${warning['severity']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Reported: ${_formatDateTime(warning['reportedAt'] as DateTime)}',
              style: const TextStyle(fontSize: 12, color: AppColors.lightGrey),
            ),
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

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  void _showPOIDetailsFromFirestore(dynamic poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (poi.description != null) Text(poi.description),
            const SizedBox(height: 8),
            Text('Type: ${poi.type}'),
            if (poi.address != null) Text('Address: ${poi.address}'),
            if (poi.phone != null) Text('Phone: ${poi.phone}'),
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

  void _showWarningDetailsFromFirestore(dynamic warning) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_getWarningIcon(warning.type)} ${warning.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warning.description),
            const SizedBox(height: 8),
            Text(
              'Severity: ${warning.severity}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Reported: ${_formatDateTime(warning.reportedAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.lightGrey),
            ),
            if (warning.reportedBy != null)
              Text(
                'By: ${warning.reportedBy}',
                style: const TextStyle(fontSize: 12, color: AppColors.lightGrey),
              ),
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

  String _getPOIIcon(String type) {
    switch (type) {
      case 'bike_shop':
        return '🏪';
      case 'parking':
        return '🚲';
      case 'repair_station':
        return '🔧';
      case 'water_fountain':
        return '💧';
      case 'rest_area':
        return '🪑';
      default:
        return '📍';
    }
  }

  String _getWarningIcon(String type) {
    switch (type) {
      case 'hazard':
        return '⚠️';
      case 'construction':
        return '🚧';
      case 'road_closure':
        return '🚫';
      case 'poor_condition':
        return '🕳️';
      case 'traffic':
        return '🚗';
      case 'weather':
        return '🌧️';
      default:
        return '⚠️';
    }
  }

  @override
  void dispose() {
    // flutter_map MapController doesn't need explicit disposal
    super.dispose();
  }
}
