import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_gl/mapbox_gl.dart';
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
import '../widgets/locationiq_debug_window.dart';
import '../services/debug_service.dart';
import '../services/osm_debug_service.dart';
import '../services/locationiq_service.dart';
import '../providers/locationiq_debug_provider.dart';
import '../config/api_keys.dart';

class Mapbox3DScreen extends ConsumerStatefulWidget {
  const Mapbox3DScreen({super.key});

  @override
  ConsumerState<Mapbox3DScreen> createState() => _Mapbox3DScreenState();
}

class _Mapbox3DScreenState extends ConsumerState<Mapbox3DScreen> with TickerProviderStateMixin {
  MapboxMapController? _mapController;
  final MapService _mapService = MapService();
  final DebugService _debugService = DebugService();
  final OSMDebugService _osmDebugService = OSMDebugService();
  
  bool _isMapReady = false;
  bool _isDebugPanelOpen = false;
  bool _showMobileHint = false;
  bool _showOSMDebugWindow = false;
  bool _showLocationIQDebugWindow = false;
  Timer? _debounceTimer;
  bool _isUserMoving = false;
  LatLng? _lastGPSPosition;
  LatLng? _originalGPSReference;
  
  // Share dialog state
  bool _isShareDialogVisible = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  List<LocationIQResult> _searchResults = [];
  bool _isSearching = false;
  late final LocationIQService _locationIQService;
  
