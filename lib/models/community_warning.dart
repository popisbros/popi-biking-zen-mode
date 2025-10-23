/// User interaction record for audit trail (imported from cycling_poi.dart)
class UserInteraction {
  final String userId;
  final String userEmail;
  final String action; // 'created', 'updated', 'deleted'
  final DateTime timestamp;

  const UserInteraction({
    required this.userId,
    required this.userEmail,
    required this.action,
    required this.timestamp,
  });

  factory UserInteraction.fromMap(Map<String, dynamic> map) {
    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value.runtimeType.toString() == 'Timestamp') {
        return (value as dynamic).toDate();
      }
      return DateTime.now();
    }

    return UserInteraction(
      userId: map['userId'] ?? '',
      userEmail: map['userEmail'] ?? '',
      action: map['action'] ?? '',
      timestamp: parseTimestamp(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userEmail': userEmail,
      'action': action,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

/// Community warning/hazard model
class CommunityWarning {
  final String? id; // Optional - will be set by Firestore when created
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
  final List<UserInteraction> userInteractions; // Last 5 interactions
  final bool isDeleted; // Soft deletion flag
  final DateTime? deletedAt;

  const CommunityWarning({
    this.id,
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
    this.userInteractions = const [],
    this.isDeleted = false,
    this.deletedAt,
  });

  factory CommunityWarning.fromMap(Map<String, dynamic> map) {
    // Helper function to convert Firestore Timestamp or int to DateTime
    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      // Handle Firestore Timestamp object
      if (value.runtimeType.toString() == 'Timestamp') {
        return (value as dynamic).toDate();
      }
      return DateTime.now();
    }

    // Parse user interactions list
    final interactionsList = (map['userInteractions'] as List?)
        ?.map((e) => UserInteraction.fromMap(e as Map<String, dynamic>))
        .toList() ?? [];

    return CommunityWarning(
      id: map['id']?.toString().isNotEmpty == true ? map['id'] : null,
      type: map['type'] ?? '',
      severity: map['severity'] ?? 'medium',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      reportedBy: map['reportedBy'],
      reportedAt: parseTimestamp(map['reportedAt']),
      expiresAt: map['expiresAt'] != null ? parseTimestamp(map['expiresAt']) : null,
      isActive: map['isActive'] ?? true,
      tags: map['tags']?.cast<String>(),
      metadata: map['metadata'],
      userInteractions: interactionsList,
      isDeleted: map['isDeleted'] ?? false,
      deletedAt: map['deletedAt'] != null ? parseTimestamp(map['deletedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
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
      'userInteractions': userInteractions.map((e) => e.toMap()).toList(),
      'isDeleted': isDeleted,
    };

    // Only include ID if it's not null (for existing warnings)
    if (id != null && id!.isNotEmpty) {
      map['id'] = id;
    }

    // Only include deletedAt if item is deleted
    if (deletedAt != null) {
      map['deletedAt'] = deletedAt!.millisecondsSinceEpoch;
    }

    return map;
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
    List<UserInteraction>? userInteractions,
    bool? isDeleted,
    DateTime? deletedAt,
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
      userInteractions: userInteractions ?? this.userInteractions,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  String toString() {
    return 'CommunityWarning(id: ${id ?? 'new'}, type: $type, severity: $severity, title: $title)';
  }
}

