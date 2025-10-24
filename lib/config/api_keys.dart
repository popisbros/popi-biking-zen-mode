/// API Keys Configuration
/// Keys are injected at build time via --dart-define flags
///
/// Three methods to provide API keys:
/// 1. Native iOS builds from Xcode: Keys configured in Runner.xcscheme (EnvironmentVariables section)
/// 2. GitHub Actions web builds: Keys stored as GitHub secrets and injected during build
/// 3. Local shell script builds: Keys loaded from .env file and passed via --dart-define flags
///
/// Required environment variables:
/// - THUNDERFOREST_API_KEY: https://www.thunderforest.com/
/// - MAPTILER_API_KEY: https://www.maptiler.com/
/// - MAPBOX_ACCESS_TOKEN: https://account.mapbox.com/
/// - LOCATIONIQ_API_KEY: https://locationiq.com/
/// - GRAPHHOPPER_API_KEY: https://www.graphhopper.com/
/// - OPENROUTESERVICE_API_KEY: https://openrouteservice.org/
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

  // OpenRouteService API Key (for routing - alternative to GraphHopper)
  static const String openrouteserviceApiKey = String.fromEnvironment(
    'OPENROUTESERVICE_API_KEY',
    defaultValue: '', // No default - must be provided via environment
  );
}
