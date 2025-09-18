import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/location_data.dart';
import '../models/cycling_poi.dart';
import '../models/community_warning.dart';

/// Service for offline storage and caching
class OfflineStorageService {
  static final OfflineStorageService _instance = OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  static const String _locationHistoryKey = 'location_history';
  static const String _cachedPOIsKey = 'cached_pois';
  static const String _cachedWarningsKey = 'cached_warnings';
  static const String _offlineMapsKey = 'offline_maps';
  static const String _userPreferencesKey = 'user_preferences';

  /// Save location history for offline access
  Future<void> saveLocationHistory(List<LocationData> locations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationJsonList = locations.map((location) => location.toMap()).toList();
      await prefs.setString(_locationHistoryKey, jsonEncode(locationJsonList));
      print('OfflineStorageService.saveLocationHistory: Saved ${locations.length} locations');
    } catch (e) {
      print('OfflineStorageService.saveLocationHistory: Error saving locations: $e');
    }
  }

  /// Get cached location history
  Future<List<LocationData>> getLocationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationJsonString = prefs.getString(_locationHistoryKey);
      if (locationJsonString != null) {
        final List<dynamic> locationJsonList = jsonDecode(locationJsonString);
        return locationJsonList.map((json) => LocationData.fromMap(json)).toList();
      }
      return [];
    } catch (e) {
      print('OfflineStorageService.getLocationHistory: Error loading locations: $e');
      return [];
    }
  }

  /// Add a single location to history
  Future<void> addLocationToHistory(LocationData location) async {
    try {
      final existingLocations = await getLocationHistory();
      existingLocations.add(location);
      
      // Keep only last 1000 locations to prevent storage bloat
      if (existingLocations.length > 1000) {
        existingLocations.removeRange(0, existingLocations.length - 1000);
      }
      
      await saveLocationHistory(existingLocations);
    } catch (e) {
      print('OfflineStorageService.addLocationToHistory: Error adding location: $e');
    }
  }

  /// Cache cycling POIs for offline access
  Future<void> cachePOIs(List<CyclingPOI> pois) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final poiJsonList = pois.map((poi) => poi.toMap()).toList();
      await prefs.setString(_cachedPOIsKey, jsonEncode(poiJsonList));
      print('OfflineStorageService.cachePOIs: Cached ${pois.length} POIs');
    } catch (e) {
      print('OfflineStorageService.cachePOIs: Error caching POIs: $e');
    }
  }

  /// Get cached cycling POIs
  Future<List<CyclingPOI>> getCachedPOIs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final poiJsonString = prefs.getString(_cachedPOIsKey);
      if (poiJsonString != null) {
        final List<dynamic> poiJsonList = jsonDecode(poiJsonString);
        return poiJsonList.map((json) => CyclingPOI.fromMap(json)).toList();
      }
      return [];
    } catch (e) {
      print('OfflineStorageService.getCachedPOIs: Error loading POIs: $e');
      return [];
    }
  }

  /// Cache community warnings for offline access
  Future<void> cacheWarnings(List<CommunityWarning> warnings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final warningJsonList = warnings.map((warning) => warning.toMap()).toList();
      await prefs.setString(_cachedWarningsKey, jsonEncode(warningJsonList));
      print('OfflineStorageService.cacheWarnings: Cached ${warnings.length} warnings');
    } catch (e) {
      print('OfflineStorageService.cacheWarnings: Error caching warnings: $e');
    }
  }

  /// Get cached community warnings
  Future<List<CommunityWarning>> getCachedWarnings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final warningJsonString = prefs.getString(_cachedWarningsKey);
      if (warningJsonString != null) {
        final List<dynamic> warningJsonList = jsonDecode(warningJsonString);
        return warningJsonList.map((json) => CommunityWarning.fromMap(json)).toList();
      }
      return [];
    } catch (e) {
      print('OfflineStorageService.getCachedWarnings: Error loading warnings: $e');
      return [];
    }
  }

  /// Save user preferences
  Future<void> saveUserPreferences(Map<String, dynamic> preferences) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPreferencesKey, jsonEncode(preferences));
      print('OfflineStorageService.saveUserPreferences: Saved preferences');
    } catch (e) {
      print('OfflineStorageService.saveUserPreferences: Error saving preferences: $e');
    }
  }

  /// Get user preferences
  Future<Map<String, dynamic>> getUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferencesJsonString = prefs.getString(_userPreferencesKey);
      if (preferencesJsonString != null) {
        return Map<String, dynamic>.from(jsonDecode(preferencesJsonString));
      }
      return _getDefaultPreferences();
    } catch (e) {
      print('OfflineStorageService.getUserPreferences: Error loading preferences: $e');
      return _getDefaultPreferences();
    }
  }

  /// Get default user preferences
  Map<String, dynamic> _getDefaultPreferences() {
    return {
      'notifications': true,
      'cyclingStyle': 'balanced',
      'showWarnings': true,
      'showPOIs': true,
      'offlineMode': false,
      'autoCacheMaps': true,
      'locationTracking': true,
      'hazardAlerts': true,
      'routeOptimization': true,
    };
  }

  /// Cache map tiles for offline use
  Future<void> cacheMapTiles(String region, List<String> tileUrls) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final mapCacheDir = Directory('${directory.path}/map_cache/$region');
      if (!await mapCacheDir.exists()) {
        await mapCacheDir.create(recursive: true);
      }

      // Store tile URLs for the region
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${_offlineMapsKey}_$region';
      await prefs.setString(cacheKey, jsonEncode(tileUrls));
      
      print('OfflineStorageService.cacheMapTiles: Cached ${tileUrls.length} tiles for region $region');
    } catch (e) {
      print('OfflineStorageService.cacheMapTiles: Error caching map tiles: $e');
    }
  }

  /// Get cached map tiles for a region
  Future<List<String>> getCachedMapTiles(String region) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${_offlineMapsKey}_$region';
      final tileUrlsJsonString = prefs.getString(cacheKey);
      if (tileUrlsJsonString != null) {
        final List<dynamic> tileUrls = jsonDecode(tileUrlsJsonString);
        return tileUrls.cast<String>();
      }
      return [];
    } catch (e) {
      print('OfflineStorageService.getCachedMapTiles: Error loading cached tiles: $e');
      return [];
    }
  }

  /// Clear all cached data
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_locationHistoryKey);
      await prefs.remove(_cachedPOIsKey);
      await prefs.remove(_cachedWarningsKey);
      await prefs.remove(_userPreferencesKey);
      
      // Clear map cache directory
      final directory = await getApplicationDocumentsDirectory();
      final mapCacheDir = Directory('${directory.path}/map_cache');
      if (await mapCacheDir.exists()) {
        await mapCacheDir.delete(recursive: true);
      }
      
      print('OfflineStorageService.clearAllCache: Cleared all cached data');
    } catch (e) {
      print('OfflineStorageService.clearAllCache: Error clearing cache: $e');
    }
  }

  /// Get cache size information
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final locationHistory = await getLocationHistory();
      final cachedPOIs = await getCachedPOIs();
      final cachedWarnings = await getCachedWarnings();
      
      // Calculate directory size
      final directory = await getApplicationDocumentsDirectory();
      final mapCacheDir = Directory('${directory.path}/map_cache');
      int mapCacheSize = 0;
      if (await mapCacheDir.exists()) {
        await for (final entity in mapCacheDir.list(recursive: true)) {
          if (entity is File) {
            mapCacheSize += await entity.length();
          }
        }
      }
      
      return {
        'locationHistoryCount': locationHistory.length,
        'cachedPOIsCount': cachedPOIs.length,
        'cachedWarningsCount': cachedWarnings.length,
        'mapCacheSizeBytes': mapCacheSize,
        'mapCacheSizeMB': (mapCacheSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      print('OfflineStorageService.getCacheInfo: Error getting cache info: $e');
      return {};
    }
  }

  /// Check if device is offline
  Future<bool> isOffline() async {
    try {
      // This is a simple check - in production you'd use connectivity_plus package
      // For now, we'll assume online unless explicitly set to offline mode
      final preferences = await getUserPreferences();
      return preferences['offlineMode'] ?? false;
    } catch (e) {
      print('OfflineStorageService.isOffline: Error checking offline status: $e');
      return false;
    }
  }

  /// Set offline mode
  Future<void> setOfflineMode(bool isOffline) async {
    try {
      final preferences = await getUserPreferences();
      preferences['offlineMode'] = isOffline;
      await saveUserPreferences(preferences);
      print('OfflineStorageService.setOfflineMode: Set offline mode to $isOffline');
    } catch (e) {
      print('OfflineStorageService.setOfflineMode: Error setting offline mode: $e');
    }
  }
}
