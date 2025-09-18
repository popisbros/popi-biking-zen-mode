import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../services/map_service.dart';
import '../widgets/warning_report_modal.dart';

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
  }

  Future<void> _initializeLocation() async {
    // Request location permission and start tracking
    final locationNotifier = ref.read(locationNotifierProvider.notifier);
    await locationNotifier.requestPermission();
    await locationNotifier.startTracking();
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

    return Scaffold(
      body: Stack(
        children: [
          // Flutter Map (works on web and mobile)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(37.7749, -122.4194), // San Francisco default
              initialZoom: 15.0,
              onMapReady: () => _onMapReady(),
            ),
            children: [
              // OpenStreetMap tiles
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.popibiking.zenmode',
              ),
              // Cycling-specific overlay (you can add custom tiles here)
              // Note: Thunderforest requires API key, using OpenStreetMap for now
              // TileLayer(
              //   urlTemplate: 'https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=YOUR_API_KEY',
              //   userAgentPackageName: 'com.popibiking.zenmode',
              // ),
            ],
          ),

          // Profile button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
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
            // POI List button
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              right: 16,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.urbanBlue,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('POI list feature coming soon'),
                    ),
                  );
                },
                child: const Icon(Icons.place),
              ),
            ),

            // Center on location button
            Positioned(
              top: MediaQuery.of(context).padding.top + 140,
              right: 16,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.urbanBlue,
                onPressed: _centerOnUserLocation,
                child: const Icon(Icons.my_location),
              ),
            ),

            // Zoom controls
            Positioned(
              top: MediaQuery.of(context).padding.top + 200,
              right: 16,
              child: Column(
                children: [
                  FloatingActionButton(
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
                  const SizedBox(height: 8),
                  FloatingActionButton(
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
                ],
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onReportWarning,
        backgroundColor: AppColors.signalYellow,
        foregroundColor: AppColors.urbanBlue,
        child: const Icon(Icons.warning),
      ),
    );
  }

  void _addCyclingLayers() {
    // Add cycling-specific layers using flutter_map
    // This can be enhanced with custom markers, polylines, etc.
    print('Adding cycling layers...');
  }

  @override
  void dispose() {
    // flutter_map MapController doesn't need explicit disposal
    super.dispose();
  }
}
