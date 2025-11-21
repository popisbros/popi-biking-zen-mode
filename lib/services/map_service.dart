import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';

/// 2D Map layer types for cycling
enum MapLayerType {
  /// OpenStreetMap standard - Free, reliable baseline
  openStreetMap,

  /// OpenCycleMap - Cycling-specific with bike routes highlighted
  openCycleMap,

  /// Thunderforest Outdoors - Great for off-road cycling
  thunderforestOutdoors,

  /// Wike 2D - Custom Mapbox cycling style (raster tiles)
  wike2D,

  /// Satellite - Aerial imagery
  satellite,

  /// Terrain - Topographic with elevation
  terrain,
}

/// 3D Mapbox style types for cycling
enum MapboxStyleType {
  /// Mapbox Streets - Clean street map (default)
  streets,

  /// Mapbox Outdoors - Great for cycling with terrain
  outdoors,

  /// Wike Basic - Basic map style
  wikeBasic,

  /// Wike 3D - Custom cycling style
  wike3D,

  /// Wike 3D - Navigation - Optimized for turn-by-turn navigation
  wike3DNavigation,
}

/// Service for managing map tiles and styles
class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  /// Current active 2D layer
  MapLayerType _current2DLayer = MapLayerType.openCycleMap;

  /// Current active 3D style
  MapboxStyleType _current3DStyle = MapboxStyleType.wike3D;

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
        // OpenCycleMap powered by Thunderforest
        return 'https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=${ApiKeys.thunderforestApiKey}';

      case MapLayerType.thunderforestOutdoors:
        // Thunderforest Outdoors - Great for mountain biking
        return 'https://tile.thunderforest.com/outdoors/{z}/{x}/{y}.png?apikey=${ApiKeys.thunderforestApiKey}';

      case MapLayerType.wike2D:
        // Wike 2D - Custom Mapbox cycling style (raster tiles from Mapbox Static Tiles API)
        return 'https://api.mapbox.com/styles/v1/sylvainbrosset/cmh4kecsz008101s705b482zb/tiles/256/{z}/{x}/{y}?access_token=${ApiKeys.mapboxAccessToken}';

      case MapLayerType.satellite:
        // MapTiler Satellite
        return 'https://api.maptiler.com/maps/satellite/{z}/{x}/{y}.jpg?key=${ApiKeys.mapTilerApiKey}';

      case MapLayerType.terrain:
        // MapTiler Outdoor/Terrain
        return 'https://api.maptiler.com/maps/outdoor/{z}/{x}/{y}.png?key=${ApiKeys.mapTilerApiKey}';
    }
  }

  /// Get Mapbox style URI for the specified 3D style
  String getMapboxStyleUri(MapboxStyleType style) {
    switch (style) {
      case MapboxStyleType.streets:
        return 'mapbox://styles/mapbox/streets-v12';
      case MapboxStyleType.outdoors:
        return 'mapbox://styles/mapbox/outdoors-v12';
      case MapboxStyleType.wikeBasic:
        return 'mapbox://styles/sylvainbrosset/cmhypfxgw002l01r0aaqj9jxd';
      case MapboxStyleType.wike3D:
        return 'mapbox://styles/sylvainbrosset/cmgclfgn400f001pd72ofcdg9';
      case MapboxStyleType.wike3DNavigation:
        return 'mapbox://styles/sylvainbrosset/cmhd87drv004301qz6kpeh2zd';
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
      case MapLayerType.thunderforestOutdoors:
        return '© Thunderforest, © OpenStreetMap contributors';

      case MapLayerType.wike2D:
        return '© Mapbox, © OpenStreetMap contributors';

      case MapLayerType.satellite:
        return '© MapTiler, © OpenStreetMap contributors';

      case MapLayerType.terrain:
        return '© MapTiler, © OpenStreetMap contributors';
    }
  }

  /// Get attribution text for the 3D style
  String get3DAttribution(MapboxStyleType style) {
    return '© Mapbox, © OpenStreetMap contributors';
  }

  /// Get human-readable name with provider for 2D layer
  String getLayerName(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return 'Standard (OSM)';
      case MapLayerType.openCycleMap:
        return 'OpenCycleMap (Thunderforest)';
      case MapLayerType.thunderforestOutdoors:
        return 'Outdoors (Thunderforest)';
      case MapLayerType.wike2D:
        return 'Wike 2D (Mapbox)';
      case MapLayerType.satellite:
        return 'Satellite (MapTiler)';
      case MapLayerType.terrain:
        return 'Terrain (MapTiler)';
    }
  }

  /// Get human-readable name for 3D style
  String getStyleName(MapboxStyleType style) {
    switch (style) {
      case MapboxStyleType.streets:
        return 'Streets (Mapbox)';
      case MapboxStyleType.outdoors:
        return 'Outdoors (Mapbox)';
      case MapboxStyleType.wikeBasic:
        return 'Basic Map (Wike)';
      case MapboxStyleType.wike3D:
        return '3D Map (Wike)';
      case MapboxStyleType.wike3DNavigation:
        return 'Navigation Map (Wike)';
    }
  }

  /// Get default cycling center (San Francisco)
  LatLng getDefaultCenter() {
    return const LatLng(37.7749, -122.4194);
  }
}
