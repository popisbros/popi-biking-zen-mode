import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile model with authentication and preferences
class UserProfile {
  final String uid; // Firebase Auth UID
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? photoURL;
  final String? country;
  final String authProvider; // 'google', 'apple', 'email'

  // User preferences
  final String defaultRouteProfile; // 'bike', 'car', 'foot'
  final List<String> recentSearches; // Last 20 search queries
  final List<SavedLocation> recentDestinations; // Last 20 destinations
  final List<SavedLocation> favoriteLocations; // Up to 20 favorites

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.uid,
    this.email,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.photoURL,
    this.country,
    required this.authProvider,
    this.defaultRouteProfile = 'bike',
    this.recentSearches = const [],
    this.recentDestinations = const [],
    this.favoriteLocations = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get full name from first and last name
  String? get displayName {
    if (firstName == null && lastName == null) return null;
    return '${firstName ?? ''} ${lastName ?? ''}'.trim();
  }

  /// Get initials from first and last name (e.g., "John Doe" -> "JD")
  String getInitials() {
    final first = firstName?.trim();
    final last = lastName?.trim();

    if (first != null && first.isNotEmpty && last != null && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    } else if (first != null && first.isNotEmpty) {
      return first[0].toUpperCase();
    } else if (last != null && last.isNotEmpty) {
      return last[0].toUpperCase();
    }
    return '?';
  }

  /// Create from Firebase Auth User
  /// Splits displayName into firstName and lastName if provided
  factory UserProfile.fromAuth({
    required String uid,
    String? email,
    String? displayName,
    String? phoneNumber,
    String? photoURL,
    required String authProvider,
  }) {
    final now = DateTime.now();

    // Split displayName into firstName and lastName
    String? firstName;
    String? lastName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      final parts = displayName.trim().split(' ');
      firstName = parts.first;
      if (parts.length > 1) {
        lastName = parts.sublist(1).join(' ');
      }
    }

    return UserProfile(
      uid: uid,
      email: email,
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      photoURL: photoURL,
      authProvider: authProvider,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create from Firestore document
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Support both old (displayName) and new (firstName/lastName) formats
    String? firstName = data['firstName'];
    String? lastName = data['lastName'];

    // Migration: if firstName/lastName not present but displayName is, split it
    if (firstName == null && lastName == null && data['displayName'] != null) {
      final displayName = data['displayName'] as String;
      if (displayName.trim().isNotEmpty) {
        final parts = displayName.trim().split(' ');
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }
    }

    return UserProfile(
      uid: doc.id,
      email: data['email'],
      firstName: firstName,
      lastName: lastName,
      phoneNumber: data['phoneNumber'],
      photoURL: data['photoURL'],
      country: data['country'],
      authProvider: data['authProvider'] ?? 'email',
      defaultRouteProfile: data['defaultRouteProfile'] ?? 'bike',
      recentSearches: List<String>.from(data['recentSearches'] ?? []),
      recentDestinations: (data['recentDestinations'] as List<dynamic>?)
              ?.map((e) => SavedLocation.fromMap(e))
              .toList() ??
          [],
      favoriteLocations: (data['favoriteLocations'] as List<dynamic>?)
              ?.map((e) => SavedLocation.fromMap(e))
              .toList() ??
          [],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'photoURL': photoURL,
      'country': country,
      'authProvider': authProvider,
      'defaultRouteProfile': defaultRouteProfile,
      'recentSearches': recentSearches,
      'recentDestinations': recentDestinations.map((e) => e.toMap()).toList(),
      'favoriteLocations': favoriteLocations.map((e) => e.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Copy with method for updates
  UserProfile copyWith({
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? photoURL,
    String? country,
    String? defaultRouteProfile,
    List<String>? recentSearches,
    List<SavedLocation>? recentDestinations,
    List<SavedLocation>? favoriteLocations,
  }) {
    return UserProfile(
      uid: uid,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoURL: photoURL ?? this.photoURL,
      country: country ?? this.country,
      authProvider: authProvider,
      defaultRouteProfile: defaultRouteProfile ?? this.defaultRouteProfile,
      recentSearches: recentSearches ?? this.recentSearches,
      recentDestinations: recentDestinations ?? this.recentDestinations,
      favoriteLocations: favoriteLocations ?? this.favoriteLocations,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Saved location for destinations and favorites
class SavedLocation {
  final String name;
  final double latitude;
  final double longitude;
  final DateTime savedAt;

  const SavedLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.savedAt,
  });

  factory SavedLocation.fromMap(Map<String, dynamic> map) {
    return SavedLocation(
      name: map['name'] ?? '',
      latitude: map['latitude'] ?? 0.0,
      longitude: map['longitude'] ?? 0.0,
      savedAt: (map['savedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'savedAt': Timestamp.fromDate(savedAt),
    };
  }
}
