/// Community warning/hazard model
class CommunityWarning {
  final String id;
  final String type; // hazard, alert, construction, etc.
  final String severity; // low, medium, high, critical
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final String? reportedBy;
  final DateTime reportedAt;
  final DateTime? expiresAt;
  final bool isActive;
  final List<String>? tags;
  final Map<String, dynamic>? metadata;

  const CommunityWarning({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.reportedBy,
    required this.reportedAt,
    this.expiresAt,
    this.isActive = true,
    this.tags,
    this.metadata,
  });

  factory CommunityWarning.fromMap(Map<String, dynamic> map) {
    return CommunityWarning(
      id: map['id'] ?? '',
      type: map['type'] ?? '',
      severity: map['severity'] ?? 'medium',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      reportedBy: map['reportedBy'],
      reportedAt: DateTime.fromMillisecondsSinceEpoch(map['reportedAt'] ?? 0),
      expiresAt: map['expiresAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['expiresAt'])
          : null,
      isActive: map['isActive'] ?? true,
      tags: map['tags']?.cast<String>(),
      metadata: map['metadata'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'severity': severity,
      'title': title,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'reportedBy': reportedBy,
      'reportedAt': reportedAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt?.millisecondsSinceEpoch,
      'isActive': isActive,
      'tags': tags,
      'metadata': metadata,
    };
  }

  CommunityWarning copyWith({
    String? id,
    String? type,
    String? severity,
    String? title,
    String? description,
    double? latitude,
    double? longitude,
    String? reportedBy,
    DateTime? reportedAt,
    DateTime? expiresAt,
    bool? isActive,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return CommunityWarning(
      id: id ?? this.id,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      title: title ?? this.title,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      reportedBy: reportedBy ?? this.reportedBy,
      reportedAt: reportedAt ?? this.reportedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isActive: isActive ?? this.isActive,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'CommunityWarning(id: $id, type: $type, severity: $severity, title: $title)';
  }
}

