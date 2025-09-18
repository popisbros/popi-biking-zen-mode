/// Cycling Point of Interest model
class CyclingPOI {
  final String id;
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
    required this.id,
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
      id: map['id'] ?? '',
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
    return {
      'id': id,
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
    return 'CyclingPOI(id: $id, name: $name, type: $type, lat: $latitude, lng: $longitude)';
  }
}

