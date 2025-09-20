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
    print('OSM POI Provider: loadPOIsForLocation called with center=$center, zoom=$zoom');
    // Check if we need to load new data
    if (_shouldLoadNewPOIs(center, zoom)) {
      await _loadPOIs(center, zoom);
    }
  }
  
  /// Force reload OSM POIs for the current location
  Future<void> forceReloadPOIs(LatLng center, double zoom) async {
    print('OSM POI Provider: forceReloadPOIs called with center=$center, zoom=$zoom');
    await _loadPOIs(center, zoom);
  }
  
  /// Force reload OSM POIs using the last known location
  Future<void> forceReload() async {
    if (_lastLoadedCenter != null) {
      print('OSM POI Provider: forceReload called with last known location=$_lastLoadedCenter, zoom=$_lastLoadedZoom');
      await _loadPOIs(_lastLoadedCenter!, _lastLoadedZoom);
    } else {
      print('OSM POI Provider: forceReload called but no previous location available');
      state = const AsyncValue.data([]);
    }
  }
  
  /// Internal method to load POIs
  Future<void> _loadPOIs(LatLng center, double zoom) async {
    print('OSM POI Provider: Loading new POIs...');
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
    // Calculate the visible map area based on zoom level
    // Each zoom level doubles the resolution, so we need to account for this
    // At zoom 0: entire world is visible
    // At zoom 18: very detailed view
    
    // Calculate the approximate size of the visible area in degrees
    // This is based on the standard web mercator projection
    final worldSize = 256.0; // Standard tile size
    final scale = pow(2, zoom).toDouble();
    final pixelSize = worldSize * scale;
    
    // Approximate degrees per pixel at the equator
    final degreesPerPixel = 360.0 / pixelSize;
    
    // Assume a typical screen size of 800x600 pixels for the map view
    // This gives us a reasonable buffer around the visible area
    final mapWidthPixels = 800.0;
    final mapHeightPixels = 600.0;
    
    // Calculate the bounding box size in degrees
    final latSpan = (mapHeightPixels * degreesPerPixel) / 2.0;
    final lonSpan = (mapWidthPixels * degreesPerPixel) / 2.0;
    
    // Adjust longitude span for the current latitude (mercator projection)
    final adjustedLonSpan = lonSpan / cos(center.latitude * pi / 180.0);
    
    // Ensure minimum size for very high zoom levels
    final minSpan = 0.001; // ~100m at equator
    final finalLatSpan = latSpan.clamp(minSpan, 1.0);
    final finalLonSpan = adjustedLonSpan.clamp(minSpan, 1.0);
    
    final bbox = BoundingBox(
      south: center.latitude - finalLatSpan,
      north: center.latitude + finalLatSpan,
      west: center.longitude - finalLonSpan,
      east: center.longitude + finalLonSpan,
    );
    
    print('OSM POI Provider: Calculated bounding box:');
    print('  Center: ${center.latitude}, ${center.longitude}');
    print('  Zoom: $zoom, Scale: $scale');
    print('  Degrees per pixel: $degreesPerPixel');
    print('  Lat span: $finalLatSpan, Lon span: $finalLonSpan');
    print('  South: ${bbox.south}, North: ${bbox.north}');
    print('  West: ${bbox.west}, East: ${bbox.east}');
    print('  Lat diff: ${bbox.north - bbox.south}, Lon diff: ${bbox.east - bbox.west}');
    
    return bbox;
  }
}

/// Provider for OSM POIs notifier
final osmPOIsNotifierProvider = StateNotifierProvider<OSMPOIsNotifier, AsyncValue<List<OSMPOI>>>((ref) {
  final osmService = ref.watch(osmServiceProvider);
  return OSMPOIsNotifier(osmService);
});
