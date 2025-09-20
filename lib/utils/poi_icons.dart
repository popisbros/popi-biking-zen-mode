import 'package:flutter/material.dart';

/// Helper class for POI and Hazard type icons
class POIIcons {
  /// Get the appropriate icon for a POI type
  static String getPOIIcon(String type) {
    switch (type.toLowerCase()) {
      // Bike-related POIs
      case 'bike_shop':
      case 'bike_shop':
        return '🏪';
      case 'bike_repair':
      case 'repair_station':
        return '🔧';
      case 'bike_charging':
      case 'charging_station':
        return '⚡️';
      case 'bike_parking':
      case 'bicycle_parking':
        return '🚲';
      
      // Water-related POIs
      case 'drinking_water':
      case 'water_tap':
        return '⛲️';
      case 'fountain':
        return '⛲️';
      
      // Facilities
      case 'toilets':
      case 'toilet':
        return '🚻';
      case 'shelter':
        return '🏠';
      case 'rest_area':
        return '🛋️';
      
      // Food & Drink
      case 'restaurant':
      case 'cafe':
        return '☕️';
      case 'food':
        return '🍽️';
      
      // Services
      case 'hospital':
      case 'medical':
        return '🏥';
      case 'police':
        return '👮';
      case 'gas_station':
        return '⛽';
      
      // Default
      default:
        return '📍';
    }
  }
  
  /// Get the appropriate icon for a Hazard type
  static String getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pothole':
        return '🕳️';
      case 'construction':
        return '🚧';
      case 'accident':
        return '⚠️';
      case 'road_closed':
        return '🚫';
      case 'traffic_jam':
        return '🚗';
      case 'ice':
        return '🧊';
      case 'flooding':
        return '🌊';
      case 'debris':
        return '🗑️';
      case 'narrow_road':
        return '↔️';
      case 'steep_hill':
        return '⛰️';
      case 'dangerous_intersection':
        return '⚠️';
      case 'poor_lighting':
        return '🌙';
      case 'wildlife':
        return '🦌';
      case 'maintenance':
        return '🔧';
      default:
        return '⚠️';
    }
  }
  
  /// Get the appropriate Material icon for a POI type (fallback)
  static IconData getPOIMaterialIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bike_shop':
        return Icons.store;
      case 'bike_repair':
        return Icons.build;
      case 'bike_charging':
        return Icons.electric_bolt;
      case 'bike_parking':
        return Icons.local_parking;
      case 'drinking_water':
      case 'water_tap':
        return Icons.water_drop;
      case 'toilets':
        return Icons.wc;
      case 'shelter':
        return Icons.home;
      case 'restaurant':
      case 'cafe':
        return Icons.restaurant;
      case 'hospital':
        return Icons.local_hospital;
      case 'police':
        return Icons.local_police;
      default:
        return Icons.place;
    }
  }
  
  /// Get the appropriate Material icon for a Hazard type (fallback)
  static IconData getHazardMaterialIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pothole':
        return Icons.warning;
      case 'construction':
        return Icons.construction;
      case 'accident':
        return Icons.error;
      case 'road_closed':
        return Icons.block;
      case 'traffic_jam':
        return Icons.traffic;
      case 'ice':
        return Icons.ac_unit;
      case 'flooding':
        return Icons.water;
      case 'debris':
        return Icons.delete;
      case 'narrow_road':
        return Icons.straighten;
      case 'steep_hill':
        return Icons.terrain;
      case 'dangerous_intersection':
        return Icons.warning;
      case 'poor_lighting':
        return Icons.nightlight_round;
      case 'wildlife':
        return Icons.pets;
      case 'maintenance':
        return Icons.build;
      default:
        return Icons.warning;
    }
  }
}
