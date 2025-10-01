import 'package:latlong2/latlong.dart';

/// 2D Map layer types for cycling
enum MapLayerType {
  /// OpenStreetMap standard - Free, reliable baseline
  openStreetMap,

  /// OpenCycleMap - Cycling-specific with bike routes highlighted
  openCycleMap,

  /// Thunderforest Cycle - Premium cycling map with elevation
  thunderforestCycle,

  /// Thunderforest Outdoors - Great for off-road cycling
  thunderforestOutdoors,

  /// CyclOSM - Community cycling map focused on bike infrastructure
  cyclOSM,

  /// Satellite - Aerial imagery
  satellite,

  /// Terrain - Topographic with elevation
  terrain,
}

/// 3D Mapbox style types for cycling
enum MapboxStyleType {
  /// Mapbox Outdoors - Great for cycling with terrain (default)
  outdoors,

  /// Mapbox Streets - Clean street map
  streets,

  /// Mapbox Satellite - Aerial imagery
  satellite,

  /// Mapbox Satellite Streets - Hybrid satellite + streets
  satelliteStreets,

  /// Mapbox Light - Minimal, clean design
  light,

  /// Mapbox Dark - Dark theme
  dark,
}

/// Service for managing map tiles and styles
class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  /// Current active 2D layer
  MapLayerType _current2DLayer = MapLayerType.openCycleMap;

  /// Current active 3D style
  MapboxStyleType _current3DStyle = MapboxStyleType.outdoors;

  /// Get current 2D layer type
  MapLayerType get current2DLayer => _current2DLayer;

  /// Get current 3D style type
  MapboxStyleType get current3DStyle => _current3DStyle;

  /// Set current 2D layer type
  void set2DLayer(MapLayerType layer) {
    _current2DLayer = layer;
  }

  /// Set current 3D style type
  void set3DStyle(MapboxStyleType style) {
    _current3DStyle = style;
  }

  /// Get tile URL for the specified 2D layer
  String getTileUrl(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

      case MapLayerType.openCycleMap:
        // OpenCycleMap powered by Thunderforest (requires API key for production)
        // For now using without key (limited to development)
        return 'https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png';

      case MapLayerType.thunderforestCycle:
        // Thunderforest Cycle layer - Premium cycling map
        return 'https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png';

      case MapLayerType.thunderforestOutdoors:
        // Thunderforest Outdoors - Great for mountain biking
        return 'https://tile.thunderforest.com/outdoors/{z}/{x}/{y}.png';

      case MapLayerType.cyclOSM:
        // CyclOSM - Community-driven cycling map
        return 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png';

      case MapLayerType.satellite:
        // OpenStreetMap satellite (via ArcGIS)
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

      case MapLayerType.terrain:
        // OpenTopoMap - Topographic map with elevation
        return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    }
  }

  /// Get Mapbox style URI for the specified 3D style
  String getMapboxStyleUri(MapboxStyleType style) {
    switch (style) {
      case MapboxStyleType.outdoors:
        return 'mapbox://styles/mapbox/outdoors-v12';
      case MapboxStyleType.streets:
        return 'mapbox://styles/mapbox/streets-v12';
      case MapboxStyleType.satellite:
        return 'mapbox://styles/mapbox/satellite-v9';
      case MapboxStyleType.satelliteStreets:
        return 'mapbox://styles/mapbox/satellite-streets-v12';
      case MapboxStyleType.light:
        return 'mapbox://styles/mapbox/light-v11';
      case MapboxStyleType.dark:
        return 'mapbox://styles/mapbox/dark-v11';
    }
  }

  /// Get user agent for tile requests
  String get userAgent => 'com.popibiking.fresh';

  /// Get attribution text for the 2D layer
  String getAttribution(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return '© OpenStreetMap contributors';

      case MapLayerType.openCycleMap:
      case MapLayerType.thunderforestCycle:
      case MapLayerType.thunderforestOutdoors:
        return '© Thunderforest, © OpenStreetMap contributors';

      case MapLayerType.cyclOSM:
        return '© CyclOSM, © OpenStreetMap contributors';

      case MapLayerType.satellite:
        return '© Esri, © OpenStreetMap contributors';

      case MapLayerType.terrain:
        return '© OpenTopoMap, © OpenStreetMap contributors';
    }
  }

  /// Get attribution text for the 3D style
  String get3DAttribution(MapboxStyleType style) {
    return '© Mapbox, © OpenStreetMap contributors';
  }

  /// Get human-readable name for 2D layer
  String getLayerName(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return 'OpenStreetMap';
      case MapLayerType.openCycleMap:
        return 'OpenCycleMap';
      case MapLayerType.thunderforestCycle:
        return 'Cycle Map';
      case MapLayerType.thunderforestOutdoors:
        return 'Outdoors';
      case MapLayerType.cyclOSM:
        return 'CyclOSM';
      case MapLayerType.satellite:
        return 'Satellite';
      case MapLayerType.terrain:
        return 'Terrain';
    }
  }

  /// Get human-readable name for 3D style
  String getStyleName(MapboxStyleType style) {
    switch (style) {
      case MapboxStyleType.outdoors:
        return 'Outdoors 3D';
      case MapboxStyleType.streets:
        return 'Streets 3D';
      case MapboxStyleType.satellite:
        return 'Satellite 3D';
      case MapboxStyleType.satelliteStreets:
        return 'Hybrid 3D';
      case MapboxStyleType.light:
        return 'Light 3D';
      case MapboxStyleType.dark:
        return 'Dark 3D';
    }
  }

  /// Get default cycling center (San Francisco)
  LatLng getDefaultCenter() {
    return const LatLng(37.7749, -122.4194);
  }
}
