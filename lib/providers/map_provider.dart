import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/map_service.dart';

/// Provider for map state management
class MapNotifier extends Notifier<MapState> {
  @override
  MapState build() => MapState.initial();

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

  /// Set selected OSM POI types
  /// - Empty set = show none
  /// - null = show all types
  /// - Specific types = show only those types
  void setSelectedOSMPOITypes(Set<String>? types) {
    // Directly create new state to properly handle null value
    state = MapState(
      current2DLayer: state.current2DLayer,
      tileUrl: state.tileUrl,
      attribution: state.attribution,
      current3DStyle: state.current3DStyle,
      mapboxStyleUri: state.mapboxStyleUri,
      showPOIs: state.showPOIs,
      showOSMPOIs: types == null || types.isNotEmpty, // Enable if null (all) or has types
      showWarnings: state.showWarnings,
      selectedOSMPOITypes: types, // Directly set null or value
      autoZoomEnabled: state.autoZoomEnabled,
      center: state.center,
      zoom: state.zoom,
      southWest: state.southWest,
      northEast: state.northEast,
    );
  }

  /// Toggle warning visibility
  void toggleWarnings() {
    state = state.copyWith(showWarnings: !state.showWarnings);
  }

  /// Set POI visibility states
  void setPOIVisibility({bool? showOSM, bool? showCommunity, bool? showHazards}) {
    state = state.copyWith(
      showOSMPOIs: showOSM ?? state.showOSMPOIs,
      showPOIs: showCommunity ?? state.showPOIs,
      showWarnings: showHazards ?? state.showWarnings,
    );
  }

  /// Save current POI visibility states (for route selection)
  /// Note: This only saves map POI states. Favorites visibility is handled separately.
  POIVisibilityState savePOIState(bool favoritesVisible) {
    return POIVisibilityState(
      showOSMPOIs: state.showOSMPOIs,
      showPOIs: state.showPOIs,
      showWarnings: state.showWarnings,
      showFavorites: favoritesVisible,
    );
  }

  /// Restore saved POI visibility states
  void restorePOIState(POIVisibilityState savedState) {
    state = state.copyWith(
      showOSMPOIs: savedState.showOSMPOIs,
      showPOIs: savedState.showPOIs,
      showWarnings: savedState.showWarnings,
    );
    // Note: Favorites visibility is restored separately by the caller
  }

  /// Toggle auto-zoom in navigation mode
  void toggleAutoZoom() {
    state = state.copyWith(autoZoomEnabled: !state.autoZoomEnabled);
  }

  /// Update map center
  void updateCenter(LatLng center) {
    state = state.copyWith(center: center);
  }

  /// Update zoom level
  void updateZoom(double zoom) {
    state = state.copyWith(zoom: zoom);
  }

  /// Update map bounds for view synchronization
  void updateBounds(LatLng southWest, LatLng northEast) {
    state = state.copyWith(southWest: southWest, northEast: northEast);
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

  // OSM POI type filter (null = all types, empty = none, specific list = only those types)
  final Set<String>? selectedOSMPOITypes;

  // Navigation settings
  final bool autoZoomEnabled;

  // Camera settings
  final LatLng center;
  final double zoom;

  // Map bounds for view synchronization
  final LatLng? southWest;
  final LatLng? northEast;

  const MapState({
    required this.current2DLayer,
    required this.tileUrl,
    required this.attribution,
    required this.current3DStyle,
    required this.mapboxStyleUri,
    required this.showPOIs,
    required this.showOSMPOIs,
    required this.showWarnings,
    this.selectedOSMPOITypes,
    required this.autoZoomEnabled,
    required this.center,
    required this.zoom,
    this.southWest,
    this.northEast,
  });

  factory MapState.initial() {
    final mapService = MapService();
    final defaultLayer = mapService.current2DLayer;
    final defaultStyle = mapService.current3DStyle;

    // Desktop web browser: zoom 15, Mobile/Native: zoom 16
    final defaultZoom = kIsWeb ? 16.0 : 17.0; // 2D will subtract 1, giving 15 or 16

    return MapState(
      current2DLayer: defaultLayer,
      tileUrl: mapService.getTileUrl(defaultLayer),
      attribution: mapService.getAttribution(defaultLayer),
      current3DStyle: defaultStyle,
      mapboxStyleUri: mapService.getMapboxStyleUri(defaultStyle),
      showPOIs: false,
      showOSMPOIs: false,
      showWarnings: true,
      selectedOSMPOITypes: {}, // Empty = none selected by default
      autoZoomEnabled: true, // Auto-zoom enabled by default
      center: mapService.getDefaultCenter(),
      zoom: defaultZoom,
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
    Set<String>? selectedOSMPOITypes,
    bool? autoZoomEnabled,
    LatLng? center,
    double? zoom,
    LatLng? southWest,
    LatLng? northEast,
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
      selectedOSMPOITypes: selectedOSMPOITypes ?? this.selectedOSMPOITypes,
      autoZoomEnabled: autoZoomEnabled ?? this.autoZoomEnabled,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      southWest: southWest ?? this.southWest,
      northEast: northEast ?? this.northEast,
    );
  }
}

/// Provider for map service
final mapServiceProvider = Provider<MapService>((ref) {
  return MapService();
});

/// Provider for map state
final mapProvider = NotifierProvider<MapNotifier, MapState>(MapNotifier.new);

/// POI visibility state for saving/restoring during route selection
class POIVisibilityState {
  final bool showOSMPOIs;
  final bool showPOIs;
  final bool showWarnings;
  final bool showFavorites;

  const POIVisibilityState({
    required this.showOSMPOIs,
    required this.showPOIs,
    required this.showWarnings,
    required this.showFavorites,
  });
}
