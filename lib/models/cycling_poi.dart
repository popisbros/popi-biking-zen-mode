/// Cycling Point of Interest model
class CyclingPOI {
  final String? id; // Optional - will be set by Firestore when created
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

  const CyclingPOI({
    this.id,
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

  factory CyclingPOI.fromMap(Map<String, dynamic> map) {
    return CyclingPOI(
      id: map['id']?.toString().isNotEmpty == true ? map['id'] : null,
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      description: map['description'],
      address: map['address'],
      phone: map['phone'],
      website: map['website'],
      metadata: map['metadata'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] ?? 0),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
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
    
    // Only include ID if it's not null (for existing POIs)
    if (id != null && id!.isNotEmpty) {
      map['id'] = id;
    }
    
    return map;
  }

  CyclingPOI copyWith({
    String? id,
    String? name,
    String? type,
    double? latitude,
    double? longitude,
    String? description,
    String? address,
    String? phone,
    String? website,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CyclingPOI(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'CyclingPOI(id: ${id ?? 'new'}, name: $name, type: $type, lat: $latitude, lng: $longitude)';
  }
}

/// OSM Point of Interest model (extends CyclingPOI)
class OSMPOI extends CyclingPOI {
  final String osmId;
  final String osmType; // node, way, relation
  final Map<String, dynamic> osmTags;
  final bool isFromOSM;

  const OSMPOI({
    required this.osmId,
    required this.osmType,
    required this.osmTags,
    this.isFromOSM = true,
    String? id,
    required String name,
    required String type,
    required double latitude,
    required double longitude,
    String? description,
    String? address,
    String? phone,
    String? website,
    Map<String, dynamic>? metadata,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super(
          id: id,
          name: name,
          type: type,
          latitude: latitude,
          longitude: longitude,
          description: description,
          address: address,
          phone: phone,
          website: website,
          metadata: metadata,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

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

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map['osmId'] = osmId;
    map['osmType'] = osmType;
    map['osmTags'] = osmTags;
    map['isFromOSM'] = isFromOSM;
    return map;
  }
}

