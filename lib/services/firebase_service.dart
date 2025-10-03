import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';
import '../utils/app_logger.dart';

/// Firebase service for POI and warning data management (without auth)
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
  static const String _poisCollection = 'cycling_pois';

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

  // ========== POI METHODS ==========

  /// Get all cycling POIs as a stream
  Stream<QuerySnapshot> getCyclingPOIs() {
    return _firestoreInstance
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
      AppLogger.firebase('Loading POIs for bounds', data: {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
      });

      final snapshot = await _firestoreInstance
          .collection(_poisCollection)
          .where('latitude', isGreaterThanOrEqualTo: south)
          .where('latitude', isLessThanOrEqualTo: north)
          .get();

      final pois = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data();
              final poi = CyclingPOI.fromMap({...data, 'id': doc.id});
              AppLogger.firebase('Parsed POI ${doc.id}: ${poi.name} at (${poi.latitude}, ${poi.longitude})');
              return poi;
            } catch (e, stackTrace) {
              AppLogger.error('Error parsing POI document', error: e, data: {
                'docId': doc.id,
                'docData': doc.data(),
                'stackTrace': stackTrace.toString().split('\n').take(3).join('\n'),
              });
              return null;
            }
          })
          .where((poi) => poi != null && poi!.longitude >= west && poi.longitude <= east)
          .cast<CyclingPOI>()
          .toList();

      AppLogger.success('Loaded ${pois.length} POIs (from ${snapshot.docs.length} documents)');
      return pois;
    } catch (e) {
      AppLogger.firebase('Error getting POIs', error: e);
      return [];
    }
  }

  /// Add a new POI
  Future<void> addPOI(Map<String, dynamic> poiData) async {
    try {
      await _firestoreInstance.collection(_poisCollection).add({
        ...poiData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.success('POI added successfully');
    } catch (e) {
      AppLogger.firebase('Error adding POI', error: e);
      rethrow;
    }
  }

  /// Update an existing POI
  Future<void> updatePOI(String documentId, Map<String, dynamic> poiData) async {
    try {
      await _firestoreInstance.collection(_poisCollection).doc(documentId).update({
        ...poiData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.success('POI updated successfully');
    } catch (e) {
      AppLogger.firebase('Error updating POI', error: e);
      rethrow;
    }
  }

  /// Delete a POI
  Future<void> deletePOI(String poiId) async {
    try {
      await _firestoreInstance.collection(_poisCollection).doc(poiId).delete();
      AppLogger.success('POI deleted successfully');
    } catch (e) {
      AppLogger.firebase('Error deleting POI', error: e);
      rethrow;
    }
  }
}
