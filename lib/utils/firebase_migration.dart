import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Firebase data migration utilities
/// Use these to migrate existing data when schema changes
class FirebaseMigration {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Migrate existing hazards to include new voting and verification fields
  ///
  /// This adds:
  /// - upvotes: 0
  /// - downvotes: 0
  /// - verifiedBy: []
  /// - userVotes: {}
  /// - status: 'active'
  ///
  /// Also calculates expiration dates based on hazard type:
  /// - construction: 60 days
  /// - traffic_hazard: 14 days
  /// - flooding: 7 days
  /// - steep: 90 days (permanent terrain features)
  /// - poor_surface: 30 days
  /// - debris: 7 days
  /// - pothole: 30 days
  /// - dangerous_intersection: 90 days (permanent infrastructure)
  /// - other: 30 days
  static Future<void> migrateHazards({
    bool dryRun = true,
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('Starting hazard migration...');

      // Fetch all communityWarnings documents
      final QuerySnapshot snapshot = await _firestore
          .collection('communityWarnings')
          .get();

      onProgress?.call('Found ${snapshot.docs.length} hazards to migrate');

      int migrated = 0;
      int skipped = 0;
      int errors = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          // Check if already migrated (has upvotes field)
          if (data.containsKey('upvotes')) {
            skipped++;
            continue;
          }

          // Calculate expiration date based on type
          final type = data['type'] as String? ?? 'other';
          final reportedAt = (data['reportedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final expirationDays = _getExpirationDays(type);
          final expiresAt = reportedAt.add(Duration(days: expirationDays));

          // Prepare update data
          final updateData = {
            'upvotes': 0,
            'downvotes': 0,
            'verifiedBy': [],
            'userVotes': {},
            'status': 'active',
            'expiresAt': Timestamp.fromDate(expiresAt),
          };

          if (dryRun) {
            debugPrint('DRY RUN: Would update ${doc.id} with $updateData');
          } else {
            await doc.reference.update(updateData);
            debugPrint('Migrated hazard ${doc.id}');
          }

          migrated++;
        } catch (e) {
          errors++;
          onProgress?.call('Error migrating ${doc.id}: $e');
        }
      }

      final summary = '''
Migration ${dryRun ? '(DRY RUN)' : ''} completed:
- Total hazards: ${snapshot.docs.length}
- Migrated: $migrated
- Skipped (already migrated): $skipped
- Errors: $errors
''';
      onProgress?.call(summary);
    } catch (e) {
      onProgress?.call('Migration failed: $e');
      rethrow;
    }
  }

  /// Get expiration days for a hazard type
  static int _getExpirationDays(String type) {
    switch (type) {
      case 'construction':
        return 60; // Construction sites last months
      case 'traffic_hazard':
        return 14; // Traffic issues usually temporary
      case 'flooding':
        return 7; // Weather-related, short-term
      case 'steep':
        return 90; // Permanent terrain feature
      case 'poor_surface':
        return 30; // Surface degradation is gradual
      case 'debris':
        return 7; // Usually cleaned up quickly
      case 'pothole':
        return 30; // Takes time to fix
      case 'dangerous_intersection':
        return 90; // Permanent infrastructure issue
      case 'other':
      default:
        return 30; // Default
    }
  }

  /// Migrate user profiles to include new preference fields
  ///
  /// This adds:
  /// - lastUsedRouteProfile: null
  /// - appearanceMode: 'system'
  /// - audioAlertsEnabled: true
  static Future<void> migrateUserProfiles({
    bool dryRun = true,
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('Starting user profile migration...');

      final QuerySnapshot snapshot = await _firestore
          .collection('users')
          .get();

      onProgress?.call('Found ${snapshot.docs.length} user profiles to migrate');

      int migrated = 0;
      int skipped = 0;
      int errors = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          // Check if already migrated (has appearanceMode field)
          if (data.containsKey('appearanceMode')) {
            skipped++;
            continue;
          }

          // Prepare update data
          final updateData = {
            'lastUsedRouteProfile': null,
            'appearanceMode': 'system',
            'audioAlertsEnabled': true,
            'updatedAt': FieldValue.serverTimestamp(),
          };

          if (dryRun) {
            debugPrint('DRY RUN: Would update user ${doc.id} with $updateData');
          } else {
            await doc.reference.update(updateData);
            debugPrint('Migrated user profile ${doc.id}');
          }

          migrated++;
        } catch (e) {
          errors++;
          onProgress?.call('Error migrating user ${doc.id}: $e');
        }
      }

      final summary = '''
User profile migration ${dryRun ? '(DRY RUN)' : ''} completed:
- Total users: ${snapshot.docs.length}
- Migrated: $migrated
- Skipped (already migrated): $skipped
- Errors: $errors
''';
      onProgress?.call(summary);
    } catch (e) {
      onProgress?.call('User profile migration failed: $e');
      rethrow;
    }
  }

  /// Run all migrations
  static Future<void> migrateAll({
    bool dryRun = true,
    Function(String)? onProgress,
  }) async {
    onProgress?.call('=== Starting Full Migration ===\n');

    await migrateHazards(dryRun: dryRun, onProgress: onProgress);
    onProgress?.call('\n---\n');

    await migrateUserProfiles(dryRun: dryRun, onProgress: onProgress);

    onProgress?.call('\n=== Migration Complete ===');
  }
}
