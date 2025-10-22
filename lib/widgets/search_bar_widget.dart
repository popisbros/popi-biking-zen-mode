import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/search_result.dart';
import '../providers/search_provider.dart';
import '../providers/auth_provider.dart';
import 'search_result_tile.dart';
import 'search_history_tabs.dart';

/// Animated search bar widget that slides down from top
class SearchBarWidget extends ConsumerStatefulWidget {
  final LatLng mapCenter;
  final Function(double lat, double lon, String label) onResultTap;

  const SearchBarWidget({
    super.key,
    required this.mapCenter,
    required this.onResultTap,
  });

  @override
  ConsumerState<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends ConsumerState<SearchBarWidget>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    // Trigger animation when visibility changes
    if (searchState.isVisible && !_animationController.isCompleted) {
      _animationController.forward();
      // Auto-focus input when opening
      Future.microtask(() => _focusNode.requestFocus());
    } else if (!searchState.isVisible && _animationController.isCompleted) {
      _animationController.reverse();
    }

    // Sync controller with state
    if (_controller.text != searchState.query) {
      _controller.text = searchState.query;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }

    // Keep focus on TextField after results appear (so Enter key works)
    if (searchState.isVisible && searchState.results.hasValue) {
      Future.microtask(() {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }

    if (!searchState.isVisible) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.3),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Safe area padding for iOS Dynamic Island / notch
              SizedBox(height: MediaQuery.of(context).padding.top),

              // Search input row
              _buildSearchInput(context, searchState),

              // Results list
              _buildResultsList(context, searchState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput(BuildContext context, SearchState searchState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Input field
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Type your address, location or GPS coordinates...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                suffixIcon: searchState.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          ref.read(searchProvider.notifier).clearSearch();
                        },
                      )
                    : null,
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (value) {
                ref.read(searchProvider.notifier).updateQuery(
                      value,
                      widget.mapCenter,
                    );
              },
              onSubmitted: (value) {
                // If results are already showing, select first result (or expand option)
                searchState.results.whenData((results) {
                  if (results.isNotEmpty) {
                    final firstResult = results.first;

                    // If first result is "expand search", trigger expand
                    if (firstResult.type == SearchResultType.expandSearch) {
                      ref.read(searchProvider.notifier).expandSearch(widget.mapCenter);
                    } else {
                      // Save search to history (if user is logged in)
                      final authUser = ref.read(authStateProvider).value;
                      if (authUser != null && searchState.query.trim().isNotEmpty) {
                        ref.read(authNotifierProvider.notifier).addRecentSearch(searchState.query.trim());
                      }

                      // Select first result
                      widget.onResultTap(firstResult.latitude, firstResult.longitude, firstResult.title);
                      ref.read(searchProvider.notifier).closeSearch();
                    }
                    return;
                  }
                });

                // If no results or not in data state, perform search
                if (!searchState.results.hasValue || searchState.results.value!.isEmpty) {
                  ref.read(searchProvider.notifier).performSearch(widget.mapCenter);
                }
              },
            ),
          ),

          const SizedBox(width: 12),

          // Search button
          ElevatedButton(
            onPressed: searchState.query.trim().isEmpty
                ? null
                : () {
                    ref.read(searchProvider.notifier).performSearch(widget.mapCenter);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFEB3B), // Yellow
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search, size: 18),
                SizedBox(width: 6),
                Text('Search', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              ref.read(searchProvider.notifier).closeSearch();
            },
            tooltip: 'Close search',
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(BuildContext context, SearchState searchState) {
    return searchState.results.when(
      data: (results) {
        if (results.isEmpty && searchState.query.trim().isNotEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No results found',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          );
        }

        // Show history tabs when no results (query is empty or not searched yet)
        if (results.isEmpty) {
          return SearchHistoryTabs(
            onLocationTap: (lat, lon, name) {
              // Navigate to location
              widget.onResultTap(lat, lon, name);
              // Close search
              ref.read(searchProvider.notifier).closeSearch();
            },
            onSearchTap: (query) {
              // Set query and perform search
              ref.read(searchProvider.notifier).updateQuery(query, widget.mapCenter);
              ref.read(searchProvider.notifier).performSearch(widget.mapCenter);
            },
          );
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 400, // Max height for results
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero, // Remove default ListView padding
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];

                // Special handling for "expand search" trigger
                if (result.type == SearchResultType.expandSearch) {
                  return _buildExpandSearchTile(context);
                }

                return SearchResultTile(
                  result: result,
                  onTap: () {
                    // Save search to history (if user is logged in)
                    final authUser = ref.read(authStateProvider).value;
                    if (authUser != null && searchState.query.trim().isNotEmpty) {
                      ref.read(authNotifierProvider.notifier).addRecentSearch(searchState.query.trim());
                    }

                    // Navigate map to this location
                    widget.onResultTap(result.latitude, result.longitude, result.title);

                    // Close search bar
                    ref.read(searchProvider.notifier).closeSearch();
                  },
                );
              },
            ),
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Search failed. Please try again.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandSearchTile(BuildContext context) {
    return InkWell(
      onTap: () {
        ref.read(searchProvider.notifier).expandSearch(widget.mapCenter);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border(
            top: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.expand_circle_down_outlined,
              color: Colors.blue[700],
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Not finding your location? Extend the search',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blue[700],
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.blue[700],
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
