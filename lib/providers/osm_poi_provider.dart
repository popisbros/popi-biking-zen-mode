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
  
  /// Load OSM POIs using actual map bounds
  Future<void> loadPOIsWithBounds(BoundingBox bounds) async {
    print('OSM POI Provider: loadPOIsWithBounds called with bounds=$bounds');
    await _loadPOIsWithBounds(bounds);
  }

  /// Load OSM POIs in background without clearing existing data
  Future<void> loadPOIsInBackground(BoundingBox bounds) async {
    print('OSM POI Provider: loadPOIsInBackground called with bounds=$bounds');
    await _loadPOIsInBackground(bounds);
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
  
  /// Trigger background refresh of POIs when community data changes
  Future<void> triggerBackgroundRefresh() async {
    if (_lastLoadedCenter != null) {
      print('OSM POI Provider: triggerBackgroundRefresh called - refreshing POIs in background');
      // Use the last known bounds to refresh POIs in background
      final bbox = _calculateBoundingBox(_lastLoadedCenter!, _lastLoadedZoom);
      await _loadPOIsInBackground(bbox);
    } else {
      print('OSM POI Provider: triggerBackgroundRefresh called but no previous location available');
    }
  }
  
  /// Internal method to load POIs with actual map bounds
  Future<void> _loadPOIsWithBounds(BoundingBox bounds) async {
    print('OSM POI Provider: Loading POIs with actual map bounds...');
    state = const AsyncValue.loading();
    
    try {
      print('OSM POI Provider: Using bounds - South: ${bounds.south}, North: ${bounds.north}, West: ${bounds.west}, East: ${bounds.east}');
      
      final pois = await _osmService.getPOIsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );
      
      print('OSM POI Provider: Loaded ${pois.length} POIs with actual bounds');
      state = AsyncValue.data(pois);
      
      // Store the bounds center and calculate zoom for future reference
      final center = LatLng(
        (bounds.north + bounds.south) / 2,
        (bounds.east + bounds.west) / 2,
      );
      _lastLoadedCenter = center;
      _lastLoadedZoom = 15.0; // Default zoom for bounds-based loading
    } catch (error, stackTrace) {
      print('OSM POI Provider: Error loading POIs with bounds: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Internal method to load POIs in background without clearing existing data
  Future<void> _loadPOIsInBackground(BoundingBox bounds) async {
    print('OSM POI Provider: Loading POIs in background with bounds...');
    // Don't set loading state - keep existing data visible
    
    try {
      print('OSM POI Provider: Using bounds - South: ${bounds.south}, North: ${bounds.north}, West: ${bounds.west}, East: ${bounds.east}');
      
      final newPOIs = await _osmService.getPOIsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );
      
      print('OSM POI Provider: Loaded ${newPOIs.length} POIs in background');
      
      // Merge with existing data to avoid duplicates
      final currentPOIs = state.value ?? [];
      final mergedPOIs = _mergePOIs(currentPOIs, newPOIs);
      
      print('OSM POI Provider: Merged ${currentPOIs.length} existing + ${newPOIs.length} new = ${mergedPOIs.length} total POIs');
      state = AsyncValue.data(mergedPOIs);
      
      // Store the bounds center and calculate zoom for future reference
      final center = LatLng(
        (bounds.north + bounds.south) / 2,
        (bounds.east + bounds.west) / 2,
      );
      _lastLoadedCenter = center;
      _lastLoadedZoom = 15.0; // Default zoom for bounds-based loading
      
    } catch (e) {
      print('OSM POI Provider: Error loading POIs in background: $e');
      // Don't change state on error - keep existing data
    }
  }

  /// Merge POIs to avoid duplicates
  List<OSMPOI> _mergePOIs(List<OSMPOI> existing, List<OSMPOI> newPOIs) {
    final Map<String, OSMPOI> mergedMap = {};
    
    // Add existing POIs
    for (final poi in existing) {
      final key = '${poi.osmId}_${poi.osmType}';
      mergedMap[key] = poi;
    }
    
    // Add new POIs (will overwrite duplicates)
    for (final poi in newPOIs) {
      final key = '${poi.osmId}_${poi.osmType}';
      mergedMap[key] = poi;
    }
    
    return mergedMap.values.toList();
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
    
    // Calculate variable distance threshold based on zoom level
    // At zoom 18 (max): 5m threshold
    // At zoom 0 (min): 500m threshold
    // Linear interpolation between these values
    final minZoom = 0.0;
    final maxZoom = 18.0;
    final minDistance = 5.0; // 5m at max zoom
    final maxDistance = 500.0; // 500m at min zoom
    
    // Clamp zoom to valid range
    final clampedZoom = newZoom.clamp(minZoom, maxZoom);
    
    // Calculate distance threshold using linear interpolation
    final zoomRatio = (clampedZoom - minZoom) / (maxZoom - minZoom);
    final distanceThreshold = maxDistance - (zoomRatio * (maxDistance - minDistance));
    
    final movedSignificantly = distance > distanceThreshold;
    
    print('OSM POI Provider: Distance check - moved: ${distance.toStringAsFixed(1)}m, threshold: ${distanceThreshold.toStringAsFixed(1)}m, zoom: $newZoom');
    
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
