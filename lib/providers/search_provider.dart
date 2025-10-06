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

    state = state.copyWith(query: query);

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

    state = state.copyWith(results: const AsyncValue.loading());

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

      // If not coordinates, search via geocoding APIs
      final results = await _geocodingService.searchAddress(query, mapCenter);

      AppLogger.success('Search completed', tag: 'SEARCH', data: {
        'results': results.length,
      });

      state = state.copyWith(results: AsyncValue.data(results));
    } catch (e, stackTrace) {
      AppLogger.error('Search failed', tag: 'SEARCH', error: e);
      state = state.copyWith(
        results: AsyncValue.error(e, stackTrace),
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
}

/// Search state class
class SearchState {
  final bool isVisible;
  final String query;
  final AsyncValue<List<SearchResult>> results;

  const SearchState({
    required this.isVisible,
    required this.query,
    required this.results,
  });

  factory SearchState.initial() {
    return const SearchState(
      isVisible: false,
      query: '',
      results: AsyncValue.data([]),
    );
  }

  SearchState copyWith({
    bool? isVisible,
    String? query,
    AsyncValue<List<SearchResult>>? results,
  }) {
    return SearchState(
      isVisible: isVisible ?? this.isVisible,
      query: query ?? this.query,
      results: results ?? this.results,
    );
  }
}

/// Provider for search state
final searchProvider = NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);
