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
  final String type; // pothole, construction, dangerous_intersection, poor_surface, debris, traffic_hazard, steep, flooding, other
  final String severity; // low, medium, high
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

  // NEW: Voting & Verification system
  final int upvotes;
  final int downvotes;
  final List<String> verifiedBy; // List of user IDs who verified
  final Map<String, String> userVotes; // userId -> 'up' or 'down'
  final List<String> lastVotes; // Last 5 votes: 'up' or 'down' (most recent first)

  // NEW: Status management
  final String status; // active, resolved, disputed, expired

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
    this.upvotes = 0,
    this.downvotes = 0,
    this.verifiedBy = const [],
    this.userVotes = const {},
    this.lastVotes = const [],
    this.status = 'active',
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

    // Parse verified by list
    final verifiedByList = (map['verifiedBy'] as List?)?.cast<String>() ?? [];

    // Parse user votes map
    final userVotesMap = (map['userVotes'] as Map<String, dynamic>?)?.map(
      (key, value) => MapEntry(key, value.toString()),
    ) ?? {};

    // Parse last votes list
    final lastVotesList = (map['lastVotes'] as List?)?.cast<String>() ?? [];

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
      upvotes: map['upvotes'] ?? 0,
      downvotes: map['downvotes'] ?? 0,
      verifiedBy: verifiedByList,
      userVotes: userVotesMap,
      lastVotes: lastVotesList,
      status: map['status'] ?? 'active',
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
      'upvotes': upvotes,
      'downvotes': downvotes,
      'verifiedBy': verifiedBy,
      'userVotes': userVotes,
      'lastVotes': lastVotes,
      'status': status,
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
    int? upvotes,
    int? downvotes,
    List<String>? verifiedBy,
    Map<String, String>? userVotes,
    List<String>? lastVotes,
    String? status,
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
      upvotes: upvotes ?? this.upvotes,
      downvotes: downvotes ?? this.downvotes,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      userVotes: userVotes ?? this.userVotes,
      lastVotes: lastVotes ?? this.lastVotes,
      status: status ?? this.status,
    );
  }

  // Computed properties for voting and verification
  int get voteScore => upvotes - downvotes;
  bool get isVerified => voteScore >= 3; // Verified when score reaches +3 or higher

  /// Get time since report in human-readable format
  String get timeSinceReport {
    final now = DateTime.now();
    final difference = now.difference(reportedAt);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} min${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'just now';
    }
  }

  @override
  String toString() {
    return 'CommunityWarning(id: ${id ?? 'new'}, type: $type, severity: $severity, title: $title, status: $status, voteScore: $voteScore)';
  }
}

