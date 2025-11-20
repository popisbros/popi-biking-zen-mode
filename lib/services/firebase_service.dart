import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/community_warning.dart';
import '../utils/app_logger.dart';

/// Firebase service for warning data management (without auth)
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // Lazy initialization - works on all platforms
  FirebaseFirestore? _firestore;

  FirebaseFirestore get _firestoreInstance {
    if (Firebase.apps.isEmpty) {
      throw Exception('Firebase not initialized - call Firebase.initializeApp() first');
    }
    _firestore ??= FirebaseFirestore.instance;
    return _firestore!;
  }

  // Collections
  static const String _warningsCollection = 'community_warnings';

  // ========== WARNING METHODS ==========

  /// Get all warnings as a stream
  Stream<QuerySnapshot> getAllWarnings() {
    return _firestoreInstance
        .collection(_warningsCollection)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get warnings in bounds (returns Future for one-time fetch)
  Future<List<CommunityWarning>> getWarningsInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    try {
      AppLogger.firebase('Loading warnings for bounds', data: {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
      });

      final snapshot = await _firestoreInstance
          .collection(_warningsCollection)
          .where('latitude', isGreaterThanOrEqualTo: south)
          .where('latitude', isLessThanOrEqualTo: north)
          .get();

      final warnings = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return CommunityWarning.fromMap({...data, 'id': doc.id});
          })
          .where((warning) => warning.longitude >= west && warning.longitude <= east)
          .toList();

      AppLogger.success('Loaded ${warnings.length} warnings');
      return warnings;
    } catch (e) {
      AppLogger.firebase('Error getting warnings', error: e);
      return [];
    }
  }

  /// Submit a new warning
  Future<void> submitWarning(Map<String, dynamic> warningData) async {
    try {
      await _firestoreInstance.collection(_warningsCollection).add({
        ...warningData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.success('Warning submitted successfully');
    } catch (e) {
      AppLogger.firebase('Error submitting warning', error: e);
      rethrow;
    }
  }

  /// Update an existing warning
  Future<void> updateWarning(String documentId, Map<String, dynamic> warningData) async {
    try {
      await _firestoreInstance.collection(_warningsCollection).doc(documentId).update({
        ...warningData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.success('Warning updated successfully');
    } catch (e) {
      AppLogger.firebase('Error updating warning', error: e);
      rethrow;
    }
  }

  /// Delete a warning
  Future<void> deleteWarning(String warningId) async {
    try {
      await _firestoreInstance.collection(_warningsCollection).doc(warningId).delete();
      AppLogger.success('Warning deleted successfully');
    } catch (e) {
      AppLogger.firebase('Error deleting warning', error: e);
      rethrow;
    }
  }

  // ========== VOTING & VERIFICATION METHODS ==========

  /// Upvote a warning
  /// Returns true if vote was successful, false if user already voted
  Future<bool> upvoteWarning(String warningId, String userId) async {
    try {
      final docRef = _firestoreInstance.collection(_warningsCollection).doc(warningId);

      return await _firestoreInstance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Warning not found');
        }

        final data = snapshot.data()!;
        final userVotes = Map<String, String>.from(data['userVotes'] ?? {});
        final currentVote = userVotes[userId];

        // Check if user already upvoted
        if (currentVote == 'up') {
          AppLogger.warning('User already upvoted this warning');
          return false;
        }

        int upvotes = data['upvotes'] ?? 0;
        int downvotes = data['downvotes'] ?? 0;

        // If user previously downvoted, remove downvote
        if (currentVote == 'down') {
          downvotes = (downvotes - 1).clamp(0, double.infinity).toInt();
        }

        // Add upvote
        upvotes++;
        userVotes[userId] = 'up';

        // Update vote history (keep last 5 votes, most recent first)
        final lastVotes = List<String>.from(data['lastVotes'] ?? []);
        lastVotes.insert(0, 'up'); // Add new vote at beginning
        if (lastVotes.length > 5) {
          lastVotes.removeLast(); // Keep only last 5
        }

        transaction.update(docRef, {
          'upvotes': upvotes,
          'downvotes': downvotes,
          'userVotes': userVotes,
          'lastVotes': lastVotes,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        AppLogger.success('Warning upvoted successfully');
        return true;
      });
    } catch (e) {
      AppLogger.firebase('Error upvoting warning', error: e);
      rethrow;
    }
  }

  /// Downvote a warning
  /// Returns true if vote was successful, false if user already voted
  Future<bool> downvoteWarning(String warningId, String userId) async {
    try {
      final docRef = _firestoreInstance.collection(_warningsCollection).doc(warningId);

      return await _firestoreInstance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Warning not found');
        }

        final data = snapshot.data()!;
        final userVotes = Map<String, String>.from(data['userVotes'] ?? {});
        final currentVote = userVotes[userId];

        // Check if user already downvoted
        if (currentVote == 'down') {
          AppLogger.warning('User already downvoted this warning');
          return false;
        }

        int upvotes = data['upvotes'] ?? 0;
        int downvotes = data['downvotes'] ?? 0;

        // If user previously upvoted, remove upvote
        if (currentVote == 'up') {
          upvotes = (upvotes - 1).clamp(0, double.infinity).toInt();
        }

        // Add downvote
        downvotes++;
        userVotes[userId] = 'down';

        // Update vote history (keep last 5 votes, most recent first)
        final lastVotes = List<String>.from(data['lastVotes'] ?? []);
        lastVotes.insert(0, 'down'); // Add new vote at beginning
        if (lastVotes.length > 5) {
          lastVotes.removeLast(); // Keep only last 5
        }

        // Calculate new vote score
        final voteScore = upvotes - downvotes;

        // Check for 3 consecutive downvotes
        final hasThreeConsecutiveDownvotes = lastVotes.length >= 3 &&
            lastVotes[0] == 'down' &&
            lastVotes[1] == 'down' &&
            lastVotes[2] == 'down';

        // Auto-resolve if score <= -3 OR 3 consecutive downvotes
        final Map<String, dynamic> updates = {
          'upvotes': upvotes,
          'downvotes': downvotes,
          'userVotes': userVotes,
          'lastVotes': lastVotes,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (data['status'] == 'active' && (voteScore <= -3 || hasThreeConsecutiveDownvotes)) {
          updates['status'] = 'resolved';
          updates['resolvedAt'] = FieldValue.serverTimestamp();
          updates['resolvedBy'] = 'community';
          final reason = hasThreeConsecutiveDownvotes ? '3 consecutive downvotes' : 'score <= -3';
          AppLogger.info('Auto-resolving warning due to $reason');
        }

        transaction.update(docRef, updates);

        final resolveMsg = (voteScore <= -3 || hasThreeConsecutiveDownvotes) ? ' (auto-resolved)' : '';
        AppLogger.success('Warning downvoted successfully$resolveMsg');
        return true;
      });
    } catch (e) {
      AppLogger.firebase('Error downvoting warning', error: e);
      rethrow;
    }
  }

  // ========== STATUS MANAGEMENT METHODS ==========

  /// Update warning status (active, resolved, disputed, expired)
  /// Only the reporter can update status
  Future<void> updateWarningStatus(String warningId, String status, String userId) async {
    try {
      final docRef = _firestoreInstance.collection(_warningsCollection).doc(warningId);
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        throw Exception('Warning not found');
      }

      final data = snapshot.data()!;
      final reportedBy = data['reportedBy'] as String?;

      // Only the reporter can update status
      if (reportedBy != userId) {
        throw Exception('Only the reporter can update warning status');
      }

      // Validate status
      if (!['active', 'resolved', 'disputed', 'expired'].contains(status)) {
        throw Exception('Invalid status: $status');
      }

      await docRef.update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      AppLogger.success('Warning status updated to: $status');
    } catch (e) {
      AppLogger.firebase('Error updating warning status', error: e);
      rethrow;
    }
  }

  /// Mark warning as resolved (convenience method)
  Future<void> resolveWarning(String warningId, String userId) async {
    return updateWarningStatus(warningId, 'resolved', userId);
  }

  /// Get expired warnings (for cleanup)
  Future<List<CommunityWarning>> getExpiredWarnings() async {
    try {
      final now = Timestamp.now();
      final snapshot = await _firestoreInstance
          .collection(_warningsCollection)
          .where('expiresAt', isLessThan: now)
          .where('status', isEqualTo: 'active')
          .get();

      final warnings = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return CommunityWarning.fromMap({...data, 'id': doc.id});
          })
          .toList();

      AppLogger.firebase('Found ${warnings.length} expired warnings');
      return warnings;
    } catch (e) {
      AppLogger.firebase('Error getting expired warnings', error: e);
      return [];
    }
  }

  /// Auto-expire warnings (mark as expired)
  Future<int> autoExpireWarnings() async {
    try {
      final expiredWarnings = await getExpiredWarnings();

      int count = 0;
      for (final warning in expiredWarnings) {
        if (warning.id != null) {
          await _firestoreInstance
              .collection(_warningsCollection)
              .doc(warning.id)
              .update({
            'status': 'expired',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          count++;
        }
      }

      AppLogger.success('Auto-expired $count warnings');
      return count;
    } catch (e) {
      AppLogger.firebase('Error auto-expiring warnings', error: e);
      return 0;
    }
  }
}
