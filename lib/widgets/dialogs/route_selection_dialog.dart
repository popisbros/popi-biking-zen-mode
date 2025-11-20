import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/routing_service.dart';
import '../../providers/auth_provider.dart';
import '../../models/multi_profile_route_result.dart';
import '../../constants/app_colors.dart';
import '../common_dialog.dart';

/// Route selection dialog widget
///
/// Displays available routes in a horizontal swipeable carousel
/// Supports both legacy List<RouteResult> and new MultiProfileRouteResult
class RouteSelectionDialog extends ConsumerStatefulWidget {
  final List<RouteResult>? routes;
  final MultiProfileRouteResult? multiProfileRoutes;
  final Function(RouteResult) onRouteSelected;
  final VoidCallback onCancel;

  const RouteSelectionDialog({
    super.key,
    this.routes,
    this.multiProfileRoutes,
    required this.onRouteSelected,
    required this.onCancel,
  }) : assert(routes != null || multiProfileRoutes != null, 'Either routes or multiProfileRoutes must be provided');

  @override
  ConsumerState<RouteSelectionDialog> createState() => _RouteSelectionDialogState();

  /// Show route selection dialog with legacy routes list
  ///
  /// Example:
  /// ```dart
  /// RouteSelectionDialog.show(
  ///   context: context,
  ///   routes: routes,
  ///   onRouteSelected: (route) {
  ///     // Handle route selection
  ///   },
  ///   onCancel: () {
  ///     // Handle cancel
  ///   },
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    required List<RouteResult> routes,
    required Function(RouteResult) onRouteSelected,
    required VoidCallback onCancel,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => RouteSelectionDialog(
        routes: routes,
        onRouteSelected: onRouteSelected,
        onCancel: onCancel,
      ),
    );
  }

  /// Show route selection dialog with multi-profile routes
  ///
  /// Example:
  /// ```dart
  /// RouteSelectionDialog.showMultiProfile(
  ///   context: context,
  ///   multiProfileRoutes: multiProfileResult,
  ///   onRouteSelected: (route) {
  ///     // Handle route selection
  ///   },
  ///   onCancel: () {
  ///     // Handle cancel
  ///   },
  /// );
  /// ```
  static Future<void> showMultiProfile({
    required BuildContext context,
    required MultiProfileRouteResult multiProfileRoutes,
    required Function(RouteResult) onRouteSelected,
    required VoidCallback onCancel,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => RouteSelectionDialog(
        multiProfileRoutes: multiProfileRoutes,
        onRouteSelected: onRouteSelected,
        onCancel: onCancel,
      ),
    );
  }
}

