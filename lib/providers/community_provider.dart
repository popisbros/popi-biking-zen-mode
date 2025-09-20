import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/community_warning.dart';
import '../models/cycling_poi.dart';
import '../services/firebase_service.dart';
import '../services/debug_service.dart';
import 'osm_poi_provider.dart'; // Import BoundingBox

/// Provider for Firebase service
final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});

/// Provider for community warnings stream
final communityWarningsProvider = StreamProvider<List<CommunityWarning>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  final debugService = DebugService();
  
  // Log the start of warnings loading
  debugService.logAction(
    action: 'Firebase: Starting to load community warnings',
    screen: 'CommunityProvider',
  );
  
  // Get all warnings (no location filtering for debugging)
  return firebaseService.getNearbyWarnings(0, 0, 999999) // Large radius to get all warnings
      .map((snapshot) {
        debugService.logAction(
          action: 'Firebase: Received warnings snapshot',
          screen: 'CommunityProvider',
          parameters: {'docCount': snapshot.docs.length},
        );
        
        final warnings = snapshot.docs
            .map((doc) {
              try {
                return CommunityWarning.fromMap({
                  'id': doc.id,
                  ...doc.data() as Map<String, dynamic>,
                });
              } catch (e) {
                print('Error parsing warning document ${doc.id}: $e');
                print('Document data: ${doc.data()}');
                debugService.logAction(
                  action: 'Firebase: Error parsing warning document',
                  screen: 'CommunityProvider',
                  parameters: {'docId': doc.id, 'error': e.toString()},
                  error: e.toString(),
                );
                return null;
              }
            })
            .where((warning) => warning != null)
            .cast<CommunityWarning>()
            .toList();
        
        // Sort by creation date (newest first) client-side
        warnings.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
        
        return warnings;
      })
      .handleError((error) {
        print('Firestore stream error: $error');
        debugService.logAction(
          action: 'Firebase: Stream error loading warnings',
          screen: 'CommunityProvider',
          error: error.toString(),
        );
        if (error.toString().contains('CORS') || error.toString().contains('access control')) {
          print('CORS error detected - Firebase Firestore access blocked');
          debugService.logAction(
            action: 'Firebase: CORS error detected',
            screen: 'CommunityProvider',
            error: 'CORS error - Firebase Firestore access blocked',
          );
        }
        // Return empty list on error to prevent app crash
        return <CommunityWarning>[];
      });
});

/// Provider for cycling POIs stream
final cyclingPOIsProvider = StreamProvider<List<CyclingPOI>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  final debugService = DebugService();
  
  // Log the start of POIs loading
  debugService.logAction(
    action: 'Firebase: Starting to load cycling POIs',
    screen: 'CommunityProvider',
  );
  
  return firebaseService.getCyclingPOIs()
      .map((snapshot) {
        debugService.logAction(
          action: 'Firebase: Received POIs snapshot',
          screen: 'CommunityProvider',
          parameters: {'docCount': snapshot.docs.length},
        );
        
        return snapshot.docs
            .map((doc) {
              try {
                return CyclingPOI.fromMap({
                  'id': doc.id,
                  ...doc.data() as Map<String, dynamic>,
                });
              } catch (e) {
                print('Error parsing POI document ${doc.id}: $e');
                print('Document data: ${doc.data()}');
                debugService.logAction(
                  action: 'Firebase: Error parsing POI document',
                  screen: 'CommunityProvider',
                  parameters: {'docId': doc.id, 'error': e.toString()},
                  error: e.toString(),
                );
                return null;
              }
            })
            .where((poi) => poi != null)
            .cast<CyclingPOI>()
            .toList();
      })
      .handleError((error) {
        print('Firestore POI stream error: $error');
        debugService.logAction(
          action: 'Firebase: Stream error loading POIs',
          screen: 'CommunityProvider',
          error: error.toString(),
        );
        if (error.toString().contains('CORS') || error.toString().contains('access control')) {
          print('CORS error detected - Firebase Firestore access blocked');
          debugService.logAction(
            action: 'Firebase: CORS error detected',
            screen: 'CommunityProvider',
            error: 'CORS error - Firebase Firestore access blocked',
          );
        }
        // Return empty list on error to prevent app crash
        return <CyclingPOI>[];
      });
});

