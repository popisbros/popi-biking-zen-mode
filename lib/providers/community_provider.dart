import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/community_warning.dart';
import '../services/firebase_service.dart';
import '../services/debug_service.dart';
import '../utils/app_logger.dart';
import 'osm_poi_provider.dart'; // Import BoundingBox
import 'auth_provider.dart'; // For getting current user info

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
      _triggerMapBackgroundRefresh();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Update an existing warning
  Future<void> updateWarning(String documentId, CommunityWarning warning) async {
    try {
      state = const AsyncValue.loading();

      // Get current user info
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw Exception('User must be logged in to update warning');
      }

      // Track update interaction
      final updatedInteractions = _addUserInteraction(
        warning.userInteractions,
        user.uid,
        user.email ?? 'unknown@email.com',
        'updated',
      );

      final warningWithTracking = warning.copyWith(
        userInteractions: updatedInteractions,
      );

      await _firebaseService.updateWarning(documentId, warningWithTracking.toMap());

      // Reload warnings
      final warnings = await getWarningsFromFirestore();
      state = AsyncValue.data(warnings);

      // Trigger background refresh of all map data
      _triggerMapBackgroundRefresh();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Soft delete a warning (mark as deleted instead of physical deletion)
  Future<void> deleteWarning(String warningId) async {
    try {
      state = const AsyncValue.loading();

      // Get current user info
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw Exception('User must be logged in to delete warning');
      }

      // First, get the current warning to preserve its data
      final currentWarnings = await getWarningsFromFirestore();
      final currentWarning = currentWarnings.firstWhere(
        (warning) => warning.id == warningId,
        orElse: () => throw Exception('Warning not found'),
      );

      // Track deletion interaction
      final updatedInteractions = _addUserInteraction(
        currentWarning.userInteractions,
        user.uid,
        user.email ?? 'unknown@email.com',
        'deleted',
      );

      // Mark as deleted
      final deletedWarning = currentWarning.copyWith(
        userInteractions: updatedInteractions,
        isDeleted: true,
        deletedAt: DateTime.now(),
      );

      // Update in Firebase (soft delete, not physical delete)
      await _firebaseService.updateWarning(warningId, deletedWarning.toMap());

      // Reload warnings
      final warnings = await getWarningsFromFirestore();
      state = AsyncValue.data(warnings);

      // Trigger background refresh of all map data
      _triggerMapBackgroundRefresh();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Refresh warnings
  Future<void> refreshWarnings() async {
    await _loadWarnings();
  }

  /// Trigger background refresh of all map data
  Future<void> _triggerMapBackgroundRefresh() async {
    try {
      // Trigger a global refresh by incrementing the refresh counter
      // This will cause the map screen to reload all data
      AppLogger.firebase('Triggering global map data refresh after Hazard operation');

      final refreshNotifier = ref.read(mapDataRefreshTriggerProvider.notifier);
      refreshNotifier.triggerRefresh();

      AppLogger.success('Global map data refresh triggered');
    } catch (e) {
      AppLogger.error('Failed to trigger global map data refresh', error: e);
      // Don't throw - this is a background operation
    }
  }

  /// Helper to add user interaction and maintain last 5 interactions
  List<UserInteraction> _addUserInteraction(
    List<UserInteraction> existing,
    String userId,
    String userEmail,
    String action,
  ) {
    final newInteraction = UserInteraction(
      userId: userId,
      userEmail: userEmail,
      action: action,
      timestamp: DateTime.now(),
    );

    // Add new interaction at the beginning and keep only last 5
    final updated = [newInteraction, ...existing];
    return updated.take(5).toList();
  }
}

/// Provider for community warnings notifier
final communityWarningsNotifierProvider = NotifierProvider<CommunityWarningsNotifier, AsyncValue<List<CommunityWarning>>>(CommunityWarningsNotifier.new);

/// State notifier for bounds-based community warnings
class CommunityWarningsBoundsNotifier extends Notifier<AsyncValue<List<CommunityWarning>>> {
  late final FirebaseService _firebaseService;
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
      AppLogger.firebase('Fetching warnings in bounds', data: {
        'south': bounds.south.toStringAsFixed(2),
        'west': bounds.west.toStringAsFixed(2),
        'north': bounds.north.toStringAsFixed(2),
        'east': bounds.east.toStringAsFixed(2),
      });

      final warnings = await _firebaseService.getWarningsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      AppLogger.firebase('Got ${warnings.length} warnings', data: {'count': warnings.length});
      AppLogger.success('Loaded warnings with bounds', data: {'count': warnings.length});
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
      AppLogger.firebase('Fetching warnings in bounds', data: {
        'south': bounds.south.toStringAsFixed(2),
        'west': bounds.west.toStringAsFixed(2),
        'north': bounds.north.toStringAsFixed(2),
        'east': bounds.east.toStringAsFixed(2),
      });

      final newWarnings = await _firebaseService.getWarningsInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      AppLogger.firebase('Got ${newWarnings.length} warnings', data: {'count': newWarnings.length});

      AppLogger.success('Loaded warnings in background', data: {'count': newWarnings.length});

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

/// Provider for bounds-based community warnings notifier
final communityWarningsBoundsNotifierProvider = NotifierProvider<CommunityWarningsBoundsNotifier, AsyncValue<List<CommunityWarning>>>(CommunityWarningsBoundsNotifier.new);

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
