import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/map_service.dart';

/// Provider for map state management
class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(MapState.initial());

  final MapService _mapService = MapService();

  /// Change the map layer
  void changeLayer(MapLayerType layer) {
    _mapService.setLayer(layer);
    state = state.copyWith(
      currentLayer: layer,
      tileUrl: _mapService.getTileUrl(layer),
      attribution: _mapService.getAttribution(layer),
    );
  }

  /// Toggle POI visibility
  void togglePOIs() {
    state = state.copyWith(showPOIs: !state.showPOIs);
  }

  /// Toggle route visibility
  void toggleRoutes() {
    state = state.copyWith(showRoutes: !state.showRoutes);
  }

  /// Toggle warning visibility
  void toggleWarnings() {
    state = state.copyWith(showWarnings: !state.showWarnings);
  }

  /// Load cycling data
  void loadCyclingData() {
    final pois = _mapService.getCyclingPOIs();
    final routes = _mapService.getCyclingRoutes();
    final warnings = _mapService.getCyclingWarnings();

    state = state.copyWith(
      pois: pois,
      routes: routes,
      warnings: warnings,
    );
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
  final MapLayerType currentLayer;
  final String tileUrl;
  final String attribution;
  final bool showPOIs;
  final bool showRoutes;
  final bool showWarnings;
  final List<Map<String, dynamic>> pois;
  final List<Map<String, dynamic>> routes;
  final List<Map<String, dynamic>> warnings;
  final LatLng center;
  final double zoom;

  const MapState({
    required this.currentLayer,
    required this.tileUrl,
    required this.attribution,
    required this.showPOIs,
    required this.showRoutes,
    required this.showWarnings,
    required this.pois,
    required this.routes,
    required this.warnings,
    required this.center,
    required this.zoom,
  });

  factory MapState.initial() {
    final mapService = MapService();
    return MapState(
      currentLayer: MapLayerType.cycling,
      tileUrl: mapService.getTileUrl(MapLayerType.cycling),
      attribution: mapService.getAttribution(MapLayerType.cycling),
      showPOIs: true,
      showRoutes: true,
      showWarnings: true,
      pois: [],
      routes: [],
      warnings: [],
      center: mapService.getCyclingCenter(),
      zoom: 15.0,
    );
  }

  MapState copyWith({
    MapLayerType? currentLayer,
    String? tileUrl,
    String? attribution,
    bool? showPOIs,
    bool? showRoutes,
    bool? showWarnings,
    List<Map<String, dynamic>>? pois,
    List<Map<String, dynamic>>? routes,
    List<Map<String, dynamic>>? warnings,
    LatLng? center,
    double? zoom,
  }) {
    return MapState(
      currentLayer: currentLayer ?? this.currentLayer,
      tileUrl: tileUrl ?? this.tileUrl,
      attribution: attribution ?? this.attribution,
      showPOIs: showPOIs ?? this.showPOIs,
      showRoutes: showRoutes ?? this.showRoutes,
      showWarnings: showWarnings ?? this.showWarnings,
      pois: pois ?? this.pois,
      routes: routes ?? this.routes,
      warnings: warnings ?? this.warnings,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
    );
  }
}

/// Provider for map state
final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier();
});
