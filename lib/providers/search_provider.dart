import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/search_result.dart';
import '../services/geocoding_service.dart';
import '../utils/app_logger.dart';

/// Provider for geocoding service
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return GeocodingService();
});

/// Search state notifier
class SearchNotifier extends Notifier<SearchState> {
  Timer? _debounceTimer;
  late final GeocodingService _geocodingService;

  @override
  SearchState build() {
    _geocodingService = ref.watch(geocodingServiceProvider);
    return SearchState.initial();
  }

  /// Toggle search bar visibility
  void toggleSearchBar() {
    AppLogger.debug('Toggling search bar', tag: 'SEARCH', data: {
      'currentState': state.isVisible ? 'visible' : 'hidden',
    });

    state = state.copyWith(
      isVisible: !state.isVisible,
      query: state.isVisible ? '' : state.query, // Clear query when closing
      results: state.isVisible ? const AsyncValue.data([]) : state.results,
    );
  }

  /// Update search query and trigger debounced search
  void updateQuery(String query, LatLng mapCenter) {
    AppLogger.debug('Updating search query', tag: 'SEARCH', data: {
      'query': query,
      'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
    });

    state = state.copyWith(
      query: query,
      // Reset expand flags when query changes
      hasBoundedResults: false,
      isExpandedSearch: false,
    );

    // Cancel existing timer
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      state = state.copyWith(results: const AsyncValue.data([]));
      return;
    }

