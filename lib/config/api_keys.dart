/// API Keys Configuration
/// Keys are injected at build time using --dart-define flags
/// Fallback values from .env file for development
class ApiKeys {
  // Thunderforest API Key (for OpenCycleMap, Cycle, Outdoors layers)
  // Get at: https://www.thunderforest.com/
  static const String thunderforestApiKey = String.fromEnvironment(
    'THUNDERFOREST_API_KEY',
    defaultValue: '121a02b0d4754f5ca3d296c2cf0d97bb', // From .env
  );

  // MapTiler API Key (for Satellite, Terrain layers)
  // Get at: https://www.maptiler.com/
  static const String mapTilerApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
    defaultValue: '4W92qzk4nYyvr3kSNaNH', // From .env
  );

  // Mapbox Access Token (for 3D maps)
  // Get at: https://account.mapbox.com/
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'pk.eyJ1IjoicG9waWJyb3MiLCJhIjoiY20yOXFlYW8wMDB2MDJycTE1dnQxY2h4aCJ9.1t7c0qmz1ZrcPhXY5f4XBA', // From .env
  );

  // LocationIQ API Key (for geocoding - optional)
  // Get at: https://locationiq.com/
  static const String locationiqApiKey = String.fromEnvironment(
    'LOCATIONIQ_API_KEY',
    defaultValue: 'pk.1ffa72ff2e8c83a89e9da6a2c7e0e3e9', // From .env
  );
}
