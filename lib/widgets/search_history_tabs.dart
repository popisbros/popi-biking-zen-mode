import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/user_profile.dart';

/// Search history tabs widget showing recent searches, destinations, and favorites
/// Displayed below search input when search bar is open but no query/results
class SearchHistoryTabs extends ConsumerStatefulWidget {
  final Function(double lat, double lon, String name) onLocationTap;
  final Function(String query) onSearchTap;

  const SearchHistoryTabs({
    super.key,
    required this.onLocationTap,
    required this.onSearchTap,
  });

  @override
  ConsumerState<SearchHistoryTabs> createState() => _SearchHistoryTabsState();
}

class _SearchHistoryTabsState extends ConsumerState<SearchHistoryTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider).value;

    // Only show if user is logged in
    if (authUser == null) {
      return const SizedBox.shrink();
    }

    final userProfile = ref.watch(userProfileProvider);

    return userProfile.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();

        return Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tab bar
              TabBar(
                controller: _tabController,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.blue,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Recent Searches'),
                  Tab(text: 'Destinations'),
                  Tab(text: 'Favorites'),
                ],
              ),

              // Tab views
              SizedBox(
                height: 300, // Fixed height for scrollable lists
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRecentSearches(profile.recentSearches),
                    _buildRecentDestinations(profile.recentDestinations),
                    _buildFavorites(profile.favoriteLocations),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentSearches(List<String> searches) {
    if (searches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No recent searches',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: searches.length,
      itemBuilder: (context, index) {
        final query = searches[index];
        return InkWell(
          onTap: () {
            widget.onSearchTap(query);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.history,
                  color: Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    query,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentDestinations(List<SavedLocation> destinations) {
    if (destinations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No recent destinations',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: destinations.length,
      itemBuilder: (context, index) {
        final location = destinations[index];
        return InkWell(
          onTap: () {
            widget.onLocationTap(location.latitude, location.longitude, location.name);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavorites(List<SavedLocation> favorites) {
    if (favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No favorites yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final location = favorites[index];
        return InkWell(
          onTap: () {
            widget.onLocationTap(location.latitude, location.longitude, location.name);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.star,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