    // Set up new timer for 3-second debounce
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      AppLogger.debug('Debounce timer triggered - performing search', tag: 'SEARCH');
      performSearch(mapCenter);
    });
  }

  /// Perform search immediately (called by search button or ENTER key)
  Future<void> performSearch(LatLng mapCenter) async {
    _debounceTimer?.cancel();

    final query = state.query.trim();
    if (query.isEmpty) {
      state = state.copyWith(results: const AsyncValue.data([]));
      return;
    }

    AppLogger.api('Performing search', data: {
      'query': query,
      'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
    });

    state = state.copyWith(
      results: const AsyncValue.loading(),
      hasBoundedResults: false,
      isExpandedSearch: false,
    );

    try {
      // First, try to parse as coordinates
      final coordinateResult = _geocodingService.parseCoordinates(query, mapCenter);
      if (coordinateResult != null) {
        AppLogger.success('Parsed as coordinates', tag: 'SEARCH', data: {
          'lat': coordinateResult.latitude,
          'lon': coordinateResult.longitude,
        });
        state = state.copyWith(results: AsyncValue.data([coordinateResult]));
        return;
      }

      // If not coordinates, search via geocoding APIs (bounded first)
      final results = await _geocodingService.searchAddress(query, mapCenter, ref: ref);

      AppLogger.success('Search completed', tag: 'SEARCH', data: {
        'results': results.length,
      });

      // If we have bounded results, add the "expand search" trigger
      if (results.isNotEmpty) {
        final resultsWithExpand = [...results, SearchResult.expandSearchTrigger()];
        state = state.copyWith(
          results: AsyncValue.data(resultsWithExpand),
          hasBoundedResults: true,
          isExpandedSearch: false,
        );
      } else {
        // No bounded results - automatically perform extended search
        AppLogger.api('No bounded results, performing extended search', data: {
          'query': query,
        });

        final unboundedResults = await _geocodingService.searchAddressUnbounded(query, mapCenter, ref: ref);

        AppLogger.success('Extended search completed', tag: 'SEARCH', data: {
          'results': unboundedResults.length,
        });

        state = state.copyWith(
          results: AsyncValue.data(unboundedResults),
          hasBoundedResults: false,
          isExpandedSearch: true,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Search failed', tag: 'SEARCH', error: e);
      state = state.copyWith(
        results: AsyncValue.error(e, stackTrace),
      );
    }
  }

  /// Expand search beyond viewbox (called when user clicks "Extend the search")
  Future<void> expandSearch(LatLng mapCenter) async {
    final query = state.query.trim();
    if (query.isEmpty || state.isExpandedSearch) {
      return;
    }

    AppLogger.api('Expanding search', data: {
      'query': query,
      'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
    });

    // Get current results (without the expand trigger)
    final currentResults = state.results.value ?? [];
    final resultsWithoutTrigger = currentResults
        .where((r) => r.type != SearchResultType.expandSearch)
        .toList();

    // Show loading state while keeping existing results
    state = state.copyWith(results: const AsyncValue.loading());

    try {
      // Search unbounded (gets 20 results from API)
      final unboundedResults = await _geocodingService.searchAddressUnbounded(query, mapCenter, ref: ref);

      AppLogger.success('Expanded search completed', tag: 'SEARCH', data: {
        'unboundedResults': unboundedResults.length,
      });

      // Remove duplicates by place_id and take max 10 new results
      final existingIds = resultsWithoutTrigger.map((r) => r.id).toSet();
      final newResults = unboundedResults
          .where((r) => !existingIds.contains(r.id))
          .take(10) // Max 10 extra results
          .toList();

      AppLogger.debug('Added unique results', tag: 'SEARCH', data: {
        'newResults': newResults.length,
      });

      // Combine bounded + unbounded results
      final combinedResults = [...resultsWithoutTrigger, ...newResults];

      state = state.copyWith(
        results: AsyncValue.data(combinedResults),
        isExpandedSearch: true,
      );
    } catch (e) {
      AppLogger.error('Expand search failed', tag: 'SEARCH', error: e);
      // On error, restore previous results without trigger
      state = state.copyWith(
        results: AsyncValue.data(resultsWithoutTrigger),
        isExpandedSearch: false,
      );
    }
  }

  /// Clear search and results
  void clearSearch() {
    AppLogger.debug('Clearing search', tag: 'SEARCH');
    _debounceTimer?.cancel();
    state = state.copyWith(
      query: '',
      results: const AsyncValue.data([]),
    );
  }

  /// Close search bar
  void closeSearch() {
    AppLogger.debug('Closing search bar', tag: 'SEARCH');
    _debounceTimer?.cancel();
    state = state.copyWith(
      isVisible: false,
      query: '',
      results: const AsyncValue.data([]),
    );
  }

  /// Set selected search result location
  void setSelectedLocation(double latitude, double longitude, String label) {
    AppLogger.debug('Setting selected search location', tag: 'SEARCH', data: {
      'lat': latitude,
      'lon': longitude,
      'label': label,
    });
    state = state.copyWith(
      selectedLocation: SearchResultLocation(
        latitude: latitude,
        longitude: longitude,
        label: label,
      ),
    );
  }

  /// Clear selected search result location
  void clearSelectedLocation() {
    AppLogger.debug('Clearing selected search location', tag: 'SEARCH');
    state = state.copyWith(clearSelectedLocation: true);
  }

  /// Set calculated route
  void setRoute(List<LatLng> routePoints) {
    AppLogger.debug('Setting route', tag: 'SEARCH', data: {
      'points': routePoints.length,
    });
    state = state.copyWith(routePoints: routePoints);
  }

  /// Clear calculated route
  void clearRoute() {
    AppLogger.debug('Clearing route', tag: 'SEARCH');
    state = state.copyWith(clearRoute: true);
  }

  /// Set preview routes for route selection
  void setPreviewRoutes(List<LatLng> fastestRoute, List<LatLng> safestRoute, [List<LatLng>? shortestRoute]) {
    AppLogger.debug('Setting preview routes', tag: 'SEARCH', data: {
      'fastest': fastestRoute.length,
      'safest': safestRoute.length,
      'shortest': shortestRoute?.length ?? 0,
    });
    state = state.copyWith(
      previewFastestRoute: fastestRoute,
      previewSafestRoute: safestRoute,
      previewShortestRoute: shortestRoute,
    );
  }

  /// Clear preview routes
  void clearPreviewRoutes() {
    AppLogger.debug('Clearing preview routes', tag: 'SEARCH');
    state = state.copyWith(clearPreviewRoutes: true);
  }

  /// Set the selected preview route index (for z-order rendering)
  /// This allows the map to render the selected route on top without shuffling data
  void setSelectedPreviewRouteIndex(int selectedIndex) {
    state = state.copyWith(selectedPreviewRouteIndex: selectedIndex);
    AppLogger.debug('Selected preview route index updated', tag: 'SEARCH', data: {
      'selectedIndex': selectedIndex,
    });
  }

  /// Reorder preview routes to bring selected route to top (drawn last)
  /// DEPRECATED: This method is no longer needed. Use setSelectedPreviewRouteIndex instead.
  /// Routes should maintain their original profile-based order (car, bike, foot)
  @Deprecated('Use setSelectedPreviewRouteIndex instead to avoid color mismatch')
  void reorderPreviewRoutes(int selectedIndex) {
    // Simply update the selected index instead of shuffling routes
    setSelectedPreviewRouteIndex(selectedIndex);
  }
}

/// Represents a selected search result location to display on map
class SearchResultLocation {
  final double latitude;
  final double longitude;
  final String label;

  const SearchResultLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });
}

