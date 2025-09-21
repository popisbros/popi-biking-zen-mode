import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../models/location_data.dart';
import '../providers/location_provider.dart';
import '../providers/map_provider.dart';
import '../providers/community_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../models/community_warning.dart';
import '../services/map_service.dart';
import '../utils/poi_icons.dart';
import '../models/cycling_poi.dart';
import 'community/poi_management_screen.dart';
import 'community/hazard_report_screen.dart';
import '../widgets/debug_panel.dart';
import '../widgets/osm_debug_window.dart';
import '../services/debug_service.dart';
import '../services/osm_debug_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final MapService _mapService = MapService();
  final DebugService _debugService = DebugService();
  final OSMDebugService _osmDebugService = OSMDebugService();
  
  bool _isMapReady = false;
  bool _isDebugPanelOpen = false;
  bool _showMobileHint = false;
  bool _showOSMDebugWindow = false;
  Timer? _debounceTimer;
  
  // Smart reload logic - store loaded bounds and buffer zone
  BoundingBox? _lastLoadedBounds;
  BoundingBox? _reloadTriggerBounds;
  
  late AnimationController _debugPanelAnimationController;
  late Animation<double> _debugPanelAnimation;

  @override
  void initState() {
    super.initState();
    
    _debugPanelAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _debugPanelAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _debugPanelAnimationController,
      curve: Curves.easeInOut,
    ));

    _initializeLocation();
    _initializeMap();
    _debugService.logAction(action: 'Map Screen: Initialized');
  }

  @override
  void dispose() {
    _debugPanelAnimationController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    // Request location permission and start tracking
    final locationNotifier = ref.read(locationNotifierProvider.notifier);
    await locationNotifier.requestPermission();
    await locationNotifier.startTracking();
    
    // Force get current position and center map
    _debugService.logAction(action: 'GPS: Forcing current position');
    await _centerOnUserLocation();
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
    
    // Show mobile hint for touchscreen users
    final isMobile = Theme.of(context).platform == TargetPlatform.iOS || 
                     Theme.of(context).platform == TargetPlatform.android;
    if (isMobile) {
      setState(() {
        _showMobileHint = true;
      });
      // Hide hint after 4 seconds
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _showMobileHint = false;
          });
        }
      });
    }
  }

  Future<void> _centerOnUserLocation() async {
    final locationAsync = ref.read(locationNotifierProvider);
    locationAsync.whenData((location) {
      if (location != null) {
        _debugService.logAction(
          action: 'Map: Centering on GPS location',
          parameters: {
            'latitude': location.latitude,
            'longitude': location.longitude,
          },
        );
        _mapController.move(
          LatLng(location.latitude, location.longitude),
          15.0,
        );
        
        // Wait a bit for the map to settle, then load all map data with actual bounds
        Future.delayed(const Duration(milliseconds: 500), () {
          _loadAllMapDataWithBounds();
        });
      } else {
        _debugService.logAction(action: 'Map: GPS location not available');
      }
    });
  }
  
  
  /// Calculate extended bounds that are bigger than the visible map
  BoundingBox _calculateExtendedBounds(LatLngBounds visibleBounds) {
    // Calculate the dimensions of the visible area
    final latDiff = visibleBounds.north - visibleBounds.south;
    final lngDiff = visibleBounds.east - visibleBounds.west;
    
    // Extend by the same distance as the visible map dimensions
    // This creates a loading area that's 3x3 times the visible area
    final latExtension = latDiff; // Extend by full visible height
    final lngExtension = lngDiff; // Extend by full visible width
    
    return BoundingBox(
      south: visibleBounds.south - latExtension,
      west: visibleBounds.west - lngExtension,
      north: visibleBounds.north + latExtension,
      east: visibleBounds.east + lngExtension,
    );
  }

  /// Calculate reload trigger bounds (10% buffer zone from loaded bounds)
  BoundingBox _calculateReloadTriggerBounds(BoundingBox loadedBounds) {
    // Calculate 10% buffer zone
    final latDiff = loadedBounds.north - loadedBounds.south;
    final lngDiff = loadedBounds.east - loadedBounds.west;
    
    final latBuffer = latDiff * 0.1; // 10% buffer
    final lngBuffer = lngDiff * 0.1; // 10% buffer
    
    return BoundingBox(
      south: loadedBounds.south + latBuffer,
      west: loadedBounds.west + lngBuffer,
      north: loadedBounds.north - latBuffer,
      east: loadedBounds.east - lngBuffer,
    );
  }

  /// Check if current visible bounds are within the reload trigger zone
  bool _shouldReloadData(LatLngBounds visibleBounds) {
    if (_reloadTriggerBounds == null) {
      return true; // First load
    }
    
    // Check if any part of the visible bounds is outside the trigger zone
    return visibleBounds.south < _reloadTriggerBounds!.south ||
           visibleBounds.north > _reloadTriggerBounds!.north ||
           visibleBounds.west < _reloadTriggerBounds!.west ||
           visibleBounds.east > _reloadTriggerBounds!.east;
  }

  /// Load all map data (OSM POIs, Hazards, POIs) using extended bounds with smart reload logic
  void _loadAllMapDataWithBounds() {
    if (!_isMapReady) {
      print('Map Screen: Map not ready, skipping map data load');
      return;
    }
    
    try {
      // Get the actual visible bounds from the map controller camera
      final camera = _mapController.camera;
      final latLngBounds = camera.visibleBounds;
      
      // Check if we should reload data based on smart reload logic
      if (!_shouldReloadData(latLngBounds)) {
        print('Map Screen: Within loaded bounds, skipping reload');
        return;
      }
      
      // Calculate extended bounds (bigger than visible map)
      final extendedBounds = _calculateExtendedBounds(latLngBounds);
      
      print('Map Screen: Loading all map data with extended bounds:');
      print('  Visible - South: ${latLngBounds.south}, North: ${latLngBounds.north}');
      print('  Visible - West: ${latLngBounds.west}, East: ${latLngBounds.east}');
      print('  Extended - South: ${extendedBounds.south}, North: ${extendedBounds.north}');
      print('  Extended - West: ${extendedBounds.west}, East: ${extendedBounds.east}');
      
      // Load OSM POIs
      final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
      osmPOIsNotifier.loadPOIsWithBounds(extendedBounds);
      
      // Load Hazards
      final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
      warningsNotifier.loadWarningsWithBounds(extendedBounds);
      
      // Load POIs
      final poisNotifier = ref.read(cyclingPOIsBoundsNotifierProvider.notifier);
      poisNotifier.loadPOIsWithBounds(extendedBounds);
      
      // Update stored bounds for smart reload logic
      _lastLoadedBounds = extendedBounds;
      _reloadTriggerBounds = _calculateReloadTriggerBounds(extendedBounds);
      
      print('Map Screen: Updated reload trigger bounds:');
      print('  Trigger - South: ${_reloadTriggerBounds!.south}, North: ${_reloadTriggerBounds!.north}');
      print('  Trigger - West: ${_reloadTriggerBounds!.west}, East: ${_reloadTriggerBounds!.east}');
      
    } catch (e) {
      print('Map Screen: Error loading map data with bounds: $e');
    }
  }
  
  /// Handle map events (movement, zoom, etc.)
  void _onMapEvent(MapEvent mapEvent) {
    // Only reload map data on significant map changes
    if (mapEvent is MapEventMove || mapEvent is MapEventMoveStart || mapEvent is MapEventMoveEnd) {
      // Debounce the reload to avoid too many API calls
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
        if (_isMapReady) {
          print('Map Screen: Map moved, reloading all map data with new bounds');
          _loadAllMapDataWithBounds();
        }
      });
    }
  }

  void _showDebugPanel() {
    setState(() {
      _isDebugPanelOpen = true;
    });
    
    _debugPanelAnimationController.forward().then((_) {
      // Animation completed
    });
  }

  void _hideDebugPanel() {
    _debugPanelAnimationController.reverse().then((_) {
      setState(() {
        _isDebugPanelOpen = false;
      });
    });
  }

  void _showMapStyleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Select Map Style',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.urbanBlue,
              ),
            ),
            const SizedBox(height: 20),
            // Map style options
            _buildMapStyleOption('Cycling', MapLayerType.cycling, Icons.directions_bike),
            _buildMapStyleOption('OpenStreetMap', MapLayerType.openStreetMap, Icons.map),
            _buildMapStyleOption('Satellite', MapLayerType.satellite, Icons.satellite),
          ],
        ),
      ),
    );
  }

  Widget _buildMapStyleOption(String title, MapLayerType layerType, IconData icon) {
    final mapState = ref.watch(mapProvider);
    final isSelected = mapState.currentLayer == layerType;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.mossGreen : AppColors.urbanBlue,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? AppColors.mossGreen : AppColors.urbanBlue,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check, color: AppColors.mossGreen) : null,
      onTap: () {
        ref.read(mapProvider.notifier).changeLayer(layerType);
        Navigator.pop(context);
      },
    );
  }

  void _onMapTap(LatLng point) {
    _debugService.logAction(
      action: 'Map Tap',
      screen: 'MapScreen',
      parameters: {
        'latitude': point.latitude,
        'longitude': point.longitude,
      },
    );
    print('Map tapped at: ${point.latitude}, ${point.longitude}');
  }

  void _onPOITap(poi) {
    _debugService.logAction(
      action: 'POI Tap',
      screen: 'MapScreen',
      parameters: {
        'poi_id': poi.id,
        'poi_name': poi.name,
        'poi_type': poi.type,
      },
    );
    print('POI tapped: ${poi.name} (${poi.type})');
    
    // Show enhanced POI details dialog
    _showEnhancedPOIDialog(poi);
  }
  
  void _showEnhancedPOIDialog(dynamic poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(POIIcons.getPOIIcon(poi.type), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(child: Text(poi.name)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldRow('Type', poi.type),
              _buildFieldRow('Location', '${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}'),
              if (poi.description != null && poi.description!.isNotEmpty) 
                _buildFieldRow('Description', poi.description!),
              if (poi.address != null && poi.address!.isNotEmpty) 
                _buildFieldRow('Address', poi.address!),
              if (poi.phone != null && poi.phone!.isNotEmpty) 
                _buildFieldRow('Phone', poi.phone!),
              if (poi.website != null && poi.website!.isNotEmpty) 
                _buildFieldRow('Website', poi.website!),
              if (poi.createdAt != null) 
                _buildFieldRow('Created', _formatDateTime(poi.createdAt)),
              if (poi.updatedAt != null) 
                _buildFieldRow('Updated', _formatDateTime(poi.updatedAt)),
              if (poi.id != null && poi.id!.isNotEmpty) 
                _buildFieldRow('ID', poi.id!),
              
              // OSM-specific fields
              if (poi is OSMPOI) ...[
                const Divider(),
                const Text('OSM Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                _buildFieldRow('OSM ID', poi.osmId),
                _buildFieldRow('OSM Type', poi.osmType),
                if (poi.osmTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('OSM Tags:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...poi.osmTags.entries.map((entry) => 
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 2),
                      child: Text('${entry.key}: ${entry.value}'),
                    ),
                  ),
                ],
              ],
              
              // Metadata
              if (poi.metadata != null && poi.metadata!.isNotEmpty) ...[
                const Divider(),
                const Text('Additional Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ...poi.metadata!.entries.map((entry) => 
                  _buildFieldRow(entry.key, entry.value.toString()),
                ),
              ],
            ],
          ),
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

  void _onWarningTap(warning) {
    _debugService.logAction(
      action: 'Warning Tap',
      screen: 'MapScreen',
      parameters: {
        'warning_id': warning.id,
        'warning_type': warning.type,
        'warning_description': warning.description,
      },
    );
    print('Warning tapped: ${warning.type} - ${warning.description}');
    
    // Show enhanced warning details dialog
    _showEnhancedWarningDialog(warning);
  }
  
  void _showEnhancedWarningDialog(CommunityWarning warning) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: _getSeverityColor(warning.severity), size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text('Hazard: ${warning.title}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldRow('Type', warning.type),
              _buildFieldRow('Severity', warning.severity.toUpperCase()),
              _buildFieldRow('Description', warning.description),
              _buildFieldRow('Location', '${warning.latitude.toStringAsFixed(6)}, ${warning.longitude.toStringAsFixed(6)}'),
              _buildFieldRow('Reported', _formatDateTime(warning.reportedAt)),
              if (warning.reportedBy != null && warning.reportedBy!.isNotEmpty) 
                _buildFieldRow('Reported By', warning.reportedBy!),
              if (warning.expiresAt != null) 
                _buildFieldRow('Expires', _formatDateTime(warning.expiresAt!)),
              _buildFieldRow('Status', warning.isActive ? 'Active' : 'Inactive'),
              if (warning.id != null && warning.id!.isNotEmpty) 
                _buildFieldRow('ID', warning.id!),
              
              // Tags
              if (warning.tags != null && warning.tags!.isNotEmpty) ...[
                const Divider(),
                const Text('Tags', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Wrap(
                  children: warning.tags!.map((tag) => 
                    Container(
                      margin: const EdgeInsets.only(right: 4, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.urbanBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(tag, style: const TextStyle(fontSize: 12)),
                    ),
                  ).toList(),
                ),
              ],
              
              // Metadata
              if (warning.metadata != null && warning.metadata!.isNotEmpty) ...[
                const Divider(),
                const Text('Additional Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ...warning.metadata!.entries.map((entry) => 
                  _buildFieldRow(entry.key, entry.value.toString()),
                ),
              ],
            ],
          ),
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

  /// Helper method to build a field row in dialogs
  Widget _buildFieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  /// Helper method to format DateTime for display
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
  
  /// Helper method to get color based on severity
  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'low':
        return AppColors.mossGreen;
      case 'medium':
        return AppColors.signalYellow;
      case 'high':
        return AppColors.warningOrange;
      case 'critical':
        return AppColors.dangerRed;
      default:
        return AppColors.lightGrey;
    }
  }

  void _onMapLongPressFromTap(TapPosition tapPosition, LatLng point) {
    // Handle long press events from FlutterMap's onLongPress - show context menu
    if (!_isMapReady) return;
    
    // Provide haptic feedback for mobile users
    HapticFeedback.mediumImpact();
    
    _debugService.logAction(
      action: 'Map Long Press',
      screen: 'MapScreen',
      parameters: {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'platform': 'flutter_map',
      },
    );
    print('Map long-pressed at: ${point.latitude}, ${point.longitude}');
    
    _showContextMenu(tapPosition, point);
  }

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
              Icon(Icons.add_location, color: AppColors.mossGreen),
              const SizedBox(width: 8),
              const Text('Add New POI'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'report_hazard',
          child: Row(
            children: [
              Icon(Icons.warning, color: AppColors.warningOrange),
              const SizedBox(width: 8),
              const Text('Report Hazard'),
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
            _openPOIManagementWithLocation(point);
            break;
          case 'report_hazard':
            _openHazardReportWithLocation(point);
            break;
        }
      }
    });
  }

  void _openPOIManagementWithLocation(LatLng point) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => POIManagementScreenWithLocation(
          initialLatitude: point.latitude,
          initialLongitude: point.longitude,
        ),
      ),
    );
  }

  void _openHazardReportWithLocation(LatLng point) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HazardReportScreenWithLocation(
          initialLatitude: point.latitude,
          initialLongitude: point.longitude,
        ),
      ),
    );
  }

  /// Auto-center map on GPS location when it changes
  void _handleGPSLocationChange(LocationData? location) {
    if (location != null && _isMapReady) {
      final newCenter = LatLng(location.latitude, location.longitude);
      final currentCenter = _mapController.camera.center;
      
      // Calculate distance between current center and new GPS location
      final distance = _calculateDistance(
        currentCenter.latitude, currentCenter.longitude,
        newCenter.latitude, newCenter.longitude,
      );
      
      // Only auto-center if GPS location has moved significantly (more than 50 meters)
      if (distance > 50) {
        print('Map Screen: Auto-centering map on GPS location change (distance: ${distance.toStringAsFixed(1)}m)');
        _mapController.move(newCenter, _mapController.camera.zoom);
        
        // Reload map data with new center
        _loadAllMapDataWithBounds();
      }
    }
  }

  /// Calculate distance between two points in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationNotifierProvider);
    final mapState = ref.watch(mapProvider);
    final warningsAsync = ref.watch(communityWarningsBoundsNotifierProvider);
    final poisAsync = ref.watch(cyclingPOIsBoundsNotifierProvider);
    final osmPOIsAsync = ref.watch(osmPOIsNotifierProvider);

    // Auto-center map on GPS location changes
    locationAsync.whenData((location) {
      _handleGPSLocationChange(location);
    });

    return Scaffold(
      body: Stack(
        children: [
          // Enhanced Flutter Map with cycling features
          SizedBox(
            width: double.infinity,
            height: _isDebugPanelOpen 
                ? MediaQuery.of(context).size.height * 0.7 
                : MediaQuery.of(context).size.height,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapState.center,
                initialZoom: mapState.zoom,
                minZoom: 10.0,
                maxZoom: 20.0,
                onMapReady: () => _onMapReady(),
                onTap: (tapPosition, point) => _onMapTap(point),
                onLongPress: (tapPosition, point) => _onMapLongPressFromTap(tapPosition, point),
                onMapEvent: (mapEvent) => _onMapEvent(mapEvent),
              ),
              children: [
                // Dynamic tile layer based on current selection
                TileLayer(
                  urlTemplate: mapState.tileUrl,
                  userAgentPackageName: _mapService.userAgent,
                  maxZoom: 20,
                ),
                
                // POI markers
                if (mapState.showPOIs)
                  MarkerLayer(
                    markers: poisAsync.when(
                      data: (pois) => pois.map((poi) => _buildPOIMarker(poi)).toList(),
                      loading: () => [],
                      error: (_, __) => [],
                    ),
                  ),
                
                // OSM POI markers
                if (mapState.showOSMPOIs)
                  MarkerLayer(
                    markers: osmPOIsAsync.when(
                      data: (osmPOIs) => osmPOIs.map((poi) => _buildOSMPOIMarker(poi)).toList(),
                      loading: () => [],
                      error: (_, __) => [],
                    ),
                  ),
                
                // Warning markers
                if (mapState.showWarnings)
                  MarkerLayer(
                    markers: warningsAsync.when(
                      data: (warnings) => warnings.map((warning) => _buildWarningMarker(warning)).toList(),
                      loading: () => [],
                      error: (_, __) => [],
                    ),
                  ),
                
                // GPS location marker
                MarkerLayer(
                  markers: locationAsync.when(
                    data: (location) => location != null ? [_buildGPSLocationMarker(location)] : [],
                    loading: () => [],
                    error: (_, __) => [],
                  ),
                ),
              ],
            ),
          ),

          // Profile button
          if (_isMapReady)
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
                    _debugService.logButtonClick('Profile', screen: 'MapScreen');
                    // TODO: Navigate to profile screen
                  },
                  child: const Icon(Icons.person),
                ),
              ),
            ),

          // Map style selector button
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 66,
              right: 16,
              child: Semantics(
                label: 'Change map style',
                button: true,
                child: Tooltip(
                  message: 'Change map style',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.urbanBlue,
                    onPressed: () {
                      _debugService.logButtonClick('Map Layer Switch', screen: 'MapScreen');
                      _showMapStyleSelector();
                    },
                    child: const Icon(Icons.layers),
                  ),
                ),
              ),
            ),

          // Debug button
          Positioned(
            bottom: 16,
            left: 16,
            child: Semantics(
              label: 'Open debug screen',
              button: true,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: AppColors.warningOrange,
                foregroundColor: AppColors.surface,
                onPressed: () {
                  _debugService.logButtonClick('Debug Panel', screen: 'MapScreen');
                  _showDebugPanel();
                },
                child: const Icon(Icons.bug_report),
              ),
            ),
          ),

          // OSM Debug button
          Positioned(
            bottom: 16,
            left: 80,
            child: Semantics(
              label: 'Open OSM debug window',
              button: true,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: AppColors.lightGrey,
                foregroundColor: AppColors.surface,
                onPressed: () {
                  _debugService.logButtonClick('OSM Debug Window', screen: 'MapScreen');
                  setState(() {
                    _showOSMDebugWindow = !_showOSMDebugWindow;
                  });
                },
                child: const Icon(Icons.api),
              ),
            ),
          ),

          // Map controls
          if (_isMapReady) ...[
            // POI toggle button with count
            Positioned(
              top: MediaQuery.of(context).padding.top + 116,
              right: 16,
              child: Semantics(
                label: mapState.showPOIs ? 'Hide points of interest' : 'Show points of interest',
                button: true,
                child: Tooltip(
                  message: 'Toggle POI visibility',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: mapState.showPOIs ? AppColors.mossGreen : AppColors.lightGrey,
                    foregroundColor: AppColors.surface,
                    onPressed: () {
                      _debugService.logButtonClick('POI Toggle', screen: 'MapScreen');
                      ref.read(mapProvider.notifier).togglePOIs();
                    },
                    child: const Icon(Icons.location_on),
                  ),
                ),
              ),
            ),

            // OSM POI toggle button
            Positioned(
              top: MediaQuery.of(context).padding.top + 166,
              right: 16,
              child: Semantics(
                label: mapState.showOSMPOIs ? 'Hide OSM POIs' : 'Show OSM POIs',
                button: true,
                child: Tooltip(
                  message: 'Toggle OSM POI visibility',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: mapState.showOSMPOIs ? AppColors.azureBlue : AppColors.azureBlue.withValues(alpha: 0.5),
                    foregroundColor: AppColors.surface,
                    onPressed: () {
                      _debugService.logButtonClick('OSM POI Toggle', screen: 'MapScreen');
                      ref.read(mapProvider.notifier).toggleOSMPOIs();
                    },
                    child: const Icon(Icons.public),
                  ),
                ),
              ),
            ),

            // Warning toggle button with count
            Positioned(
              top: MediaQuery.of(context).padding.top + 216,
              right: 16,
              child: Semantics(
                label: mapState.showWarnings ? 'Hide community warnings' : 'Show community warnings',
                button: true,
                child: Tooltip(
                  message: 'Toggle warning visibility',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: mapState.showWarnings ? AppColors.warningOrange : AppColors.lightGrey,
                    foregroundColor: AppColors.surface,
                    onPressed: () {
                      _debugService.logButtonClick('Warning Toggle', screen: 'MapScreen');
                      ref.read(mapProvider.notifier).toggleWarnings();
                    },
                    child: const Icon(Icons.warning),
                  ),
                ),
              ),
            ),

            // Route toggle button
            Positioned(
              top: MediaQuery.of(context).padding.top + 266,
              right: 16,
              child: Semantics(
                label: mapState.showRoutes ? 'Hide cycling routes' : 'Show cycling routes',
                button: true,
                child: Tooltip(
                  message: 'Toggle route visibility',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: mapState.showRoutes ? AppColors.signalYellow : AppColors.lightGrey,
                    foregroundColor: AppColors.surface,
                    onPressed: () {
                      _debugService.logButtonClick('Route Toggle', screen: 'MapScreen');
                      ref.read(mapProvider.notifier).toggleRoutes();
                    },
                    child: const Icon(Icons.route),
                  ),
                ),
              ),
            ),

            // GPS current location button
            Positioned(
              top: MediaQuery.of(context).padding.top + 316,
              right: 16,
              child: Semantics(
                label: 'Center map on current location',
                button: true,
                child: Tooltip(
                  message: 'Center map on current location',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.urbanBlue,
                    onPressed: () {
                      _debugService.logButtonClick('GPS Center', screen: 'MapScreen');
                      _centerOnUserLocation();
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ),
            ),

            // Zoom controls
            Positioned(
              top: MediaQuery.of(context).padding.top + 366,
              right: 16,
              child: Column(
                children: [
                  // Zoom in button
                  Semantics(
                    label: 'Zoom in',
                    button: true,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.urbanBlue,
                      onPressed: () {
                        _debugService.logButtonClick('Zoom In', screen: 'MapScreen');
                        _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        );
                      },
                      child: const Icon(Icons.add),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Zoom out button
                  Semantics(
                    label: 'Zoom out',
                    button: true,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.urbanBlue,
                      onPressed: () {
                        _debugService.logButtonClick('Zoom Out', screen: 'MapScreen');
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

          // GPS Status indicator
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: locationAsync.when(
                  data: (location) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        location != null ? Icons.gps_fixed : Icons.gps_off,
                        color: location != null ? AppColors.mossGreen : AppColors.dangerRed,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        location != null ? 'GPS Active' : 'GPS Offline',
                        style: TextStyle(
                          color: location != null ? AppColors.mossGreen : AppColors.dangerRed,
                          fontSize: 12,
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
                        'GPS Loading...',
                        style: TextStyle(
                          color: AppColors.urbanBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.gps_off,
                        color: AppColors.dangerRed,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'GPS Error',
                        style: TextStyle(
                          color: AppColors.dangerRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // POI Status indicator
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: poisAsync.when(
                  data: (pois) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppColors.mossGreen,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'POIs: ${pois.length}',
                        style: TextStyle(
                          color: AppColors.mossGreen,
                          fontSize: 12,
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.mossGreen),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'POIs Loading...',
                        style: TextStyle(
                          color: AppColors.mossGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_off,
                        color: AppColors.dangerRed,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'POIs Error',
                        style: TextStyle(
                          color: AppColors.dangerRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Hazard Status indicator
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 104,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: warningsAsync.when(
                  data: (warnings) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning,
                        color: AppColors.warningOrange,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Hazards: ${warnings.length}',
                        style: TextStyle(
                          color: AppColors.warningOrange,
                          fontSize: 12,
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.warningOrange),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Hazards Loading...',
                        style: TextStyle(
                          color: AppColors.warningOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning,
                        color: AppColors.dangerRed,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Hazards Error',
                        style: TextStyle(
                          color: AppColors.dangerRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // OSM POI Status indicator
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 148,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: osmPOIsAsync.when(
                  data: (osmPOIs) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.public,
                        color: AppColors.azureBlue,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'OSM: ${osmPOIs.length}',
                        style: TextStyle(
                          color: AppColors.lightGrey,
                          fontSize: 12,
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.lightGrey),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'OSM Loading...',
                        style: TextStyle(
                          color: AppColors.lightGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.public_off,
                        color: AppColors.dangerRed,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'OSM Error',
                        style: TextStyle(
                          color: AppColors.dangerRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Mobile hint for long press
          if (_showMobileHint)
            Positioned(
              bottom: 200,
              left: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: _showMobileHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.urbanBlue.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app,
                        color: AppColors.surface,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Long press anywhere on the map to add POIs or report hazards',
                          style: TextStyle(
                            color: AppColors.surface,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showMobileHint = false;
                          });
                        },
                        icon: Icon(
                          Icons.close,
                          color: AppColors.surface,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Debug panel - slides from bottom
          if (_isDebugPanelOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _debugPanelAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, MediaQuery.of(context).size.height * 0.5 * (1 - _debugPanelAnimation.value)),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      width: MediaQuery.of(context).size.width,
                      child: DebugPanel(
                        onClose: _hideDebugPanel,
                        onReloadOSMPOIs: _loadAllMapDataWithBounds,
                      ),
                    ),
                  );
                },
              ),
            ),

          // OSM Debug Window - slides from bottom
          if (_showOSMDebugWindow)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: OSMDebugWindow(
                onClose: () {
                  setState(() {
                    _showOSMDebugWindow = false;
                  });
                },
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // POI Creation Button
          Semantics(
            label: 'Add new point of interest',
            button: true,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: AppColors.mossGreen,
              foregroundColor: AppColors.surface,
              onPressed: () {
                _debugService.logButtonClick('Add POI', screen: 'MapScreen');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const POIManagementScreen(),
                  ),
                );
              },
              child: const Icon(Icons.add_location),
            ),
          ),
          const SizedBox(height: 16),
          
          // Hazard Report Button
          Semantics(
            label: 'Report hazard or warning',
            button: true,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: AppColors.warningOrange,
              foregroundColor: AppColors.surface,
              onPressed: () {
                _debugService.logButtonClick('Report Hazard', screen: 'MapScreen');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HazardReportScreen(),
                  ),
                );
              },
              child: const Icon(Icons.warning),
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildPOIMarker(poi) {
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: 30,
      height: 40,
      alignment: Alignment.topCenter, // Align top center of icon with POI location
      child: GestureDetector(
        onTap: () => _onPOITap(poi),
        child: SizedBox(
          width: 30,
          height: 40,
          child: CustomPaint(
            painter: POITeardropPinPainter(),
            child: Positioned(
              top: 12, // 30% of 40px height = 12px from top
              left: 0,
              right: 0,
              child: Text(
                POIIcons.getPOIIcon(poi.type),
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildWarningMarker(warning) {
    return Marker(
      point: LatLng(warning.latitude, warning.longitude),
      width: 30,
      height: 40,
      alignment: Alignment.topCenter, // Align top center of icon with warning location
      child: GestureDetector(
        onTap: () => _onWarningTap(warning),
        child: SizedBox(
          width: 30,
          height: 40,
          child: CustomPaint(
            painter: WarningTeardropPinPainter(),
            child: Positioned(
              top: 12, // 30% of 40px height = 12px from top
              left: 0,
              right: 0,
              child: Text(
                POIIcons.getHazardIcon(warning.type),
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildOSMPOIMarker(OSMPOI poi) {
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: 30,
      height: 40,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => _onPOITap(poi), // Use the same enhanced dialog
        child: SizedBox(
          width: 30,
          height: 40,
          child: CustomPaint(
            painter: OSMTeardropPinPainter(),
            child: Positioned(
              top: 12, // 30% of 40px height = 12px from top
              left: 0,
              right: 0,
              child: Text(
                POIIcons.getPOIIcon(poi.type),
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildGPSLocationMarker(LocationData location) {
    return Marker(
      point: LatLng(location.latitude, location.longitude),
      width: 30,
      height: 40,
      alignment: Alignment.topCenter, // Align top center of icon with GPS location
        child: SizedBox(
          width: 30,
          height: 40,
          child: CustomPaint(
            painter: TeardropPinPainter(),
            child: Positioned(
              top: 12, // 30% of 40px height = 12px from top
              left: 0,
              right: 0,
              child: const Icon(
                Icons.directions_bike,
                color: AppColors.urbanBlue,
                size: 16,
              ),
            ),
          ),
        ),
    );
  }
}

// POI Teardrop Pin Painter - using correct mossGreen color
class POITeardropPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mossGreen // Use the correct mossGreen color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = AppColors.mossGreen.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Create teardrop path using dart:ui Path
    final path = ui.Path();
    
    // Start from the top center
    path.moveTo(size.width / 2, 0);
    
    // Create the rounded top (semicircle)
    path.arcToPoint(
      Offset(size.width, size.height * 0.3),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    // Create the sides of the teardrop
    path.lineTo(size.width * 0.7, size.height * 0.8);
    
    // Create the pointed bottom
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width * 0.3, size.height * 0.8);
    
    // Complete the teardrop shape
    path.lineTo(0, size.height * 0.3);
    path.arcToPoint(
      Offset(size.width / 2, 0),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    path.close();

    // Draw shadow first (slightly offset)
    final shadowPath = ui.Path.from(path);
    shadowPath.shift(const Offset(1, 2));
    canvas.drawPath(shadowPath, shadowPaint);

    // Draw the main teardrop
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Warning Teardrop Pin Painter - using correct warningOrange color
class WarningTeardropPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.warningOrange // Use the correct warningOrange color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = AppColors.warningOrange.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Create teardrop path using dart:ui Path
    final path = ui.Path();
    
    // Start from the top center
    path.moveTo(size.width / 2, 0);
    
    // Create the rounded top (semicircle)
    path.arcToPoint(
      Offset(size.width, size.height * 0.3),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    // Create the sides of the teardrop
    path.lineTo(size.width * 0.7, size.height * 0.8);
    
    // Create the pointed bottom
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width * 0.3, size.height * 0.8);
    
    // Complete the teardrop shape
    path.lineTo(0, size.height * 0.3);
    path.arcToPoint(
      Offset(size.width / 2, 0),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    path.close();

    // Draw shadow first (slightly offset)
    final shadowPath = ui.Path.from(path);
    shadowPath.shift(const Offset(1, 2));
    canvas.drawPath(shadowPath, shadowPaint);

    // Draw the main teardrop
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// GPS Teardrop Pin Painter
class TeardropPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.lightGrey // Grey color for GPS position
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = AppColors.lightGrey.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Create teardrop path using dart:ui Path
    final path = ui.Path();
    
    // Start from the top center
    path.moveTo(size.width / 2, 0);
    
    // Create the rounded top (semicircle)
    path.arcToPoint(
      Offset(size.width, size.height * 0.3),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    // Create the sides of the teardrop
    path.lineTo(size.width * 0.7, size.height * 0.8);
    
    // Create the pointed bottom
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width * 0.3, size.height * 0.8);
    
    // Complete the teardrop shape
    path.lineTo(0, size.height * 0.3);
    path.arcToPoint(
      Offset(size.width / 2, 0),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    path.close();

    // Draw shadow first (slightly offset)
    final shadowPath = ui.Path.from(path);
    shadowPath.shift(const Offset(1, 2));
    canvas.drawPath(shadowPath, shadowPaint);

    // Draw the main teardrop
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// OSM Teardrop Pin Painter - grey color
class OSMTeardropPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.azureBlue // Azure Blue color for OSM POIs
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = AppColors.lightGrey.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Create teardrop path using dart:ui Path
    final path = ui.Path();
    
    // Start from the top center
    path.moveTo(size.width / 2, 0);
    
    // Create the rounded top (semicircle)
    path.arcToPoint(
      Offset(size.width, size.height * 0.3),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    // Create the sides of the teardrop
    path.lineTo(size.width * 0.7, size.height * 0.8);
    
    // Create the pointed bottom
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width * 0.3, size.height * 0.8);
    
    // Complete the teardrop shape
    path.lineTo(0, size.height * 0.3);
    path.arcToPoint(
      Offset(size.width / 2, 0),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    
    path.close();

    // Draw shadow first (slightly offset)
    final shadowPath = ui.Path.from(path);
    shadowPath.shift(const Offset(1, 2));
    canvas.drawPath(shadowPath, shadowPaint);

    // Draw the main teardrop
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}