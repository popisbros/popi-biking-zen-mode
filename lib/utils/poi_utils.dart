import '../models/osm_poi.dart';

/// Utility functions for POI filtering and management
class POIUtils {
  /// Filter OSM POIs based on selected types
  ///
  /// - If selectedTypes is null: show all POIs (backward compatibility)
  /// - If selectedTypes is empty: show none
  /// - If selectedTypes has values: show only those types
  static List<OSMPOI> filterPOIsByType(
    List<OSMPOI> pois,
    Set<String>? selectedTypes,
  ) {
    return pois.where((poi) {
      // If no types selected (empty set), show none
      if (selectedTypes != null && selectedTypes.isEmpty) return false;

      // If specific types selected, only show those
      if (selectedTypes != null && !selectedTypes.contains(poi.type)) return false;

      // If selectedTypes is null, show all (backward compatibility)
      return true;
    }).toList();
  }
}
