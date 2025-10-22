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
        child: Text(
          'No recent searches',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: searches.length,
      itemBuilder: (context, index) {
        final query = searches[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.history, size: 20, color: Colors.grey),
          title: Text(
            query,
            style: const TextStyle(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            widget.onSearchTap(query);
          },
        );
      },
    );
  }

  Widget _buildRecentDestinations(List<SavedLocation> destinations) {
    if (destinations.isEmpty) {
      return Center(
        child: Text(
          'No recent destinations',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: destinations.length,
      itemBuilder: (context, index) {
        final location = destinations[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.location_on, size: 20, color: Colors.orange),
          title: Text(
            location.name,
            style: const TextStyle(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          onTap: () {
            widget.onLocationTap(location.latitude, location.longitude, location.name);
          },
        );
      },
    );
  }

  Widget _buildFavorites(List<SavedLocation> favorites) {
    if (favorites.isEmpty) {
      return Center(
        child: Text(
          'No favorites yet',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final location = favorites[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.star, size: 20, color: Colors.amber),
          title: Text(
            location.name,
            style: const TextStyle(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          onTap: () {
            widget.onLocationTap(location.latitude, location.longitude, location.name);
          },
        );
      },
    );
  }
}
