import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/map_service.dart';

/// Provider for map state management
class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(MapState.initial());

  final MapService _mapService = MapService();

  /// Change the 2D map layer
  void change2DLayer(MapLayerType layer) {
    _mapService.set2DLayer(layer);
    state = state.copyWith(
      current2DLayer: layer,
      tileUrl: _mapService.getTileUrl(layer),
      attribution: _mapService.getAttribution(layer),
    );
  }

  /// Change the 3D map style
  void change3DStyle(MapboxStyleType style) {
    _mapService.set3DStyle(style);
    state = state.copyWith(
      current3DStyle: style,
      mapboxStyleUri: _mapService.getMapboxStyleUri(style),
    );
  }

  /// Toggle POI visibility
  void togglePOIs() {
    state = state.copyWith(showPOIs: !state.showPOIs);
  }

  /// Toggle OSM POI visibility
  void toggleOSMPOIs() {
    state = state.copyWith(showOSMPOIs: !state.showOSMPOIs);
  }

  /// Toggle warning visibility
  void toggleWarnings() {
    state = state.copyWith(showWarnings: !state.showWarnings);
  }

  /// Update map center
  void updateCenter(LatLng center) {
    state = state.copyWith(center: center);
  }

  /// Update zoom level
  void updateZoom(double zoom) {
    state = state.copyWith(zoom: zoom);
  }
}

/// Map state class
class MapState {
  // 2D Map settings
  final MapLayerType current2DLayer;
  final String tileUrl;
  final String attribution;

  // 3D Map settings
  final MapboxStyleType current3DStyle;
  final String mapboxStyleUri;

  // Display toggles
  final bool showPOIs;
  final bool showOSMPOIs;
  final bool showWarnings;

  // Camera settings
  final LatLng center;
  final double zoom;

  const MapState({
    required this.current2DLayer,
    required this.tileUrl,
    required this.attribution,
    required this.current3DStyle,
    required this.mapboxStyleUri,
    required this.showPOIs,
    required this.showOSMPOIs,
    required this.showWarnings,
    required this.center,
    required this.zoom,
  });

  factory MapState.initial() {
    final mapService = MapService();
    final defaultLayer = MapLayerType.openCycleMap;
    final defaultStyle = MapboxStyleType.streets; // Default to Streets 3D

    return MapState(
      current2DLayer: defaultLayer,
      tileUrl: mapService.getTileUrl(defaultLayer),
      attribution: mapService.getAttribution(defaultLayer),
      current3DStyle: defaultStyle,
      mapboxStyleUri: mapService.getMapboxStyleUri(defaultStyle),
      showPOIs: true,
      showOSMPOIs: true,
      showWarnings: true,
      center: mapService.getDefaultCenter(),
      zoom: 16.0, // Mapbox zoom scale (2D map will use 15.0 by subtracting 1)
    );
  }

  MapState copyWith({
    MapLayerType? current2DLayer,
    String? tileUrl,
    String? attribution,
    MapboxStyleType? current3DStyle,
    String? mapboxStyleUri,
    bool? showPOIs,
    bool? showOSMPOIs,
    bool? showWarnings,
    LatLng? center,
    double? zoom,
  }) {
    return MapState(
      current2DLayer: current2DLayer ?? this.current2DLayer,
      tileUrl: tileUrl ?? this.tileUrl,
      attribution: attribution ?? this.attribution,
      current3DStyle: current3DStyle ?? this.current3DStyle,
      mapboxStyleUri: mapboxStyleUri ?? this.mapboxStyleUri,
      showPOIs: showPOIs ?? this.showPOIs,
      showOSMPOIs: showOSMPOIs ?? this.showOSMPOIs,
      showWarnings: showWarnings ?? this.showWarnings,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
    );
  }
}

/// Provider for map service
final mapServiceProvider = Provider<MapService>((ref) {
  return MapService();
});

/// Provider for map state
final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier();
});
