import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';

/// Firebase service for POI and warning data management (without auth)
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collections
  static const String _warningsCollection = 'community_warnings';
  static const String _poisCollection = 'cycling_pois';

  // ========== WARNING METHODS ==========

  /// Get all warnings as a stream
  Stream<QuerySnapshot> getAllWarnings() {
    return _firestore
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
      print('FirebaseService.getWarningsInBounds: Loading warnings for bounds south=$south, west=$west, north=$north, east=$east');

      final snapshot = await _firestore
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

      print('FirebaseService: Loaded ${warnings.length} warnings');
      return warnings;
    } catch (e) {
      print('Error getting warnings: $e');
      return [];
    }
  }

  /// Submit a new warning
  Future<void> submitWarning(Map<String, dynamic> warningData) async {
    try {
      await _firestore.collection(_warningsCollection).add({
        ...warningData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('FirebaseService: Warning submitted successfully');
    } catch (e) {
      print('Error submitting warning: $e');
      rethrow;
    }
  }

  /// Update an existing warning
  Future<void> updateWarning(String documentId, Map<String, dynamic> warningData) async {
    try {
      await _firestore.collection(_warningsCollection).doc(documentId).update({
        ...warningData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('FirebaseService: Warning updated successfully');
    } catch (e) {
      print('Error updating warning: $e');
      rethrow;
    }
  }

  /// Delete a warning
  Future<void> deleteWarning(String warningId) async {
    try {
      await _firestore.collection(_warningsCollection).doc(warningId).delete();
      print('FirebaseService: Warning deleted successfully');
    } catch (e) {
      print('Error deleting warning: $e');
      rethrow;
    }
  }

  // ========== POI METHODS ==========

  /// Get all cycling POIs as a stream
  Stream<QuerySnapshot> getCyclingPOIs() {
    return _firestore
        .collection(_poisCollection)
        .orderBy('name')
        .snapshots();
  }

  /// Get POIs in bounds (returns Future for one-time fetch)
  Future<List<CyclingPOI>> getPOIsInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    try {
      print('FirebaseService.getPOIsInBounds: Loading POIs for bounds south=$south, west=$west, north=$north, east=$east');

      final snapshot = await _firestore
          .collection(_poisCollection)
          .where('latitude', isGreaterThanOrEqualTo: south)
          .where('latitude', isLessThanOrEqualTo: north)
          .get();

      final pois = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data();
              return CyclingPOI.fromMap({...data, 'id': doc.id});
            } catch (e) {
              print('Error parsing POI document ${doc.id}: $e');
              return null;
            }
          })
          .where((poi) => poi != null && poi!.longitude >= west && poi.longitude <= east)
          .cast<CyclingPOI>()
          .toList();

      print('FirebaseService: Loaded ${pois.length} POIs');
      return pois;
    } catch (e) {
      print('Error getting POIs: $e');
      return [];
    }
  }

  /// Add a new POI
  Future<void> addPOI(Map<String, dynamic> poiData) async {
    try {
      await _firestore.collection(_poisCollection).add({
        ...poiData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('FirebaseService: POI added successfully');
    } catch (e) {
      print('Error adding POI: $e');
      rethrow;
    }
  }

  /// Update an existing POI
  Future<void> updatePOI(String documentId, Map<String, dynamic> poiData) async {
    try {
      await _firestore.collection(_poisCollection).doc(documentId).update({
        ...poiData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('FirebaseService: POI updated successfully');
    } catch (e) {
      print('Error updating POI: $e');
      rethrow;
    }
  }

  /// Delete a POI
  Future<void> deletePOI(String poiId) async {
    try {
      await _firestore.collection(_poisCollection).doc(poiId).delete();
      print('FirebaseService: POI deleted successfully');
    } catch (e) {
      print('Error deleting POI: $e');
      rethrow;
    }
  }
}
