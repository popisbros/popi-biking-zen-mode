/// OSM Point of Interest model
class OSMPOI {
  final String? id; // Optional - for future Firestore integration
  final String osmId;
  final String osmType; // node, way, relation
  final Map<String, dynamic> osmTags;
  final bool isFromOSM;
  final String name;
  final String type; // bike_shop, parking, repair_station, etc.
  final double latitude;
  final double longitude;
  final String? description;
  final String? address;
  final String? phone;
  final String? website;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OSMPOI({
    this.id,
    required this.osmId,
    required this.osmType,
    required this.osmTags,
    this.isFromOSM = true,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description,
    this.address,
    this.phone,
    this.website,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OSMPOI.fromOSMData(Map<String, dynamic> osmData) {
    final tags = osmData['tags'] as Map<String, dynamic>? ?? {};
    final lat = osmData['lat']?.toDouble() ?? 0.0;
    final lon = osmData['lon']?.toDouble() ?? 0.0;

    // Determine POI type from OSM tags
    final poiType = _determinePOIType(tags);
    final name = _extractName(tags);

    return OSMPOI(
      osmId: osmData['id']?.toString() ?? '',
      osmType: osmData['type'] ?? 'node',
      osmTags: tags,
      name: name,
      type: poiType,
      latitude: lat,
      longitude: lon,
      description: tags['description'] ?? tags['note'],
      address: _extractAddress(tags),
      phone: tags['phone'],
      website: tags['website'],
      metadata: tags,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static String _determinePOIType(Map<String, dynamic> tags) {
    // Map OSM tags to our internal POI types
    if (tags['amenity'] == 'bicycle_parking') return 'bike_parking';
    if (tags['amenity'] == 'repair_station') return 'bike_repair';
    if (tags['amenity'] == 'charging_station' && tags['bicycle'] == 'yes') return 'bike_charging';
    if (tags['shop'] == 'bicycle') return 'bike_shop';
    if (tags['amenity'] == 'drinking_water') return 'drinking_water';
    if (tags['man_made'] == 'water_tap') return 'water_tap';
    if (tags['amenity'] == 'toilets') return 'toilets';
    if (tags['amenity'] == 'shelter') return 'shelter';
    return 'unknown';
  }

  static String _extractName(Map<String, dynamic> tags) {
    return tags['name'] ??
           tags['brand'] ??
           tags['operator'] ??
           'Unnamed POI';
  }

  static String? _extractAddress(Map<String, dynamic> tags) {
    final parts = <String>[];
    if (tags['addr:housenumber'] != null) parts.add(tags['addr:housenumber']);
    if (tags['addr:street'] != null) parts.add(tags['addr:street']);
    if (tags['addr:city'] != null) parts.add(tags['addr:city']);
    return parts.isNotEmpty ? parts.join(' ') : null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'osmId': osmId,
      'osmType': osmType,
      'osmTags': osmTags,
      'isFromOSM': isFromOSM,
      'name': name,
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'address': address,
      'phone': phone,
      'website': website,
      'metadata': metadata,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'OSMPOI(osmId: $osmId, name: $name, type: $type, lat: $latitude, lng: $longitude)';
  }
}
