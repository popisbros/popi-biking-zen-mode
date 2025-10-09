import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/cycling_poi.dart';
import '../services/osm_service.dart';
import '../utils/app_logger.dart';
import 'debug_provider.dart';

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
class OSMPOIsNotifier extends Notifier<AsyncValue<List<OSMPOI>>> {
  late final OSMService _osmService;

  @override
  AsyncValue<List<OSMPOI>> build() {
    _osmService = ref.watch(osmServiceProvider);
    return const AsyncValue.data([]);
  }
  LatLng? _lastLoadedCenter;
  double _lastLoadedZoom = 0;
  
  /// Load OSM POIs for a specific location
  Future<void> loadPOIsForLocation(LatLng center, double zoom) async {
    AppLogger.api('loadPOIsForLocation called', data: {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
    });
    // Check if we need to load new data
    if (_shouldLoadNewPOIs(center, zoom)) {
      await _loadPOIs(center, zoom);
    }
  }
  
  /// Load OSM POIs using actual map bounds
  Future<void> loadPOIsWithBounds(BoundingBox bounds) async {
    AppLogger.api('loadPOIsWithBounds called', data: {
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
    });
    await _loadPOIsWithBounds(bounds);
  }

  /// Load OSM POIs in background without clearing existing data
  Future<void> loadPOIsInBackground(BoundingBox bounds) async {
    AppLogger.api('loadPOIsInBackground called', data: {
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
    });
    await _loadPOIsInBackground(bounds);
  }
  
  /// Force reload OSM POIs for the current location
  Future<void> forceReloadPOIs(LatLng center, double zoom) async {
    AppLogger.api('forceReloadPOIs called', data: {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
    });
    await _loadPOIs(center, zoom);
  }
  
  /// Force reload OSM POIs using the last known location
  Future<void> forceReload() async {
    if (_lastLoadedCenter != null) {
      AppLogger.api('forceReload called with last known location', data: {
        'location': '${_lastLoadedCenter!.latitude},${_lastLoadedCenter!.longitude}',
        'zoom': _lastLoadedZoom,
      });
      await _loadPOIs(_lastLoadedCenter!, _lastLoadedZoom);
    } else {
      AppLogger.api('forceReload called but no previous location available');
      state = const AsyncValue.data([]);
    }
  }
  
  /// Trigger background refresh of POIs when community data changes
  Future<void> triggerBackgroundRefresh() async {
    if (_lastLoadedCenter != null) {
      AppLogger.api('triggerBackgroundRefresh called - refreshing POIs in background');
      // Use the last known bounds to refresh POIs in background
      final bbox = _calculateBoundingBox(_lastLoadedCenter!, _lastLoadedZoom);
      await _loadPOIsInBackground(bbox);
    } else {
      AppLogger.api('triggerBackgroundRefresh called but no previous location available');
    }
  }
  
  /// Internal method to load POIs with actual map bounds
  Future<void> _loadPOIsWithBounds(BoundingBox bounds) async {
    AppLogger.api('Loading POIs with actual map bounds', data: {
      'south': bounds.south,
      'north': bounds.north,
      'west': bounds.west,
      'east': bounds.east,
    });
    state = const AsyncValue.loading();

    try {
      ref.read(debugProvider.notifier).addDebugMessage(
        'API: Fetching OSM POIs [${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)} to ${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}]'
      );

      final pois = await _osmService.getPOIsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      ref.read(debugProvider.notifier).addDebugMessage('API: Got ${pois.length} OSM POIs');
      AppLogger.success('Loaded ${pois.length} POIs with actual bounds');
      state = AsyncValue.data(pois);

      // Store the bounds center and calculate zoom for future reference
      final center = LatLng(
        (bounds.north + bounds.south) / 2,
        (bounds.east + bounds.west) / 2,
      );
      _lastLoadedCenter = center;
      _lastLoadedZoom = 15.0; // Default zoom for bounds-based loading
    } catch (error, stackTrace) {
      AppLogger.api('Error loading POIs with bounds', error: error);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Internal method to load POIs in background without clearing existing data
  Future<void> _loadPOIsInBackground(BoundingBox bounds) async {
    AppLogger.api('Loading POIs in background with bounds', data: {
      'south': bounds.south,
      'north': bounds.north,
      'west': bounds.west,
      'east': bounds.east,
    });
    // Don't set loading state - keep existing data visible

    try {
      final newPOIs = await _osmService.getPOIsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      AppLogger.success('Loaded ${newPOIs.length} POIs in background');

      // Filter existing POIs to keep only those within the new bounds
      final currentPOIs = state.value ?? [];
      final filteredCurrentPOIs = currentPOIs.where((poi) {
        return poi.latitude >= bounds.south &&
               poi.latitude <= bounds.north &&
               poi.longitude >= bounds.west &&
               poi.longitude <= bounds.east;
      }).toList();

      AppLogger.success('Filtered ${currentPOIs.length} existing POIs to ${filteredCurrentPOIs.length} within bounds');

      // Merge filtered existing data with new POIs to avoid duplicates
      final mergedPOIs = _mergePOIs(filteredCurrentPOIs, newPOIs);

      AppLogger.success('Merged ${filteredCurrentPOIs.length} existing + ${newPOIs.length} new = ${mergedPOIs.length} total POIs');
      state = AsyncValue.data(mergedPOIs);

      // Store the bounds center and calculate zoom for future reference
      final center = LatLng(
        (bounds.north + bounds.south) / 2,
        (bounds.east + bounds.west) / 2,
      );
      _lastLoadedCenter = center;
      _lastLoadedZoom = 15.0; // Default zoom for bounds-based loading

    } catch (e) {
      AppLogger.error('Error loading POIs in background', error: e);
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
    AppLogger.api('Loading new POIs', data: {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
    });
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

    AppLogger.api('Distance check', data: {
      'moved': '${distance.toStringAsFixed(1)}m',
      'threshold': '${distanceThreshold.toStringAsFixed(1)}m',
      'zoom': newZoom,
    });

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

    AppLogger.api('Calculated bounding box', data: {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
      'scale': scale,
      'degreesPerPixel': degreesPerPixel,
      'latSpan': finalLatSpan,
      'lonSpan': finalLonSpan,
      'south': bbox.south,
      'north': bbox.north,
      'west': bbox.west,
      'east': bbox.east,
      'latDiff': bbox.north - bbox.south,
      'lonDiff': bbox.east - bbox.west,
    });

    return bbox;
  }
}

/// Provider for OSM POIs notifier
final osmPOIsNotifierProvider = NotifierProvider<OSMPOIsNotifier, AsyncValue<List<OSMPOI>>>(OSMPOIsNotifier.new);
