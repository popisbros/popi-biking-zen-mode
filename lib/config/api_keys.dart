/// API Keys Configuration
/// Keys are injected at build time using --dart-define flags
/// This file can be committed to Git as it contains no secrets
class ApiKeys {
  // Thunderforest API Key (for OpenCycleMap, Cycle, Outdoors layers)
  static const String thunderforestApiKey = String.fromEnvironment(
    'THUNDERFOREST_API_KEY',
    defaultValue: '',
  );

  // MapTiler API Key (for Satellite, Terrain layers)
  static const String mapTilerApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
    defaultValue: '',
  );

  // Mapbox Access Token (for 3D maps)
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  // LocationIQ API Key (for geocoding - optional)
  static const String locationiqApiKey = String.fromEnvironment(
    'LOCATIONIQ_API_KEY',
    defaultValue: '',
  );
}
