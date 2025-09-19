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
import '../services/map_service.dart';
import 'community/poi_management_screen.dart';
import 'community/hazard_report_screen.dart';
import '../widgets/debug_panel.dart';
import '../services/debug_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final MapService _mapService = MapService();
  final DebugService _debugService = DebugService();
  
  bool _isMapReady = false;
  bool _isDebugPanelOpen = false;
  bool _showMobileHint = false;
  
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
      } else {
        _debugService.logAction(action: 'Map: GPS location not available');
      }
    });
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

          // Map controls
          if (_isMapReady) ...[
            // Layer switching button
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              right: 16,
              child: Semantics(
                label: 'Switch map layer',
                button: true,
                child: Tooltip(
                  message: 'Switch map layer',
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

            // POI toggle button with count
            Positioned(
              top: MediaQuery.of(context).padding.top + 140,
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

            // Warning toggle button with count
            Positioned(
              top: MediaQuery.of(context).padding.top + 200,
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
              top: MediaQuery.of(context).padding.top + 260,
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
              top: MediaQuery.of(context).padding.top + 320,
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
              top: MediaQuery.of(context).padding.top + 380,
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
                      ),
                    ),
                  );
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
      child: CustomPaint(
        painter: POITeardropPinPainter(),
        child: const Center(
          child: Icon(
            Icons.place,
            color: Colors.white,
            size: 16,
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
      child: CustomPaint(
        painter: WarningTeardropPinPainter(),
        child: const Center(
          child: Icon(
            Icons.warning,
            color: Colors.white,
            size: 16,
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
      child: CustomPaint(
        painter: TeardropPinPainter(),
        child: const Center(
          child: Icon(
            Icons.directions_bike,
            color: Colors.white,
            size: 16,
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
      ..color = const Color(0xFF4A90E2) // Light blue color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.3)
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