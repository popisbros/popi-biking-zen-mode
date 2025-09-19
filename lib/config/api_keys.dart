import 'secure_config.dart';

/// API Keys configuration for Popi Is Biking Zen Mode
/// 
/// IMPORTANT: This now uses secure configuration from environment variables
/// Get your MapTiler API key from: https://cloud.maptiler.com/
class ApiKeys {
  // MapTiler API Key for map tiles and styling
  // Now loaded securely from environment variables
  static String get mapTilerApiKey => SecureConfig.mapTilerApiKey;
  
  // Thunderforest API Key for cycling maps
  // Now loaded securely from environment variables
  static String get thunderforestApiKey => SecureConfig.thunderforestApiKey;
  
  // OpenStreetMap Nominatim API (free, no key required)
  static const String nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  
  // Overpass API for OpenStreetMap data (free, no key required)
  static const String overpassBaseUrl = 'https://overpass-api.de/api';
  
  // Example MapTiler style URLs (replace with your custom styles)
  static String get mapTilerStreetsStyle => 
      'https://api.maptiler.com/maps/streets-v2/style.json?key=$mapTilerApiKey';
  
  static String get mapTilerSatelliteStyle => 
      'https://api.maptiler.com/maps/satellite/style.json?key=$mapTilerApiKey';
  
  static String get mapTilerTerrainStyle => 
      'https://api.maptiler.com/maps/terrain-v2/style.json?key=$mapTilerApiKey';
  
  // Custom cycling-optimized style (you can create this in MapTiler)
  static String get mapTilerCyclingStyle => 
      'https://api.maptiler.com/maps/streets-v2/style.json?key=$mapTilerApiKey';
  
  // MapTiler vector tiles source
  static String get mapTilerVectorTiles => 
      'https://api.maptiler.com/tiles/v3/tiles.json?key=$mapTilerApiKey';
  
  // MapTiler terrain RGB tiles
  static String get mapTilerTerrainRgb => 
      'https://api.maptiler.com/terrain-rgb/tiles.json?key=$mapTilerApiKey';
  
  // MapTiler geocoding API
  static String get mapTilerGeocoding => 
      'https://api.maptiler.com/geocoding/';
  
  // MapTiler routing API
  static String get mapTilerRouting => 
      'https://api.maptiler.com/routing/';
}
