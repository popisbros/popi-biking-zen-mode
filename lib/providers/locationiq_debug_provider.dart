import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/locationiq_service.dart';

/// Debug data for LocationIQ search operations
class LocationIQDebugData {
  final List<LocationIQSearchRecord> searchHistory;
  final int totalSearches;
  final int successfulSearches;
  final int failedSearches;
  final DateTime? lastSearchTime;
  final String? lastSearchQuery;
  final int? lastSearchResultCount;

  LocationIQDebugData({
    this.searchHistory = const [],
    this.totalSearches = 0,
    this.successfulSearches = 0,
    this.failedSearches = 0,
    this.lastSearchTime,
    this.lastSearchQuery,
    this.lastSearchResultCount,
  });

  LocationIQDebugData copyWith({
    List<LocationIQSearchRecord>? searchHistory,
    int? totalSearches,
    int? successfulSearches,
    int? failedSearches,
    DateTime? lastSearchTime,
    String? lastSearchQuery,
    int? lastSearchResultCount,
  }) {
    return LocationIQDebugData(
      searchHistory: searchHistory ?? this.searchHistory,
      totalSearches: totalSearches ?? this.totalSearches,
      successfulSearches: successfulSearches ?? this.successfulSearches,
      failedSearches: failedSearches ?? this.failedSearches,
      lastSearchTime: lastSearchTime ?? this.lastSearchTime,
      lastSearchQuery: lastSearchQuery ?? this.lastSearchQuery,
      lastSearchResultCount: lastSearchResultCount ?? this.lastSearchResultCount,
    );
  }
}

/// Record of a LocationIQ search operation
class LocationIQSearchRecord {
  final String query;
  final DateTime timestamp;
  final bool success;
  final int resultCount;
  final String? error;
  final double? searchLat;
  final double? searchLng;
  final List<LocationIQResult>? results;

  LocationIQSearchRecord({
    required this.query,
    required this.timestamp,
    required this.success,
    required this.resultCount,
    this.error,
    this.searchLat,
    this.searchLng,
    this.results,
  });
}

/// Provider for LocationIQ debug data
class LocationIQDebugNotifier extends StateNotifier<LocationIQDebugData> {
  LocationIQDebugNotifier() : super(LocationIQDebugData());

  /// Record a search operation
  void recordSearch({
    required String query,
    required bool success,
    required int resultCount,
    String? error,
    double? searchLat,
    double? searchLng,
    List<LocationIQResult>? results,
  }) {
    final record = LocationIQSearchRecord(
      query: query,
      timestamp: DateTime.now(),
      success: success,
      resultCount: resultCount,
      error: error,
      searchLat: searchLat,
      searchLng: searchLng,
      results: results,
    );

    final newHistory = [record, ...state.searchHistory].take(50).toList(); // Keep last 50 searches

    state = state.copyWith(
      searchHistory: newHistory,
      totalSearches: state.totalSearches + 1,
      successfulSearches: state.successfulSearches + (success ? 1 : 0),
      failedSearches: state.failedSearches + (success ? 0 : 1),
      lastSearchTime: record.timestamp,
      lastSearchQuery: query,
      lastSearchResultCount: resultCount,
    );
  }

  /// Clear search history
  void clearHistory() {
    state = LocationIQDebugData();
  }

  /// Get search statistics
  Map<String, dynamic> getStatistics() {
    if (state.totalSearches == 0) {
      return {
        'totalSearches': 0,
        'successRate': 0.0,
        'averageResults': 0.0,
        'mostCommonQuery': null,
        'lastSearch': null,
      };
    }

    final successRate = state.totalSearches > 0 
        ? (state.successfulSearches / state.totalSearches) * 100 
        : 0.0;

    final averageResults = state.searchHistory.isNotEmpty
        ? state.searchHistory.map((r) => r.resultCount).reduce((a, b) => a + b) / state.searchHistory.length
        : 0.0;

    // Find most common query
    final queryCounts = <String, int>{};
    for (final record in state.searchHistory) {
      queryCounts[record.query] = (queryCounts[record.query] ?? 0) + 1;
    }
    final mostCommonQuery = queryCounts.isNotEmpty 
        ? queryCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : null;

    return {
      'totalSearches': state.totalSearches,
      'successRate': successRate,
      'averageResults': averageResults,
      'mostCommonQuery': mostCommonQuery,
      'lastSearch': state.lastSearchTime != null 
          ? '${state.lastSearchQuery} (${state.lastSearchResultCount} results)'
          : null,
    };
  }
}

/// Provider for LocationIQ debug data
final locationIQDebugProvider = StateNotifierProvider<LocationIQDebugNotifier, LocationIQDebugData>((ref) {
  return LocationIQDebugNotifier();
});
