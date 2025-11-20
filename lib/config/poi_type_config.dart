
/// POI Type Configuration with Emojis and Labels
///
/// This class provides a centralized place to define POI types with their
/// associated emojis and display labels for both Community POIs and OSM POIs.
class POITypeConfig {
  // ============================================================================
  // COMMUNITY POI TYPES
  // ============================================================================

  static const List<Map<String, String>> communityPOITypes = [
    {'value': 'bike_shop', 'label': 'Bike Shop', 'emoji': '🚲'},
    {'value': 'parking', 'label': 'Bike Parking', 'emoji': '🅿️'},
    {'value': 'repair_station', 'label': 'Repair Station', 'emoji': '🔧'},
    {'value': 'water_fountain', 'label': 'Water Fountain', 'emoji': '💧'},
    {'value': 'rest_area', 'label': 'Rest Area', 'emoji': '🪑'},
  ];

  // ============================================================================
  // OSM POI TYPES
  // ============================================================================

  static const Map<String, Map<String, String>> osmPOITypes = {
    'bike_parking': {'label': 'Bike Parking', 'emoji': '🅿️'},
    'bike_repair': {'label': 'Bike Repair', 'emoji': '🔧'},
    'bike_charging': {'label': 'Bike Charging', 'emoji': '🔌'},
    'bike_shop': {'label': 'Bike Shop', 'emoji': '🚲'},
    'drinking_water': {'label': 'Drinking Water', 'emoji': '💧'},
    'water_tap': {'label': 'Water Tap', 'emoji': '🚰'},
    'toilets': {'label': 'Toilets', 'emoji': '🚻'},
    'shelter': {'label': 'Shelter', 'emoji': '🏠'},
    'unknown': {'label': 'Unknown', 'emoji': '❓'},
  };

  // ============================================================================
  // WARNING TYPES (for completeness)
  // ============================================================================

  static const List<Map<String, String>> warningTypes = [
    {'value': 'pothole', 'label': 'Pothole', 'emoji': '🕳️'},
    {'value': 'construction', 'label': 'Construction', 'emoji': '🚧'},
    {'value': 'dangerous_intersection', 'label': 'Dangerous Intersection', 'emoji': '⚠️'},
    {'value': 'poor_surface', 'label': 'Poor Surface', 'emoji': '🛤️'},
    {'value': 'debris', 'label': 'Debris', 'emoji': '🪨'},
    {'value': 'traffic_hazard', 'label': 'Traffic Hazard', 'emoji': '🚗'},
    {'value': 'steep', 'label': 'Steep Section', 'emoji': '⛰️'},
    {'value': 'flooding', 'label': 'Flooding', 'emoji': '💧'},
    {'value': 'other', 'label': 'Other', 'emoji': '❓'},
  ];

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Get emoji for Community POI type
  static String getCommunityPOIEmoji(String type) {
    final poiType = communityPOITypes.firstWhere(
      (t) => t['value'] == type,
      orElse: () => {'emoji': '📍'},
    );
    return poiType['emoji'] ?? '📍';
  }

  /// Get label for Community POI type
  static String getCommunityPOILabel(String type) {
    final poiType = communityPOITypes.firstWhere(
      (t) => t['value'] == type,
      orElse: () => {'label': type},
    );
    return poiType['label'] ?? type;
  }

  /// Get emoji for OSM POI type
  static String getOSMPOIEmoji(String type) {
    return osmPOITypes[type]?['emoji'] ?? '📍';
  }

  /// Get label for OSM POI type
  static String getOSMPOILabel(String type) {
    return osmPOITypes[type]?['label'] ?? type;
  }

  /// Get emoji for Warning type
  static String getWarningEmoji(String type) {
    final warningType = warningTypes.firstWhere(
      (t) => t['value'] == type,
      orElse: () => {'emoji': '⚠️'},
    );
    return warningType['emoji'] ?? '⚠️';
  }

  /// Get label for Warning type
  static String getWarningLabel(String type) {
    final warningType = warningTypes.firstWhere(
      (t) => t['value'] == type,
      orElse: () => {'label': type},
    );
    return warningType['label'] ?? type;
  }
}
