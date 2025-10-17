import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/community_warning.dart';
import '../models/cycling_poi.dart';
import '../services/firebase_service.dart';
import '../services/debug_service.dart';
import '../utils/app_logger.dart';
import '../utils/debug_message_helper.dart';
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
  return firebaseService.getAllWarnings()
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
                AppLogger.error(
                  'Error parsing warning document',
                  error: e,
                  data: {
                    'docId': doc.id,
                    'docData': doc.data(),
                  },
                );
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
        AppLogger.firebase('Firestore stream error loading warnings', error: error);
        debugService.logAction(
          action: 'Firebase: Stream error loading warnings',
          screen: 'CommunityProvider',
          error: error.toString(),
        );
        if (error.toString().contains('CORS') || error.toString().contains('access control')) {
          AppLogger.error('CORS error detected - Firebase Firestore access blocked', error: error);
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
                AppLogger.error(
                  'Error parsing POI document',
                  error: e,
                  data: {
                    'docId': doc.id,
                    'docData': doc.data(),
                  },
                );
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
        AppLogger.firebase('Firestore stream error loading POIs', error: error);
        debugService.logAction(
          action: 'Firebase: Stream error loading POIs',
          screen: 'CommunityProvider',
          error: error.toString(),
        );
        if (error.toString().contains('CORS') || error.toString().contains('access control')) {
          AppLogger.error('CORS error detected - Firebase Firestore access blocked', error: error);
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
class CommunityWarningsNotifier extends Notifier<AsyncValue<List<CommunityWarning>>> {
  late final FirebaseService _firebaseService;

  @override
  AsyncValue<List<CommunityWarning>> build() {
    _firebaseService = ref.watch(firebaseServiceProvider);
    _loadWarnings();
    return const AsyncValue.loading();
  }
  
  Future<void> _loadWarnings() async {
    try {
      // Get initial warnings
      final warnings = await getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  Future<List<CommunityWarning>> getWarningsFromFirestore() async {
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
      final warnings = await getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
      
      // Trigger background refresh of all map data
      _triggerOSMBackgroundRefresh();
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
      final warnings = await getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
      
      // Trigger background refresh of all map data
      _triggerOSMBackgroundRefresh();
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
      final warnings = await getWarningsFromFirestore();
      state = AsyncValue.data(warnings);
      
      // Trigger background refresh of all map data
      _triggerOSMBackgroundRefresh();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }
  
  /// Refresh warnings
  Future<void> refreshWarnings() async {
    await _loadWarnings();
  }
  
  /// Trigger background refresh of all map data (POIs, Hazards, OSM POIs)
  Future<void> _triggerOSMBackgroundRefresh() async {
    try {
      // Trigger a global refresh by incrementing the refresh counter
      // This will cause the map screen to reload all data
      AppLogger.firebase('Triggering global map data refresh after POI/Hazard operation');

      final refreshNotifier = ref.read(mapDataRefreshTriggerProvider.notifier);
      refreshNotifier.triggerRefresh();

      AppLogger.success('Global map data refresh triggered');
    } catch (e) {
      AppLogger.error('Failed to trigger global map data refresh', error: e);
      // Don't throw - this is a background operation
    }
  }
}

/// Provider for community warnings notifier
final communityWarningsNotifierProvider = NotifierProvider<CommunityWarningsNotifier, AsyncValue<List<CommunityWarning>>>(CommunityWarningsNotifier.new);

/// Notifier for cycling POIs management
class CyclingPOIsNotifier extends Notifier<AsyncValue<List<CyclingPOI>>> {
  late final FirebaseService _firebaseService;

  @override
  AsyncValue<List<CyclingPOI>> build() {
    _firebaseService = ref.watch(firebaseServiceProvider);
    _loadPOIs();
    return const AsyncValue.loading();
  }
  
  Future<void> _loadPOIs() async {
    try {
      // Get initial POIs
      final pois = await getPOIsFromFirestore();
      state = AsyncValue.data(pois);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  Future<List<CyclingPOI>> getPOIsFromFirestore() async {
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
      final pois = await getPOIsFromFirestore();
      state = AsyncValue.data(pois);
      
      debugService.logAction(
        action: 'POI: Reloaded POIs after creation',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiCount': pois.length},
      );
      
      // Trigger background refresh of all map data
      _triggerOSMBackgroundRefresh();
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
      final pois = await getPOIsFromFirestore();
      state = AsyncValue.data(pois);
      
      debugService.logAction(
        action: 'POI: Reloaded POIs after update',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiCount': pois.length},
      );
      
      // Trigger background refresh of all map data
      _triggerOSMBackgroundRefresh();
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
      final pois = await getPOIsFromFirestore();
      state = AsyncValue.data(pois);
      
      debugService.logAction(
        action: 'POI: Reloaded POIs after deletion',
        screen: 'CyclingPOIsNotifier',
        parameters: {'poiCount': pois.length},
      );
      
      // Trigger background refresh of all map data
      _triggerOSMBackgroundRefresh();
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
  
  /// Trigger background refresh of all map data (POIs, Hazards, OSM POIs)
  Future<void> _triggerOSMBackgroundRefresh() async {
    try {
      // Trigger a global refresh by incrementing the refresh counter
      // This will cause the map screen to reload all data
      AppLogger.firebase('Triggering global map data refresh after POI/Hazard operation');

      final refreshNotifier = ref.read(mapDataRefreshTriggerProvider.notifier);
      refreshNotifier.triggerRefresh();

      AppLogger.success('Global map data refresh triggered');
    } catch (e) {
      AppLogger.error('Failed to trigger global map data refresh', error: e);
      // Don't throw - this is a background operation
    }
  }
}

/// Provider for cycling POIs notifier
final cyclingPOIsNotifierProvider = NotifierProvider<CyclingPOIsNotifier, AsyncValue<List<CyclingPOI>>>(CyclingPOIsNotifier.new);

// BoundingBox class is imported from osm_poi_provider.dart

/// State notifier for bounds-based community warnings
class CommunityWarningsBoundsNotifier extends Notifier<AsyncValue<List<CommunityWarning>>> {
  late final FirebaseService _firebaseService;
  final DebugService _debugService = DebugService();
  BoundingBox? _lastLoadedBounds;

  @override
  AsyncValue<List<CommunityWarning>> build() {
    _firebaseService = ref.watch(firebaseServiceProvider);
    return const AsyncValue.loading();
  }

  /// Load warnings using actual map bounds
  Future<void> loadWarningsWithBounds(BoundingBox bounds) async {
    AppLogger.firebase('Loading warnings with bounds', data: {
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
    });
    state = const AsyncValue.loading();

    try {
      DebugMessageHelper.addMessage(
        ref,
        'API: Fetching warnings [${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)} to ${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}]',
        tag: 'COMMUNITY',
      );

      final warnings = await _firebaseService.getWarningsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      // warnings is already a List<CommunityWarning>
      /*
      final warnings = snapshot.docs
          .map((doc) {
            try {
              return CommunityWarning.fromMap({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              });
            } catch (e) {
              AppLogger.error('Error parsing warning document', error: e, data: {'docId': doc.id});
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
      */

      DebugMessageHelper.addMessage(ref, 'API: Got ${warnings.length} warnings', tag: 'COMMUNITY');
      AppLogger.success('Loaded ${warnings.length} warnings with bounds');
      state = AsyncValue.data(warnings);
      _lastLoadedBounds = bounds;
    } catch (error, stackTrace) {
      AppLogger.firebase('Error loading warnings with bounds', error: error);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Load warnings in background without clearing existing data
  Future<void> loadWarningsInBackground(BoundingBox bounds) async {
    AppLogger.firebase('Loading warnings in background with bounds', data: {
      'south': bounds.south,
      'north': bounds.north,
      'west': bounds.west,
      'east': bounds.east,
    });
    // Don't set loading state - keep existing data visible

    try {
      DebugMessageHelper.addMessage(
        ref,
        'API: Fetching warnings [${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)} to ${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}]',
        tag: 'COMMUNITY',
      );

      final newWarnings = await _firebaseService.getWarningsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      DebugMessageHelper.addMessage(ref, 'API: Got ${newWarnings.length} warnings', tag: 'COMMUNITY');

      AppLogger.success('Loaded warnings in background', tag: 'COMMUNITY', data: {'count': newWarnings.length});

      // Filter existing warnings to keep only those within the new bounds
      final currentWarnings = state.value ?? [];
      final filteredCurrentWarnings = currentWarnings.where((warning) {
        return warning.latitude >= bounds.south &&
               warning.latitude <= bounds.north &&
               warning.longitude >= bounds.west &&
               warning.longitude <= bounds.east;
      }).toList();

      AppLogger.success('Filtered ${currentWarnings.length} existing warnings to ${filteredCurrentWarnings.length} within bounds');

      // Merge filtered existing data with new warnings to avoid duplicates
      final mergedWarnings = _mergeWarnings(filteredCurrentWarnings, newWarnings);

      AppLogger.success('Merged ${filteredCurrentWarnings.length} existing + ${newWarnings.length} new = ${mergedWarnings.length} total warnings');
      state = AsyncValue.data(mergedWarnings);
      _lastLoadedBounds = bounds;
    } catch (e) {
      AppLogger.error('Error loading warnings in background', error: e);
      // Don't change state on error - keep existing data
    }
  }

  /// Merge warnings to avoid duplicates
  List<CommunityWarning> _mergeWarnings(List<CommunityWarning> existing, List<CommunityWarning> newWarnings) {
    final Map<String, CommunityWarning> mergedMap = {};

    // Add existing warnings
    for (final warning in existing) {
      if (warning.id != null) {
        mergedMap[warning.id!] = warning;
      }
    }

    // Add new warnings (will overwrite duplicates)
    for (final warning in newWarnings) {
      if (warning.id != null) {
        mergedMap[warning.id!] = warning;
      }
    }

    return mergedMap.values.toList();
  }

  /// Force reload warnings using the last known bounds
  Future<void> forceReload() async {
    if (_lastLoadedBounds != null) {
      AppLogger.firebase('Force reloading warnings with last known bounds', data: {
        'bounds': _lastLoadedBounds.toString(),
      });
      await loadWarningsWithBounds(_lastLoadedBounds!);
    } else {
      AppLogger.firebase('Force reload called but no previous bounds available');
      state = const AsyncValue.data([]);
    }
  }
}

/// State notifier for bounds-based cycling POIs
class CyclingPOIsBoundsNotifier extends Notifier<AsyncValue<List<CyclingPOI>>> {
  late final FirebaseService _firebaseService;
  final DebugService _debugService = DebugService();
  BoundingBox? _lastLoadedBounds;

  @override
  AsyncValue<List<CyclingPOI>> build() {
    _firebaseService = ref.watch(firebaseServiceProvider);
    return const AsyncValue.loading();
  }

  /// Load POIs using actual map bounds
  Future<void> loadPOIsWithBounds(BoundingBox bounds) async {
    AppLogger.firebase('Loading POIs with bounds', data: {
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
    });
    state = const AsyncValue.loading();

    try {
      DebugMessageHelper.addMessage(
        ref,
        'API: Fetching POIs [${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)} to ${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}]',
        tag: 'COMMUNITY',
      );

      final pois = await _firebaseService.getPOIsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      // pois is already a List<CyclingPOI>
      /*
      final pois = snapshot.docs
          .map((doc) {
            try {
              return CyclingPOI.fromMap({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              });
            } catch (e) {
              AppLogger.error('Error parsing POI document', error: e, data: {'docId': doc.id});
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
      */

      DebugMessageHelper.addMessage(ref, 'API: Got ${pois.length} POIs', tag: 'COMMUNITY');
      AppLogger.success('Loaded ${pois.length} POIs with bounds');
      state = AsyncValue.data(pois);
      _lastLoadedBounds = bounds;
    } catch (error, stackTrace) {
      AppLogger.firebase('Error loading POIs with bounds', error: error);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Load POIs in background without clearing existing data
  Future<void> loadPOIsInBackground(BoundingBox bounds) async {
    AppLogger.firebase('Loading POIs in background with bounds', data: {
      'south': bounds.south,
      'north': bounds.north,
      'west': bounds.west,
      'east': bounds.east,
    });
    // Don't set loading state - keep existing data visible

    try {
      DebugMessageHelper.addMessage(
        ref,
        'API: Fetching POIs [${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)} to ${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}]',
        tag: 'COMMUNITY',
      );

      final newPOIs = await _firebaseService.getPOIsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      DebugMessageHelper.addMessage(ref, 'API: Got ${newPOIs.length} POIs', tag: 'COMMUNITY');

      AppLogger.success('Loaded POIs in background', tag: 'COMMUNITY', data: {'count': newPOIs.length});

      // Filter existing POIs to keep only those within the new bounds
      final currentPOIs = state.value ?? [];
      final filteredCurrentPOIs = currentPOIs.where((poi) {
        return poi.latitude >= bounds.south &&
               poi.latitude <= bounds.north &&
               poi.longitude >= bounds.west &&
               poi.longitude <= bounds.east;
      }).toList();

      AppLogger.success('Filtered ${currentPOIs.length} existing POIs to ${filteredCurrentPOIs.length} within bounds');

      // Merge filtered existing data with new POIs to avoid duplicates
      final mergedPOIs = _mergePOIs(filteredCurrentPOIs, newPOIs);

      AppLogger.success('Merged ${filteredCurrentPOIs.length} existing + ${newPOIs.length} new = ${mergedPOIs.length} total POIs');
      state = AsyncValue.data(mergedPOIs);
      _lastLoadedBounds = bounds;
    } catch (e) {
      AppLogger.error('Error loading POIs in background', error: e);
      // Don't change state on error - keep existing data
    }
  }

  /// Merge POIs to avoid duplicates
  List<CyclingPOI> _mergePOIs(List<CyclingPOI> existing, List<CyclingPOI> newPOIs) {
    final Map<String, CyclingPOI> mergedMap = {};

    // Add existing POIs
    for (final poi in existing) {
      if (poi.id != null) {
        mergedMap[poi.id!] = poi;
      }
    }

    // Add new POIs (will overwrite duplicates)
    for (final poi in newPOIs) {
      if (poi.id != null) {
        mergedMap[poi.id!] = poi;
      }
    }

    return mergedMap.values.toList();
  }

  /// Force reload POIs using the last known bounds
  Future<void> forceReload() async {
    if (_lastLoadedBounds != null) {
      AppLogger.firebase('Force reloading POIs with last known bounds', data: {
        'bounds': _lastLoadedBounds.toString(),
      });
      await loadPOIsWithBounds(_lastLoadedBounds!);
    } else {
      AppLogger.firebase('Force reload called but no previous bounds available');
      state = const AsyncValue.data([]);
    }
  }
}

/// Provider for bounds-based community warnings notifier
final communityWarningsBoundsNotifierProvider = NotifierProvider<CommunityWarningsBoundsNotifier, AsyncValue<List<CommunityWarning>>>(CommunityWarningsBoundsNotifier.new);

/// Provider for bounds-based cycling POIs notifier
final cyclingPOIsBoundsNotifierProvider = NotifierProvider<CyclingPOIsBoundsNotifier, AsyncValue<List<CyclingPOI>>>(CyclingPOIsBoundsNotifier.new);

/// Global refresh trigger for map data
class MapDataRefreshTrigger extends Notifier<int> {
  @override
  int build() => 0;

  void triggerRefresh() {
    state = state + 1;
    AppLogger.firebase('Map data refresh triggered', data: {'counter': state});
  }
}

/// Provider for map data refresh trigger
final mapDataRefreshTriggerProvider = NotifierProvider<MapDataRefreshTrigger, int>(MapDataRefreshTrigger.new);

