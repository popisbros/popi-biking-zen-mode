import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../config/api_keys.dart';

/// Service for managing map configuration and styles
class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  /// Default map style for cycling navigation
  static String get _defaultStyleUrl => ApiKeys.mapTilerCyclingStyle;
  
  /// Custom cycling style (will be loaded from assets)
  String? _customCyclingStyle;

  /// Get the cycling-optimized map style
  Future<String> getCyclingStyle() async {
    if (_customCyclingStyle != null) {
      return _customCyclingStyle!;
    }

    try {
      // Try to load custom cycling style from assets
      final styleJson = await rootBundle.loadString('assets/map_styles/cycling_style.json');
      _customCyclingStyle = styleJson;
      return _customCyclingStyle!;
    } catch (e) {
      print('MapService.getCyclingStyle: Could not load custom style, using default: $e');
      return _defaultStyleUrl;
    }
  }

  /// Get default map style
  String getDefaultStyle() {
    return _defaultStyleUrl;
  }

  /// Get OpenStreetMap tile URL
  String get openStreetMapTiles => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  
  /// Get cycling-specific tile URL (requires API key)
  String get cyclingTiles => 'https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=YOUR_API_KEY';

  /// Create cycling-optimized map style configuration
  Map<String, dynamic> createCyclingStyleConfig() {
    return {
      'version': 8,
      'name': 'Cycling Style',
      'sources': {
        'openmaptiles': {
          'type': 'vector',
          'url': ApiKeys.mapTilerVectorTiles,
        },
        'terrain-rgb': {
          'type': 'raster-dem',
          'url': ApiKeys.mapTilerTerrainRgb,
          'tileSize': 256,
        },
      },
      'layers': [
        // Base layers
        {
          'id': 'background',
          'type': 'background',
          'paint': {
            'background-color': '#f8f9fa',
          },
        },
        // Terrain
        {
          'id': 'terrain',
          'type': 'hillshade',
          'source': 'terrain-rgb',
          'paint': {
            'hillshade-exaggeration': 0.5,
            'hillshade-shadow-color': '#000000',
            'hillshade-highlight-color': '#ffffff',
            'hillshade-illumination-direction': 315,
          },
        },
        // Roads
        {
          'id': 'roads',
          'type': 'line',
          'source': 'openmaptiles',
          'source-layer': 'transportation',
          'filter': ['in', 'class', 'primary', 'secondary', 'tertiary', 'trunk'],
          'paint': {
            'line-color': '#ffffff',
            'line-width': 2,
          },
        },
        // Bike lanes
        {
          'id': 'bike-lanes',
          'type': 'line',
          'source': 'openmaptiles',
          'source-layer': 'transportation',
          'filter': ['==', 'class', 'cycleway'],
          'paint': {
            'line-color': '#2196F3',
            'line-width': 3,
            'line-dasharray': [2, 1],
          },
        },
        // Protected bike paths
        {
          'id': 'protected-paths',
          'type': 'line',
          'source': 'openmaptiles',
          'source-layer': 'transportation',
          'filter': ['==', 'bicycle', 'designated'],
          'paint': {
            'line-color': '#4CAF50',
            'line-width': 4,
          },
        },
        // Buildings
        {
          'id': 'buildings',
          'type': 'fill-extrusion',
          'source': 'openmaptiles',
          'source-layer': 'building',
          'paint': {
            'fill-extrusion-color': '#e0e0e0',
            'fill-extrusion-height': [
              'interpolate',
              ['linear'],
              ['zoom'],
              15,
              0,
              15.05,
              ['get', 'render_height'],
            ],
            'fill-extrusion-base': [
              'interpolate',
              ['linear'],
              ['zoom'],
              15,
              0,
              15.05,
              ['get', 'render_min_height'],
            ],
            'fill-extrusion-opacity': 0.6,
          },
        },
      ],
    };
  }

  /// Get map camera configuration for cycling
  Map<String, dynamic> getCyclingCameraConfig() {
    return {
      'zoom': 15.0,
      'bearing': 0.0,
      'tilt': 60.0, // Tilted view for better cycling perspective
      'pitch': 60.0,
    };
  }

  /// Get map constraints for cycling navigation
  Map<String, dynamic> getMapConstraints() {
    return {
      'minZoom': 10.0,
      'maxZoom': 20.0,
      'minPitch': 0.0,
      'maxPitch': 85.0,
    };
  }

  /// Create map style with cycling layers highlighted
  Future<String> createHighlightedCyclingStyle() async {
    final baseStyle = await getCyclingStyle();
    
    // If we have a custom style, return it
    if (_customCyclingStyle != null) {
      return _customCyclingStyle!;
    }

    // Otherwise, create a cycling-optimized style
    final styleConfig = createCyclingStyleConfig();
    return jsonEncode(styleConfig);
  }

  /// Get cycling-specific map settings
  Map<String, dynamic> getCyclingMapSettings() {
    return {
      'styleString': _defaultStyleUrl,
      'cameraTarget': {'lat': 0.0, 'lng': 0.0}, // Will be set to user location
      'zoom': 15.0,
      'bearing': 0.0,
      'tilt': 60.0,
      'pitch': 60.0,
      'minZoom': 10.0,
      'maxZoom': 20.0,
      'minPitch': 0.0,
      'maxPitch': 85.0,
      'compassEnabled': true,
      'logoEnabled': false,
      'attributionEnabled': true,
      'scaleBarEnabled': true,
      'rotateGesturesEnabled': true,
      'scrollGesturesEnabled': true,
      'tiltGesturesEnabled': true,
      'zoomGesturesEnabled': true,
      'doubleClickZoomEnabled': true,
      'quickZoomEnabled': true,
    };
  }
}
