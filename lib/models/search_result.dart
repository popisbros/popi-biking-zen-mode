/// Search result types
enum SearchResultType {
  address,      // Location from geocoding API
  coordinates,  // Parsed GPS coordinates
  expandSearch, // Trigger to expand search beyond viewbox
}

/// Unified search result model
class SearchResult {
  final String id;
  final String title;           // Main display text (e.g., "Eiffel Tower")
  final String? subtitle;       // Address or description
  final double latitude;
  final double longitude;
  final SearchResultType type;
  final double? distance;       // Distance from search center in km
  final dynamic metadata;       // Store original API response for debugging

  const SearchResult({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.subtitle,
    this.distance,
    this.metadata,
  });

  /// Display helper for distance text
  String get distanceText {
    if (distance == null) return '';
    if (distance! < 1) {
      return '${(distance! * 1000).toStringAsFixed(0)} m';
    }
    return '${distance!.toStringAsFixed(1)} km';
  }

  /// Factory for creating result from LocationIQ/Nominatim response
  factory SearchResult.fromGeocodingResponse(
    Map<String, dynamic> json, {
    double? distanceFromCenter,
  }) {
    return SearchResult(
      id: json['place_id']?.toString() ?? json['osm_id']?.toString() ?? '',
      title: json['display_name']?.toString().split(',').first ?? 'Unknown Location',
      subtitle: json['display_name']?.toString() ?? '',
      latitude: double.tryParse(json['lat']?.toString() ?? '0') ?? 0.0,
      longitude: double.tryParse(json['lon']?.toString() ?? '0') ?? 0.0,
      type: SearchResultType.address,
      distance: distanceFromCenter,
      metadata: json,
    );
  }

  /// Factory for creating result from parsed coordinates
  factory SearchResult.fromCoordinates(
    double lat,
    double lon, {
    String? label,
    double? distanceFromCenter,
  }) {
    return SearchResult(
      id: 'coords_${lat}_$lon',
      title: label ?? 'GPS Coordinates',
      subtitle: '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
      latitude: lat,
      longitude: lon,
      type: SearchResultType.coordinates,
      distance: distanceFromCenter,
    );
  }

  /// Factory for creating the "expand search" trigger
  factory SearchResult.expandSearchTrigger() {
    return const SearchResult(
      id: 'expand_search_trigger',
      title: 'Not finding your location? Extend the search',
      subtitle: null,
      latitude: 0.0,
      longitude: 0.0,
      type: SearchResultType.expandSearch,
      distance: null,
    );
  }

  /// Create a copy with updated fields
  SearchResult copyWith({
    String? id,
    String? title,
    String? subtitle,
    double? latitude,
    double? longitude,
    SearchResultType? type,
    double? distance,
    dynamic metadata,
  }) {
    return SearchResult(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      distance: distance ?? this.distance,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'SearchResult(title: $title, lat: $latitude, lon: $longitude, distance: $distanceText)';
  }
}