/// Notifier for community warnings management
class CommunityWarningsNotifier extends StateNotifier<AsyncValue<List<CommunityWarning>>> {
  final FirebaseService _firebaseService;
  
  CommunityWarningsNotifier(this._firebaseService) : super(const AsyncValue.loading()) {
    _loadWarnings();
  }
  
  Future<void> _loadWarnings() async {
    try {
      // Get initial warnings
      final warnings = await _getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  Future<List<CommunityWarning>> _getWarningsFromFirestore() async {
    final snapshot = await _firebaseService.getAllWarnings().first;
    return snapshot.docs
        .map((doc) => CommunityWarning.fromMap({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        }))
        .toList();
  }
  
  /// Submit a new warning
  Future<void> submitWarning(CommunityWarning warning) async {
    try {
      state = const AsyncValue.loading();
      await _firebaseService.submitWarning(warning.toMap());
      
      // Reload warnings
      final warnings = await _getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Update an existing warning
  Future<void> updateWarning(String documentId, CommunityWarning warning) async {
    try {
      state = const AsyncValue.loading();
      await _firebaseService.updateWarning(documentId, warning.toMap());
      
      // Reload warnings
      final warnings = await _getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Delete a warning
  Future<void> deleteWarning(String warningId) async {
    try {
      state = const AsyncValue.loading();
      await _firebaseService.deleteWarning(warningId);
      
      // Reload warnings
      final warnings = await _getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }
  
  /// Refresh warnings
  Future<void> refreshWarnings() async {
    await _loadWarnings();
  }
}

/// Provider for community warnings notifier
final communityWarningsNotifierProvider = StateNotifierProvider<CommunityWarningsNotifier, AsyncValue<List<CommunityWarning>>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return CommunityWarningsNotifier(firebaseService);
});

/// Notifier for cycling POIs management
class CyclingPOIsNotifier extends StateNotifier<AsyncValue<List<CyclingPOI>>> {
  final FirebaseService _firebaseService;
  
  CyclingPOIsNotifier(this._firebaseService) : super(const AsyncValue.loading()) {
    _loadPOIs();
  }
  
  Future<void> _loadPOIs() async {
    try {
      // Get initial POIs
      final pois = await _getPOIsFromFirestore();
      state = AsyncValue.data(pois);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  Future<List<CyclingPOI>> _getPOIsFromFirestore() async {
    final snapshot = await _firebaseService.getCyclingPOIs().first;
    return snapshot.docs
        .map((doc) => CyclingPOI.fromMap({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        }))
        .toList();
  }
  
  /// Add a new POI
  Future<void> addPOI(CyclingPOI poi) async {
    final debugService = DebugService();
    
    try {
      state = const AsyncValue.loading();
      
      debugService.logAction(
        action: 'POI: Starting Firebase addPOI call',
        screen: 'CyclingPOIsNotifier',
        parameters: {
          'poiName': poi.name,
          'poiType': poi.type,
          'poiData': poi.toMap(),
        },
      );
      
      // Actually call Firebase to add the POI
      await _firebaseService.addPOI(poi.toMap());
      
      debugService.logAction(
        action: 'POI: Successfully added to Firebase',
        screen: 'CyclingPOIsNotifier',
        result: 'POI created in Firestore',
      );
      
      // Reload POIs after successful creation
      final pois = await _getPOIsFromFirestore();
      state = AsyncValue.data(pois);
      
      debugService.logAction(
        action: 'POI: Reloaded POIs after creation',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiCount': pois.length},
      );
    } catch (error, stackTrace) {
      debugService.logAction(
        action: 'POI: Failed to add to Firebase',
        screen: 'CyclingPOIsNotifier',
        error: error.toString(),
      );
      
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Update an existing POI
  Future<void> updatePOI(String documentId, CyclingPOI poi) async {
    final debugService = DebugService();
    
    try {
      state = const AsyncValue.loading();
      
      debugService.logAction(
        action: 'POI: Starting Firebase updatePOI call',
        screen: 'CyclingPOIsNotifier',
        parameters: {
          'poiId': poi.id,
          'poiName': poi.name,
          'poiType': poi.type,
        },
      );
      
      // Call Firebase to update the POI
      await _firebaseService.updatePOI(documentId, poi.toMap());
      
      debugService.logAction(
        action: 'POI: Successfully updated in Firebase',
        screen: 'CyclingPOIsNotifier',
        result: 'POI updated in Firestore',
      );
      
      // Reload POIs after successful update
      final pois = await _getPOIsFromFirestore();
      state = AsyncValue.data(pois);
      
      debugService.logAction(
        action: 'POI: Reloaded POIs after update',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiCount': pois.length},
      );
    } catch (error, stackTrace) {
      debugService.logAction(
        action: 'POI: Failed to update in Firebase',
        screen: 'CyclingPOIsNotifier',
        error: error.toString(),
      );
      
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Delete a POI
  Future<void> deletePOI(String poiId) async {
    final debugService = DebugService();
    
    try {
      state = const AsyncValue.loading();
      
      debugService.logAction(
        action: 'POI: Starting Firebase deletePOI call',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiId': poiId},
      );
      
      // Call Firebase to delete the POI
      await _firebaseService.deletePOI(poiId);
      
      debugService.logAction(
        action: 'POI: Successfully deleted from Firebase',
        screen: 'CyclingPOIsNotifier',
        result: 'POI deleted from Firestore',
      );
      
      // Reload POIs after successful deletion
      final pois = await _getPOIsFromFirestore();
      state = AsyncValue.data(pois);
      
      debugService.logAction(
        action: 'POI: Reloaded POIs after deletion',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiCount': pois.length},
      );
    } catch (error, stackTrace) {
      debugService.logAction(
        action: 'POI: Failed to delete from Firebase',
        screen: 'CyclingPOIsNotifier',
        error: error.toString(),
      );
      
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }
  
  /// Refresh POIs
  Future<void> refreshPOIs() async {
    await _loadPOIs();
  }
}

/// Provider for cycling POIs notifier
final cyclingPOIsNotifierProvider = StateNotifierProvider<CyclingPOIsNotifier, AsyncValue<List<CyclingPOI>>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return CyclingPOIsNotifier(firebaseService);
});

// BoundingBox class is imported from osm_poi_provider.dart

/// State notifier for bounds-based community warnings
class CommunityWarningsBoundsNotifier extends StateNotifier<AsyncValue<List<CommunityWarning>>> {
  final FirebaseService _firebaseService;
  final DebugService _debugService = DebugService();
  BoundingBox? _lastLoadedBounds;

  CommunityWarningsBoundsNotifier(this._firebaseService) : super(const AsyncValue.loading());

  /// Load warnings using actual map bounds
  Future<void> loadWarningsWithBounds(BoundingBox bounds) async {
    print('Community Warnings Bounds Notifier: Loading warnings with bounds=$bounds');
    state = const AsyncValue.loading();
    
    try {
      final snapshot = await _firebaseService.getWarningsInBounds(
        bounds.south,
        bounds.west,
        bounds.north,
        bounds.east,
      ).first;
      
      final warnings = snapshot.docs
          .map((doc) {
            try {
              return CommunityWarning.fromMap({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              });
            } catch (e) {
              print('Error parsing warning document ${doc.id}: $e');
              return null;
            }
          })
          .where((warning) => warning != null)
          .cast<CommunityWarning>()
          .toList();
      
      // Client-side filtering by bounds
      final filteredWarnings = warnings.where((warning) {
        return warning.latitude >= bounds.south &&
               warning.latitude <= bounds.north &&
               warning.longitude >= bounds.west &&
               warning.longitude <= bounds.east;
      }).toList();
      
      print('Community Warnings Bounds Notifier: Loaded ${filteredWarnings.length} warnings with bounds');
      state = AsyncValue.data(filteredWarnings);
      _lastLoadedBounds = bounds;
    } catch (error, stackTrace) {
      print('Community Warnings Bounds Notifier: Error loading warnings with bounds: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  /// Force reload warnings using the last known bounds
  Future<void> forceReload() async {
    if (_lastLoadedBounds != null) {
      print('Community Warnings Bounds Notifier: Force reloading with last known bounds=$_lastLoadedBounds');
      await loadWarningsWithBounds(_lastLoadedBounds!);
    } else {
      print('Community Warnings Bounds Notifier: Force reload called but no previous bounds available');
      state = const AsyncValue.data([]);
    }
  }
}

/// State notifier for bounds-based cycling POIs
class CyclingPOIsBoundsNotifier extends StateNotifier<AsyncValue<List<CyclingPOI>>> {
  final FirebaseService _firebaseService;
  final DebugService _debugService = DebugService();
  BoundingBox? _lastLoadedBounds;

  CyclingPOIsBoundsNotifier(this._firebaseService) : super(const AsyncValue.loading());

  /// Load POIs using actual map bounds
  Future<void> loadPOIsWithBounds(BoundingBox bounds) async {
    print('Cycling POIs Bounds Notifier: Loading POIs with bounds=$bounds');
    state = const AsyncValue.loading();
    
    try {
      final snapshot = await _firebaseService.getPOIsInBounds(
        bounds.south,
        bounds.west,
        bounds.north,
        bounds.east,
      ).first;
      
      final pois = snapshot.docs
          .map((doc) {
            try {
              return CyclingPOI.fromMap({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              });
            } catch (e) {
              print('Error parsing POI document ${doc.id}: $e');
              return null;
            }
          })
          .where((poi) => poi != null)
          .cast<CyclingPOI>()
          .toList();
      
      // Client-side filtering by bounds
      final filteredPOIs = pois.where((poi) {
        return poi.latitude >= bounds.south &&
               poi.latitude <= bounds.north &&
               poi.longitude >= bounds.west &&
               poi.longitude <= bounds.east;
      }).toList();
      
      print('Cycling POIs Bounds Notifier: Loaded ${filteredPOIs.length} POIs with bounds');
      state = AsyncValue.data(filteredPOIs);
      _lastLoadedBounds = bounds;
    } catch (error, stackTrace) {
      print('Cycling POIs Bounds Notifier: Error loading POIs with bounds: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  /// Force reload POIs using the last known bounds
  Future<void> forceReload() async {
    if (_lastLoadedBounds != null) {
      print('Cycling POIs Bounds Notifier: Force reloading with last known bounds=$_lastLoadedBounds');
      await loadPOIsWithBounds(_lastLoadedBounds!);
    } else {
      print('Cycling POIs Bounds Notifier: Force reload called but no previous bounds available');
      state = const AsyncValue.data([]);
    }
  }
}

/// Provider for bounds-based community warnings notifier
final communityWarningsBoundsNotifierProvider = StateNotifierProvider<CommunityWarningsBoundsNotifier, AsyncValue<List<CommunityWarning>>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return CommunityWarningsBoundsNotifier(firebaseService);
});

/// Provider for bounds-based cycling POIs notifier
final cyclingPOIsBoundsNotifierProvider = StateNotifierProvider<CyclingPOIsBoundsNotifier, AsyncValue<List<CyclingPOI>>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return CyclingPOIsBoundsNotifier(firebaseService);
});

