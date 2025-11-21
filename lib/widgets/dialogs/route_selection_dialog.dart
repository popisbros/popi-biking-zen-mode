import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/routing_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/search_provider.dart';
import '../../models/multi_profile_route_result.dart';
import '../../constants/app_colors.dart';
import '../../utils/app_logger.dart';
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

    // Determine initial page based on default profile
    int initialPage = 0; // Default to first available route

    if (widget.multiProfileRoutes != null) {
      // Get user's preferred profile to set initial page
      final userProfileAsync = ref.read(userProfileProvider);

      AppLogger.debug('Route dialog init - hasValue: ${userProfileAsync.hasValue}, hasError: ${userProfileAsync.hasError}, isLoading: ${userProfileAsync.isLoading}', tag: 'ROUTE_DIALOG');

      // Try to get the profile value - may be null if still loading
      final defaultProfile = userProfileAsync.whenData((profile) => profile?.defaultRouteProfile).value;

      AppLogger.debug('Route dialog init - defaultProfile from whenData: $defaultProfile', tag: 'ROUTE_DIALOG');

      // Find the index of the preferred route in availableRoutes
      // availableRoutes returns routes in order: [car, bike, foot] (only those available)
      if (defaultProfile != null) {
        final routes = _availableRoutes;
        AppLogger.debug('Available routes count: ${routes.length}', tag: 'ROUTE_DIALOG');
        AppLogger.debug('Car route available: ${widget.multiProfileRoutes!.carRoute != null}', tag: 'ROUTE_DIALOG');
        AppLogger.debug('Bike route available: ${widget.multiProfileRoutes!.bikeRoute != null}', tag: 'ROUTE_DIALOG');
        AppLogger.debug('Foot route available: ${widget.multiProfileRoutes!.footRoute != null}', tag: 'ROUTE_DIALOG');

        for (int i = 0; i < routes.length; i++) {
          final route = routes[i];
          final isCarMatch = route == widget.multiProfileRoutes!.carRoute;
          final isBikeMatch = route == widget.multiProfileRoutes!.bikeRoute;
          final isFootMatch = route == widget.multiProfileRoutes!.footRoute;

          AppLogger.debug('Route $i - isCarMatch: $isCarMatch, isBikeMatch: $isBikeMatch, isFootMatch: $isFootMatch', tag: 'ROUTE_DIALOG');

          if (defaultProfile == 'car' && isCarMatch) {
            initialPage = i;
            AppLogger.debug('Setting initial page to $i (car)', tag: 'ROUTE_DIALOG');
            break;
          } else if (defaultProfile == 'bike' && isBikeMatch) {
            initialPage = i;
            AppLogger.debug('Setting initial page to $i (bike)', tag: 'ROUTE_DIALOG');
            break;
          } else if (defaultProfile == 'foot' && isFootMatch) {
            initialPage = i;
            AppLogger.debug('Setting initial page to $i (foot)', tag: 'ROUTE_DIALOG');
            break;
          }
        }
        AppLogger.debug('Final initialPage: $initialPage', tag: 'ROUTE_DIALOG');
      } else {
        AppLogger.warning('defaultProfile is null in route dialog init - profile may still be loading', tag: 'ROUTE_DIALOG');
      }
    }

    _pageController = PageController(initialPage: initialPage);
    _currentPage = initialPage;

    // Set initial route order so the preferred route is on top
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(searchProvider.notifier).reorderPreviewRoutes(initialPage);
      }
    });
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

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 450,
          ),
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7), // More transparent to see routes
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
              const SizedBox(height: 12), // Reduced from 16

              // Horizontal carousel
              SizedBox(
                height: 140,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                    // Reorder preview routes so the selected route is drawn on top
                    ref.read(searchProvider.notifier).reorderPreviewRoutes(index);
                  },
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    return _buildRouteCard(routes[index], index);
                  },
                ),
              ),

              // Page indicators
              if (routes.length > 1) ...[
                const SizedBox(height: 12), // Reduced from 16
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

              const SizedBox(height: 16), // Reduced from 20

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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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

                          // Update default profile if in multi-profile mode
                          if (profile != null) {
                            final profileName = profile.name; // 'car', 'bike', or 'foot'
                            await ref.read(authNotifierProvider.notifier).updateProfile(
                              defaultRouteProfile: profileName,
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85), // Semi-transparent to see routes behind
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
      child: Row(
        children: [
          // Icon on the left (smaller)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 32, color: color),
          ),
          const SizedBox(width: 12),

          // Content on the right
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Label
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),

                // Description
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),

                // Stats: Distance and Duration in compact row
                Row(
                  children: [
                    Icon(Icons.straighten, size: 14, color: AppColors.urbanBlue),
                    const SizedBox(width: 4),
                    Text(
                      '${route.distanceKm} km',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.access_time, size: 14, color: AppColors.urbanBlue),
                    const SizedBox(width: 4),
                    Text(
                      '${route.durationMin} min',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                  ],
                ),

                // Hazards on separate line (only if hazards exist)
                if (hazardsCount > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Hazards: $hazardsCount on this route',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
