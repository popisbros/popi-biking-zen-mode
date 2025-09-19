import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_warning.dart';
import '../models/cycling_poi.dart';
import '../services/firebase_service.dart';

/// Provider for Firebase service
final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});

/// Provider for community warnings stream
final communityWarningsProvider = StreamProvider<List<CommunityWarning>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  
  // For now, we'll get all warnings. In production, you'd filter by location
  return firebaseService.getNearbyWarnings(37.7749, -122.4194, 50.0)
      .map((snapshot) => snapshot.docs
          .map((doc) => CommunityWarning.fromMap({
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          }))
          .toList());
});

/// Provider for cycling POIs stream
final cyclingPOIsProvider = StreamProvider<List<CyclingPOI>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  
  return firebaseService.getCyclingPOIs()
      .map((snapshot) => snapshot.docs
          .map((doc) => CyclingPOI.fromMap({
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          }))
          .toList());
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
    final snapshot = await _firebaseService.getNearbyWarnings(37.7749, -122.4194, 50.0).first;
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
    try {
      state = const AsyncValue.loading();
      // TODO: Implement addPOI method in FirebaseService
      // await _firebaseService.addPOI(poi.toMap());
      
      // Reload POIs
      final pois = await _getPOIsFromFirestore();
      state = AsyncValue.data(pois);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
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