  // 3D Perspective state
  bool _is3DEnabled = true; // Default to 3D for Mapbox
  double _tiltAngle = 30.0; // Default tilt for 3D effect
  double _bearingAngle = 0.0;
  String _currentMapStyle = MapboxStyles.MAPBOX_STREETS;
  
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
    _debugService.logAction(action: 'Mapbox 3D Screen: Initialized');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final debugNotifier = ref.read(locationIQDebugProvider.notifier);
    _locationIQService = LocationIQService(debugNotifier: debugNotifier);
  }

  @override
  void dispose() {
    _debugPanelAnimationController.dispose();
    _debounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    final locationNotifier = ref.read(locationNotifierProvider.notifier);
    await locationNotifier.requestPermission();
    await locationNotifier.startTracking();
    
    _debugService.logAction(action: 'GPS: Forcing current position');
    await _centerOnUserLocation();
  }

  void _initializeMap() {
    final mapNotifier = ref.read(mapProvider.notifier);
    mapNotifier.loadCyclingData();
  }

  void _onMapCreated(MapboxMapController controller) {
    _mapController = controller;
    setState(() {
      _isMapReady = true;
    });
    
    _centerOnUserLocation();
    
    // Show mobile hint for touchscreen users
    final isMobile = Theme.of(context).platform == TargetPlatform.iOS || 
                     Theme.of(context).platform == TargetPlatform.android;
    if (isMobile) {
      setState(() {
        _showMobileHint = true;
      });
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
      if (location != null && _mapController != null) {
        _debugService.logAction(
          action: 'Map: Centering on GPS location',
          parameters: {
            'latitude': location.latitude,
            'longitude': location.longitude,
          },
        );
        
        final newPosition = LatLng(location.latitude, location.longitude);
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newPosition,
              zoom: 15.0,
              tilt: _tiltAngle,
              bearing: _bearingAngle,
            ),
          ),
        );
        
        _lastGPSPosition = newPosition;
        _originalGPSReference = newPosition;
      }
    });
  }

  /// Toggle 3D perspective on/off
  void _toggle3DPerspective() {
    setState(() {
      _is3DEnabled = !_is3DEnabled;
      if (_is3DEnabled) {
        _tiltAngle = 30.0;
        _bearingAngle = 0.0;
      } else {
        _tiltAngle = 0.0;
        _bearingAngle = 0.0;
      }
    });
    
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _mapController!.cameraPosition!.target,
            zoom: _mapController!.cameraPosition!.zoom,
            tilt: _tiltAngle,
            bearing: _bearingAngle,
          ),
        ),
      );
    }
    
    _debugService.logAction(
      action: '3D Perspective Toggle',
      screen: 'Mapbox3DScreen',
      parameters: {
        'enabled': _is3DEnabled,
        'tilt': _tiltAngle,
        'bearing': _bearingAngle,
      },
    );
  }

  /// Adjust 3D tilt angle
  void _adjustTilt(double tilt) {
    setState(() {
      _tiltAngle = tilt.clamp(0.0, 60.0);
    });
    
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _mapController!.cameraPosition!.target,
            zoom: _mapController!.cameraPosition!.zoom,
            tilt: _tiltAngle,
            bearing: _bearingAngle,
          ),
        ),
      );
    }
  }

  /// Adjust 3D bearing angle
  void _adjustBearing(double bearing) {
    setState(() {
      _bearingAngle = bearing % 360.0;
    });
    
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _mapController!.cameraPosition!.target,
            zoom: _mapController!.cameraPosition!.zoom,
            tilt: _tiltAngle,
            bearing: _bearingAngle,
          ),
        ),
      );
    }
  }

  /// Change map style
  void _changeMapStyle(String style) {
    setState(() {
      _currentMapStyle = style;
    });
    
    if (_mapController != null) {
      _mapController!.setStyle(style);
    }
    
    _debugService.logAction(
      action: 'Map Style Changed',
      screen: 'Mapbox3DScreen',
      parameters: {'style': style},
    );
  }

  /// Show map style selector
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
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.urbanBlue,
              ),
            ),
            const SizedBox(height: 20),
            _buildMapStyleOption('Streets', MapboxStyles.MAPBOX_STREETS, Icons.map),
            _buildMapStyleOption('Satellite', MapboxStyles.SATELLITE, Icons.satellite),
            _buildMapStyleOption('Outdoors', MapboxStyles.OUTDOORS, Icons.terrain),
            _buildMapStyleOption('Light', MapboxStyles.LIGHT, Icons.light_mode),
            _buildMapStyleOption('Dark', MapboxStyles.DARK, Icons.dark_mode),
          ],
        ),
      ),
    );
  }

  Widget _buildMapStyleOption(String title, String style, IconData icon) {
    final isSelected = _currentMapStyle == style;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.mossGreen : AppColors.urbanBlue,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? AppColors.mossGreen : AppColors.urbanBlue,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check, color: AppColors.mossGreen) : null,
      onTap: () {
        _changeMapStyle(style);
        Navigator.pop(context);
      },
    );
  }

  /// Build 3D preset button
  Widget _build3DPresetButton(String label, double tilt, double bearing) {
    return TextButton(
      onPressed: () {
        _adjustTilt(tilt);
        _adjustBearing(bearing);
      },
      style: TextButton.styleFrom(
        backgroundColor: AppColors.azureBlue.withValues(alpha: 0.1),
        foregroundColor: AppColors.azureBlue,
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }

  void _showDebugPanel() {
    setState(() {
      _isDebugPanelOpen = true;
    });
    
    _debugPanelAnimationController.forward();
  }

  void _hideDebugPanel() {
    _debugPanelAnimationController.reverse().then((_) {
      setState(() {
        _isDebugPanelOpen = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationNotifierProvider);
    final mapState = ref.watch(mapProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Mapbox GL Map with 3D capabilities
          SizedBox(
            width: double.infinity,
            height: _isDebugPanelOpen 
                ? MediaQuery.of(context).size.height * 0.7 
                : MediaQuery.of(context).size.height,
            child: MapboxMap(
              accessToken: ApiKeys.mapboxApiKey,
              initialCameraPosition: CameraPosition(
                target: LatLng(mapState.center.latitude, mapState.center.longitude),
                zoom: mapState.zoom,
                tilt: _tiltAngle,
                bearing: _bearingAngle,
              ),
              styleString: _currentMapStyle,
              onMapCreated: _onMapCreated,
              onMapClick: (point, coordinates) {
                _debugService.logAction(
                  action: 'Map Tap',
                  screen: 'Mapbox3DScreen',
                  parameters: {
                    'latitude': coordinates.latitude,
                    'longitude': coordinates.longitude,
                  },
                );
              },
              onMapLongClick: (point, coordinates) {
                _debugService.logAction(
                  action: 'Map Long Press',
                  screen: 'Mapbox3DScreen',
                  parameters: {
                    'latitude': coordinates.latitude,
                    'longitude': coordinates.longitude,
                  },
                );
              },
              onCameraMove: (cameraPosition) {
                // Update our state with current camera position
                setState(() {
                  _tiltAngle = cameraPosition.tilt;
                  _bearingAngle = cameraPosition.bearing;
                });
              },
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
                    _debugService.logButtonClick('Profile', screen: 'Mapbox3DScreen');
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
                      _debugService.logButtonClick('Map Style Switch', screen: 'Mapbox3DScreen');
                      _showMapStyleSelector();
                    },
                    child: const Icon(Icons.layers),
                  ),
                ),
              ),
            ),

          // 3D Toggle button
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 116,
              right: 16,
              child: Semantics(
                label: _is3DEnabled ? 'Disable 3D perspective' : 'Enable 3D perspective',
                button: true,
                child: Tooltip(
                  message: 'Toggle 3D perspective',
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: _is3DEnabled ? AppColors.azureBlue : AppColors.lightGrey,
                    foregroundColor: AppColors.surface,
                    onPressed: () {
                      _debugService.logButtonClick('3D Toggle', screen: 'Mapbox3DScreen');
                      _toggle3DPerspective();
                    },
                    child: Icon(_is3DEnabled ? Icons.view_in_ar : Icons.view_in_ar_outlined),
                  ),
                ),
              ),
            ),

          // GPS current location button
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 166,
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
                      _debugService.logButtonClick('GPS Center', screen: 'Mapbox3DScreen');
                      _centerOnUserLocation();
                    },
                    child: const Icon(Icons.my_location),
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
                  _debugService.logButtonClick('Debug Panel', screen: 'Mapbox3DScreen');
                  _showDebugPanel();
                },
                child: const Icon(Icons.bug_report),
              ),
            ),
          ),

          // 3D Control Panel
          if (_is3DEnabled && _isMapReady)
            Positioned(
              bottom: 200,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '3D Perspective Controls',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Tilt Control
                    Row(
                      children: [
                        Icon(Icons.swap_vert, color: AppColors.azureBlue, size: 16),
                        const SizedBox(width: 8),
                        Text('Tilt: ${_tiltAngle.toStringAsFixed(0)}°', 
                             style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: _tiltAngle,
                            min: 0.0,
                            max: 60.0,
                            divisions: 12,
                            activeColor: AppColors.azureBlue,
                            onChanged: _adjustTilt,
                          ),
                        ),
                      ],
                    ),
                    
                    // Bearing Control
                    Row(
                      children: [
                        Icon(Icons.rotate_right, color: AppColors.azureBlue, size: 16),
                        const SizedBox(width: 8),
                        Text('Bearing: ${_bearingAngle.toStringAsFixed(0)}°', 
                             style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: _bearingAngle,
                            min: 0.0,
                            max: 360.0,
                            divisions: 36,
                            activeColor: AppColors.azureBlue,
                            onChanged: _adjustBearing,
                          ),
                        ),
                      ],
                    ),
                    
                    // Quick Presets
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _build3DPresetButton('Street View', 45.0, 0.0),
                        _build3DPresetButton('Bird\'s Eye', 15.0, 0.0),
                        _build3DPresetButton('Isometric', 30.0, 45.0),
                      ],
                    ),
                  ],
                ),
              ),
            ),

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

          // Debug panel
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
                        onReloadOSMPOIs: () {
                          // TODO: Implement POI reloading for Mapbox
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
