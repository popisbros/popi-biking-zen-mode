/// API Keys Configuration
/// Keys MUST be injected at build time using --dart-define flags or environment variables
/// NO default values are provided for security reasons
///
/// For local development, create a .env file with your keys (see .env.example)
/// For GitHub Actions, configure secrets in repository settings
///
/// Required environment variables:
/// - THUNDERFOREST_API_KEY: https://www.thunderforest.com/
/// - MAPTILER_API_KEY: https://www.maptiler.com/
/// - MAPBOX_ACCESS_TOKEN: https://account.mapbox.com/
/// - LOCATIONIQ_API_KEY: https://locationiq.com/
/// - GRAPHHOPPER_API_KEY: https://www.graphhopper.com/
class ApiKeys {
  // Thunderforest API Key (for OpenCycleMap, Cycle, Outdoors layers)
  static const String thunderforestApiKey = String.fromEnvironment(
    'THUNDERFOREST_API_KEY',
    defaultValue: '', // No default - must be provided via environment
  );

  // MapTiler API Key (for Satellite, Terrain layers)
  static const String mapTilerApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
    defaultValue: '', // No default - must be provided via environment
  );

  // Mapbox Access Token (for 3D maps)
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '', // No default - must be provided via environment
  );

  // LocationIQ API Key (for geocoding - optional)
  static const String locationiqApiKey = String.fromEnvironment(
    'LOCATIONIQ_API_KEY',
    defaultValue: '', // No default - must be provided via environment
  );

  // Graphhopper API Key (for routing)
  static const String graphhopperApiKey = String.fromEnvironment(
    'GRAPHHOPPER_API_KEY',
    defaultValue: '', // No default - must be provided via environment
  );
}