class _RouteSelectionDialogState extends ConsumerState<RouteSelectionDialog> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();

    // Get user's preferred profile to set initial page
    final userProfile = ref.read(userProfileProvider).value;
    final lastUsedProfile = userProfile?.lastUsedRouteProfile;

    // Determine initial page based on last used profile
    int initialPage = 1; // Default to bike (middle)
    if (widget.multiProfileRoutes != null) {
      if (lastUsedProfile == 'car' && widget.multiProfileRoutes!.carRoute != null) {
        initialPage = 0;
      } else if (lastUsedProfile == 'foot' && widget.multiProfileRoutes!.footRoute != null) {
        initialPage = 2;
      }
    }

    _pageController = PageController(initialPage: initialPage);
    _currentPage = initialPage;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Get list of available routes
  List<RouteResult> get _availableRoutes {
    if (widget.multiProfileRoutes != null) {
      return widget.multiProfileRoutes!.availableRoutes;
    }
    return widget.routes ?? [];
  }

  /// Get profile for route at index
  TransportProfile? _getProfileForIndex(int index) {
    if (widget.multiProfileRoutes == null) return null;

    final routes = _availableRoutes;
    if (index >= routes.length) return null;

    final route = routes[index];
    if (route == widget.multiProfileRoutes!.carRoute) return TransportProfile.car;
    if (route == widget.multiProfileRoutes!.bikeRoute) return TransportProfile.bike;
    if (route == widget.multiProfileRoutes!.footRoute) return TransportProfile.foot;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final routes = _availableRoutes;

    if (routes.isEmpty) {
      return _buildEmptyState();
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 450,
            maxHeight: 500,
          ),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  widget.multiProfileRoutes != null
                      ? 'Choose Your Transport Profile'
                      : 'Choose Your Route',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.urbanBlue,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Horizontal carousel
              SizedBox(
                height: 280,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    return _buildRouteCard(routes[index], index);
                  },
                ),
              ),

              // Page indicators
              if (routes.length > 1) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    routes.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentPage == index
                            ? AppColors.urbanBlue
                            : AppColors.lightGrey,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onCancel();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('CANCEL', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          final selectedRoute = routes[_currentPage];
                          final profile = _getProfileForIndex(_currentPage);

                          // Save last used profile if in multi-profile mode
                          if (profile != null) {
                            final profileName = profile.name; // 'car', 'bike', or 'foot'
                            await ref.read(authNotifierProvider.notifier).updateProfile(
                              lastUsedRouteProfile: profileName,
                            );
                          }

                          if (mounted) {
                            Navigator.pop(context);
                            widget.onRouteSelected(selectedRoute);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.urbanBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'START NAVIGATION',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteCard(RouteResult route, int index) {
    final profile = _getProfileForIndex(index);

    // Determine card properties
    final IconData icon;
    final Color color;
    final String label;
    final String description;

    if (profile != null) {
      // Multi-profile mode
      switch (profile) {
        case TransportProfile.car:
          icon = Icons.directions_car;
          color = Colors.red[700]!;
          label = 'Car Route';
          description = 'Fastest route using car roads';
          break;
        case TransportProfile.bike:
          icon = Icons.directions_bike;
          color = Colors.green[700]!;
          label = 'Bike Route';
          description = 'Optimized for cycling';
          break;
        case TransportProfile.foot:
          icon = Icons.directions_walk;
          color = Colors.blue[700]!;
          label = 'Walking Route';
          description = 'Pedestrian-friendly path';
          break;
      }
    } else {
      // Legacy mode (fastest/safest/shortest)
      switch (route.type) {
        case RouteType.fastest:
          icon = Icons.directions_car;
          color = Colors.red[700]!;
          label = 'Fastest Route';
          description = 'Optimized for speed';
          break;
        case RouteType.safest:
          icon = Icons.shield;
          color = Colors.green[700]!;
          label = 'Safest Route';
          description = 'Prioritizes cycle lanes & quiet roads';
          break;
        case RouteType.shortest:
          icon = Icons.directions_walk;
          color = Colors.blue[700]!;
          label = 'Shortest Route';
          description = 'Minimal distance';
          break;
      }
    }

    // Calculate hazards count if available
    final hazardsCount = route.routeHazards?.length ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Icon(icon, size: 64, color: color),
          const SizedBox(height: 16),

          // Label
          Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Stats
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightGrey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat(Icons.straighten, '${route.distanceKm} km', 'Distance'),
                    _buildStat(Icons.access_time, '${route.durationMin} min', 'Duration'),
                  ],
                ),
                if (hazardsCount > 0) ...[
                  const SizedBox(height: 12),
                  _buildStat(
                    Icons.warning_amber_rounded,
                    '$hazardsCount hazard${hazardsCount > 1 ? 's' : ''}',
                    'On route',
                    color: Colors.orange[700]!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label, {Color? color}) {
    final statColor = color ?? AppColors.urbanBlue;

    return Column(
      children: [
        Icon(icon, size: 20, color: statColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: statColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 64, color: AppColors.lightGrey),
              const SizedBox(height: 16),
              const Text(
                'No routes available',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unable to calculate routes for this destination.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCancel();
                },
                child: const Text('CLOSE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
