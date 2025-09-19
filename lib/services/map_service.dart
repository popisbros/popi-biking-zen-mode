// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';

/// Map layer types
enum MapLayerType {
  cycling,
  openStreetMap,
  satellite,
}

/// Service for managing map configuration and styles for flutter_map
class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  /// Current active layer
  MapLayerType _currentLayer = MapLayerType.cycling;

  /// Get current layer type
  MapLayerType get currentLayer => _currentLayer;

  /// Set current layer type
  void setLayer(MapLayerType layer) {
    _currentLayer = layer;
  }

  /// Get tile URL for the specified layer
  String getTileUrl(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapLayerType.cycling:
        // Use Thunderforest cycling layer with API key
        return 'https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=${ApiKeys.thunderforestApiKey}';
      case MapLayerType.satellite:
        // Use MapTiler satellite with proper API key
        return 'https://api.maptiler.com/maps/satellite/{z}/{x}/{y}.jpg?key=${ApiKeys.mapTilerApiKey}';
    }
  }

  /// Get user agent for tile requests
  String get userAgent => 'com.popibiking.zenmode';

  /// Get attribution text for the current layer
  String getAttribution(MapLayerType layer) {
    switch (layer) {
      case MapLayerType.openStreetMap:
        return '© OpenStreetMap contributors';
      case MapLayerType.cycling:
        return '© Thunderforest, © OpenStreetMap contributors';
      case MapLayerType.satellite:
        return '© MapTiler, © OpenStreetMap contributors';
    }
  }

  /// Get cycling-specific POI locations (mock data for now)
  List<Map<String, dynamic>> getCyclingPOIs() {
    return [
      {
        'id': '1',
        'name': 'Bike Repair Station',
        'type': 'repair',
        'position': LatLng(37.7749, -122.4194),
        'description': 'Free bike repair station with tools',
        'icon': '🔧',
      },
      {
        'id': '2',
        'name': 'Bike Parking',
        'type': 'parking',
        'position': LatLng(37.7849, -122.4094),
        'description': 'Secure bike parking area',
        'icon': '🚲',
      },
      {
        'id': '3',
        'name': 'Water Fountain',
        'type': 'water',
        'position': LatLng(37.7649, -122.4294),
        'description': 'Public water fountain',
        'icon': '💧',
      },
      {
        'id': '4',
        'name': 'Bike Shop',
        'type': 'shop',
        'position': LatLng(37.7549, -122.4394),
        'description': 'Local bike shop and rentals',
        'icon': '🏪',
      },
    ];
  }

  /// Get cycling routes (mock data for now)
  List<Map<String, dynamic>> getCyclingRoutes() {
    return [
      {
        'id': '1',
        'name': 'Golden Gate Park Loop',
        'type': 'recreational',
        'difficulty': 'easy',
        'distance': 5.2,
        'elevation': 120,
        'waypoints': [
          LatLng(37.7694, -122.4862),
          LatLng(37.7694, -122.4762),
          LatLng(37.7594, -122.4762),
          LatLng(37.7594, -122.4862),
          LatLng(37.7694, -122.4862),
        ],
        'color': 0xFF4CAF50, // Green
      },
      {
        'id': '2',
        'name': 'Embarcadero Waterfront',
        'type': 'commute',
        'difficulty': 'easy',
        'distance': 3.8,
        'elevation': 45,
        'waypoints': [
          LatLng(37.7849, -122.4094),
          LatLng(37.7849, -122.3994),
          LatLng(37.7749, -122.3994),
          LatLng(37.7749, -122.4094),
        ],
        'color': 0xFF2196F3, // Blue
      },
    ];
  }

  /// Get cycling warnings (mock data for now)
  List<Map<String, dynamic>> getCyclingWarnings() {
    return [
      {
        'id': '1',
        'type': 'hazard',
        'severity': 'high',
        'position': LatLng(37.7749, -122.4194),
        'description': 'Pothole on bike lane',
        'reportedBy': 'user123',
        'reportedAt': DateTime.now().subtract(const Duration(hours: 2)),
        'icon': '⚠️',
      },
      {
        'id': '2',
        'type': 'construction',
        'severity': 'medium',
        'position': LatLng(37.7849, -122.4094),
        'description': 'Road construction ahead',
        'reportedBy': 'user456',
        'reportedAt': DateTime.now().subtract(const Duration(hours: 5)),
        'icon': '🚧',
      },
    ];
  }

  /// Get cycling-optimized map settings for flutter_map
  Map<String, dynamic> getCyclingMapSettings() {
    return {
      'initialZoom': 15.0,
      'minZoom': 10.0,
      'maxZoom': 20.0,
      'interactionOptions': {
        'enableMultiFingerGestureRace': true,
        'enableScrollWheelZoom': true,
        'enableScrollWheelZoomOnFling': true,
        'enableScrollWheelZoomOnFlingVelocity': 0.1,
        'enableScrollWheelZoomOnFlingVelocityThreshold': 0.1,
        'enableScrollWheelZoomOnFlingVelocityThreshold': 0.1,
      },
    };
  }

  /// Get cycling-specific map bounds (San Francisco area)
  // Note: LatLngBounds removed for now - can be added back when needed

  /// Get cycling-specific initial center
  LatLng getCyclingCenter() {
    return const LatLng(37.7749, -122.4194); // San Francisco
  }
}
