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

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final MapService _mapService = MapService();
  final DebugService _debugService = DebugService();
  bool _isMapReady = false;
  bool _isDebugPanelOpen = false;
  bool _showMobileHint = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _initializeMap();
    _debugService.logAction(action: 'Map Screen: Initialized');
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
      _showMobileHint = true;
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

  void _onReportWarning() {
    _debugService.logButtonClick('Report Warning', screen: 'MapScreen');
    _debugService.logNavigation('MapScreen', 'HazardReportScreen');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const HazardReportScreen(),
      ),
    );
  }

  void _showDebugPanel() {
    setState(() {
      _isDebugPanelOpen = true;
    });
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => const DebugPanel(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
    ).then((_) {
      setState(() {
        _isDebugPanelOpen = false;
      });
    });
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
          Container(
            height: _isDebugPanelOpen 
                ? MediaQuery.of(context).size.height * 0.7 
                : MediaQuery.of(context).size.height,
            child: GestureDetector(
              onLongPressStart: (details) => _onMapLongPress(details.globalPosition),
              child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapState.center,
                initialZoom: mapState.zoom,
                minZoom: 10.0,
                maxZoom: 20.0,
                onMapReady: () => _onMapReady(),
                onTap: (tapPosition, point) => _onMapTap(point),
                onSecondaryTap: (tapPosition, point) => _onMapRightClick(tapPosition, point),
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
                          data: (pois) {
                            print('🗺️ POI Layer: showPOIs=${mapState.showPOIs}, pois.length=${pois.length}');
                            final markers = _buildPOIMarkersFromFirestore(pois);
                            print('🗺️ POI Layer: Built ${markers.length} markers');
                            return MarkerLayer(markers: markers);
                          },
                          loading: () {
                            print('🗺️ POI Layer: Loading...');
                            return const MarkerLayer(markers: []);
                          },
                          error: (error, stack) {
                            print('🗺️ POI Layer: Error - $error');
                            return const MarkerLayer(markers: []);
                          },
                        ),
                      
                      // Warning markers (from Firestore)
                      if (mapState.showWarnings)
                        warningsAsync.when(
                          data: (warnings) {
                            print('⚠️ Warning Layer: showWarnings=${mapState.showWarnings}, warnings.length=${warnings.length}');
                            final markers = _buildWarningMarkersFromFirestore(warnings);
                            print('⚠️ Warning Layer: Built ${markers.length} markers');
                            return MarkerLayer(markers: markers);
                          },
                          loading: () {
                            print('⚠️ Warning Layer: Loading...');
                            return const MarkerLayer(markers: []);
                          },
                          error: (error, stack) {
                            print('⚠️ Warning Layer: Error - $error');
                            return const MarkerLayer(markers: []);
                          },
                        ),
                      
                      // GPS Location marker
                      locationAsync.when(
                        data: (location) => location != null 
                            ? MarkerLayer(
                                markers: [_buildGPSLocationMarker(location)],
                              )
                            : const MarkerLayer(markers: []),
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
            ),
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

                  // Debug button (bottom left)
                  Positioned(
                    bottom: 120, // Above the floating action buttons
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


          // Mobile hint for long press
          if (_showMobileHint)
            Positioned(
              bottom: 200, // Above the floating action buttons
              left: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: _showMobileHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.urbanBlue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
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
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showMobileHint = false;
                          });
                        },
                        child: const Icon(
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
                        child: Tooltip(
                          message: 'Switch map layer',
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.urbanBlue,
                            onPressed: _showLayerSelector,
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
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: mapState.showPOIs ? AppColors.mossGreen : AppColors.surface,
                          foregroundColor: mapState.showPOIs ? AppColors.surface : AppColors.urbanBlue,
                          onPressed: () {
                            _debugService.logButtonClick('Toggle POIs', screen: 'MapScreen', parameters: {'currentState': mapState.showPOIs});
                            ref.read(mapProvider.notifier).togglePOIs();
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.place, size: 16),
                              const SizedBox(height: 2),
                              poisAsync.when(
                                data: (pois) => Text(
                                  '${pois.length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: mapState.showPOIs ? AppColors.surface : AppColors.urbanBlue,
                                  ),
                                ),
                                loading: () => Text(
                                  '...',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: mapState.showPOIs ? AppColors.surface : AppColors.urbanBlue,
                                  ),
                                ),
                                error: (error, stack) => Text(
                                  '!',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.dangerRed,
                                  ),
                                ),
                              ),
                            ],
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
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: mapState.showWarnings ? AppColors.dangerRed : AppColors.surface,
                          foregroundColor: mapState.showWarnings ? AppColors.surface : AppColors.urbanBlue,
                          onPressed: () {
                            _debugService.logButtonClick('Toggle Warnings', screen: 'MapScreen', parameters: {'currentState': mapState.showWarnings});
                            ref.read(mapProvider.notifier).toggleWarnings();
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning, size: 16),
                              const SizedBox(height: 2),
                              warningsAsync.when(
                                data: (warnings) => Text(
                                  '${warnings.length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: mapState.showWarnings ? AppColors.surface : AppColors.urbanBlue,
                                  ),
                                ),
                                loading: () => Text(
                                  '...',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: mapState.showWarnings ? AppColors.surface : AppColors.urbanBlue,
                                  ),
                                ),
                                error: (error, stack) => Text(
                                  '!',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.dangerRed,
                                  ),
                                ),
                              ),
                            ],
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // POI Creation Button
          Semantics(
            label: 'Add new point of interest',
            button: true,
            child: Tooltip(
              message: 'Add new point of interest',
              child: FloatingActionButton(
                mini: true,
                        onPressed: () {
                          _debugService.logButtonClick('Add POI', screen: 'MapScreen');
                          _debugService.logNavigation('MapScreen', 'POIManagementScreen');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const POIManagementScreen(),
                            ),
                          );
                        },
                backgroundColor: AppColors.mossGreen,
                foregroundColor: AppColors.surface,
                child: const Icon(Icons.add_location),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Warning Report Button
          Semantics(
            label: 'Report a community warning',
            button: true,
            child: Tooltip(
              message: 'Report a community warning',
              child: FloatingActionButton(
                mini: true,
                onPressed: _onReportWarning,
                backgroundColor: AppColors.signalYellow,
                foregroundColor: AppColors.urbanBlue,
                child: const Icon(Icons.warning),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onMapTap(LatLng point) {
    // Handle map tap events
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

  void _onMapRightClick(TapPosition tapPosition, LatLng point) {
    // Handle right-click events - show context menu
    _debugService.logAction(
      action: 'Map Right Click',
      screen: 'MapScreen',
      parameters: {
        'latitude': point.latitude,
        'longitude': point.longitude,
      },
    );
    print('Map right-clicked at: ${point.latitude}, ${point.longitude}');
    
    _showContextMenu(tapPosition, point);
  }

  void _onMapLongPress(Offset globalPosition) {
    // Handle long press events on mobile/touchscreen - show context menu
    if (!_isMapReady) return;
    
    // Provide haptic feedback for mobile users
    HapticFeedback.mediumImpact();
    
    // Convert global position to map coordinates
    final point = _mapController.camera.pointToLatLng(
      _mapController.camera.globalToLocal(globalPosition),
    );
    
    _debugService.logAction(
      action: 'Map Long Press',
      screen: 'MapScreen',
      parameters: {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'platform': 'mobile',
      },
    );
    print('Map long-pressed at: ${point.latitude}, ${point.longitude}');
    
    // Create a TapPosition from the global position
    final tapPosition = TapPosition(
      globalPosition: globalPosition,
      localPosition: _mapController.camera.globalToLocal(globalPosition),
    );
    
    _showContextMenu(tapPosition, point);
  }

  void _showContextMenu(TapPosition tapPosition, LatLng point) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    // Detect platform for different menu styling
    final isMobile = Theme.of(context).platform == TargetPlatform.iOS || 
                     Theme.of(context).platform == TargetPlatform.android;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          tapPosition.global,
          tapPosition.global,
        ),
        Offset.zero & overlay.size,
      ),
      elevation: isMobile ? 8 : 4, // Higher elevation on mobile for better visibility
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'add_poi',
          child: Row(
            children: [
              const Icon(Icons.add_location, color: AppColors.mossGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Add New POI',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (isMobile)
                      const Text(
                        'Add a point of interest',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'report_hazard',
          child: Row(
            children: [
              const Icon(Icons.warning, color: AppColors.dangerRed),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Report Hazard',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (isMobile)
                      const Text(
                        'Report a safety issue',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((String? selectedValue) {
      if (selectedValue != null) {
        // Provide haptic feedback when selecting an option on mobile
        if (isMobile) {
          HapticFeedback.lightImpact();
        }
        _handleContextMenuSelection(selectedValue, point);
      }
    });
  }

  void _handleContextMenuSelection(String action, LatLng point) {
    _debugService.logAction(
      action: 'Context Menu: $action',
      screen: 'MapScreen',
      parameters: {
        'latitude': point.latitude,
        'longitude': point.longitude,
      },
    );

    switch (action) {
      case 'add_poi':
        _openPOIManagementWithLocation(point);
        break;
      case 'report_hazard':
        _openHazardReportWithLocation(point);
        break;
    }
  }

  void _openPOIManagementWithLocation(LatLng point) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => POIManagementScreenWithLocation(
          initialLatitude: point.latitude,
          initialLongitude: point.longitude,
        ),
      ),
    );
  }

  void _openHazardReportWithLocation(LatLng point) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HazardReportScreenWithLocation(
          initialLatitude: point.latitude,
          initialLongitude: point.longitude,
        ),
      ),
    );
  }

  void _showLayerSelector() {
    _debugService.logButtonClick('Layer Selector', screen: 'MapScreen');
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
                        _debugService.logButtonClick('Select Layer: ${_getLayerName(layer)}', screen: 'MapScreen');
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
              case MapLayerType.cycling:
                return Icons.directions_bike;
              case MapLayerType.openStreetMap:
                return Icons.map;
              case MapLayerType.satellite:
                return Icons.satellite;
            }
          }

          String _getLayerName(MapLayerType layer) {
            switch (layer) {
              case MapLayerType.cycling:
                return 'Cycling';
              case MapLayerType.openStreetMap:
                return 'OpenStreetMap';
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
    print('🗺️ _buildPOIMarkersFromFirestore: Building ${pois.length} POI markers');
    
    return pois.map((poi) {
      try {
        final position = LatLng(poi.latitude, poi.longitude);
        print('📍 POI Marker: ${poi.name} at ${poi.latitude}, ${poi.longitude}');
        
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
      } catch (e) {
        print('❌ Error building POI marker for ${poi.name}: $e');
        return null;
      }
    }).where((marker) => marker != null).cast<Marker>().toList();
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
    print('⚠️ _buildWarningMarkersFromFirestore: Building ${warnings.length} warning markers');
    
    return warnings.map((warning) {
      try {
        final position = LatLng(warning.latitude, warning.longitude);
        final severity = warning.severity as String;
        Color color = AppColors.dangerRed;
        if (severity == 'medium') color = AppColors.signalYellow;
        if (severity == 'low') color = AppColors.mossGreen;

        print('⚠️ Warning Marker: ${warning.title} at ${warning.latitude}, ${warning.longitude} (${severity})');

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
      } catch (e) {
        print('❌ Error building warning marker for ${warning.title}: $e');
        return null;
      }
    }).where((marker) => marker != null).cast<Marker>().toList();
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

  Marker _buildGPSLocationMarker(LocationData location) {
    return Marker(
      point: LatLng(location.latitude, location.longitude),
      width: 50,
      height: 50,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.urbanBlue,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppColors.urbanBlue.withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.directions_bike,
            color: AppColors.surface,
            size: 24,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // flutter_map MapController doesn't need explicit disposal
    super.dispose();
  }
}
