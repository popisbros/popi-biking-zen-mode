import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/cycling_poi.dart';
import '../services/osm_service.dart';

/// Provider for OSM service
final osmServiceProvider = Provider<OSMService>((ref) {
  return OSMService();
});

/// Bounding box class for OSM queries
class BoundingBox {
  final double south, west, north, east;
  const BoundingBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}

/// Notifier for OSM POIs with location-based loading
class OSMPOIsNotifier extends StateNotifier<AsyncValue<List<OSMPOI>>> {
  OSMPOIsNotifier(this._osmService) : super(const AsyncValue.data([]));
  
  final OSMService _osmService;
  LatLng? _lastLoadedCenter;
  double _lastLoadedZoom = 0;
  
  /// Load OSM POIs for a specific location
  Future<void> loadPOIsForLocation(LatLng center, double zoom) async {
    // Check if we need to load new data
    if (_shouldLoadNewPOIs(center, zoom)) {
      state = const AsyncValue.loading();
      
      try {
        // Calculate bounding box based on zoom level
        final bbox = _calculateBoundingBox(center, zoom);
        
        final pois = await _osmService.getPOIsInBounds(
          south: bbox.south,
          west: bbox.west,
          north: bbox.north,
          east: bbox.east,
        );
        
        state = AsyncValue.data(pois);
        _lastLoadedCenter = center;
        _lastLoadedZoom = zoom;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
      }
    }
  }
  
  bool _shouldLoadNewPOIs(LatLng newCenter, double newZoom) {
    if (_lastLoadedCenter == null) return true;
    
    final distance = Distance().as(
      LengthUnit.Meter,
      _lastLoadedCenter!,
      newCenter,
    );
    
    final zoomChanged = (newZoom - _lastLoadedZoom).abs() > 1;
    final movedSignificantly = distance > 500; // 500m threshold
    
    return zoomChanged || movedSignificantly;
  }
  
  BoundingBox _calculateBoundingBox(LatLng center, double zoom) {
    // Calculate radius based on zoom level
    final zoomFactor = pow(2, 20 - zoom).toDouble();
    final radius = (1000 / zoomFactor).clamp(200.0, 2000.0);
    
    final distance = Distance();
    return BoundingBox(
      south: distance.offset(center, -radius, 180).latitude,
      north: distance.offset(center, radius, 0).latitude,
      west: distance.offset(center, -radius, 270).longitude,
      east: distance.offset(center, radius, 90).longitude,
    );
  }
}

/// Provider for OSM POIs notifier
final osmPOIsNotifierProvider = StateNotifierProvider<OSMPOIsNotifier, AsyncValue<List<OSMPOI>>>((ref) {
  final osmService = ref.watch(osmServiceProvider);
  return OSMPOIsNotifier(osmService);
});
