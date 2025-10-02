/// API Keys Configuration
/// Keys are injected at build time using --dart-define flags
/// Fallback values from .env file for development
class ApiKeys {
  // Thunderforest API Key (for OpenCycleMap, Cycle, Outdoors layers)
  // Get at: https://www.thunderforest.com/
  static const String thunderforestApiKey = String.fromEnvironment(
    'THUNDERFOREST_API_KEY',
    defaultValue: 'REMOVED_FROM_HISTORY', // From .env
  );

  // MapTiler API Key (for Satellite, Terrain layers)
  // Get at: https://www.maptiler.com/
  static const String mapTilerApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
    defaultValue: 'REMOVED_FROM_HISTORY', // From .env
  );

  // Mapbox Access Token (for 3D maps)
  // Get at: https://account.mapbox.com/
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'REMOVED_FROM_HISTORY', // From .env
  );

  // LocationIQ API Key (for geocoding - optional)
  // Get at: https://locationiq.com/
  static const String locationiqApiKey = String.fromEnvironment(
    'LOCATIONIQ_API_KEY',
    defaultValue: 'REMOVED_FROM_HISTORY', // From .env
  );
}