/// Search state class
class SearchState {
  final bool isVisible;
  final String query;
  final AsyncValue<List<SearchResult>> results;
  final SearchResultLocation? selectedLocation; // Track selected search result
  final List<LatLng>? routePoints; // Track calculated route
  final List<LatLng>? previewFastestRoute; // Preview route for car (route 0)
  final List<LatLng>? previewSafestRoute; // Preview route for bike (route 1)
  final List<LatLng>? previewShortestRoute; // Preview route for foot (route 2)
  final int selectedPreviewRouteIndex; // Which preview route is selected (0=car, 1=bike, 2=foot)
  final bool hasBoundedResults; // Track if initial bounded search returned results
  final bool isExpandedSearch; // Track if we've already expanded the search

  const SearchState({
    required this.isVisible,
    required this.query,
    required this.results,
    this.selectedLocation,
    this.routePoints,
    this.previewFastestRoute,
    this.previewSafestRoute,
    this.previewShortestRoute,
    this.selectedPreviewRouteIndex = 0,
    this.hasBoundedResults = false,
    this.isExpandedSearch = false,
  });

  factory SearchState.initial() {
    return const SearchState(
      isVisible: false,
      query: '',
      results: AsyncValue.data([]),
      selectedLocation: null,
      routePoints: null,
    );
  }

  SearchState copyWith({
    bool? isVisible,
    String? query,
    AsyncValue<List<SearchResult>>? results,
    SearchResultLocation? selectedLocation,
    bool clearSelectedLocation = false,
    List<LatLng>? routePoints,
    bool clearRoute = false,
    List<LatLng>? previewFastestRoute,
    List<LatLng>? previewSafestRoute,
    List<LatLng>? previewShortestRoute,
    bool clearPreviewRoutes = false,
    int? selectedPreviewRouteIndex,
    bool? hasBoundedResults,
    bool? isExpandedSearch,
  }) {
    return SearchState(
      isVisible: isVisible ?? this.isVisible,
      query: query ?? this.query,
      results: results ?? this.results,
      selectedLocation: clearSelectedLocation ? null : (selectedLocation ?? this.selectedLocation),
      routePoints: clearRoute ? null : (routePoints ?? this.routePoints),
      previewFastestRoute: clearPreviewRoutes ? null : (previewFastestRoute ?? this.previewFastestRoute),
      previewSafestRoute: clearPreviewRoutes ? null : (previewSafestRoute ?? this.previewSafestRoute),
      previewShortestRoute: clearPreviewRoutes ? null : (previewShortestRoute ?? this.previewShortestRoute),
      selectedPreviewRouteIndex: clearPreviewRoutes ? 0 : (selectedPreviewRouteIndex ?? this.selectedPreviewRouteIndex),
      hasBoundedResults: hasBoundedResults ?? this.hasBoundedResults,
      isExpandedSearch: isExpandedSearch ?? this.isExpandedSearch,
    );
  }
}

/// Provider for search state
final searchProvider = NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);
