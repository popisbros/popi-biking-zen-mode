import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/routing_service.dart';
import '../../providers/auth_provider.dart';

/// Route selection dialog widget
///
/// Displays available routes (fastest/safest/shortest) for user to choose
/// Consolidates duplicate dialogs from map_screen and mapbox_map_screen_simple
class RouteSelectionDialog extends ConsumerWidget {
  final List<RouteResult> routes;
  final Function(RouteResult) onRouteSelected;
  final VoidCallback onCancel;
  final bool transparentBarrier;

  const RouteSelectionDialog({
    super.key,
    required this.routes,
    required this.onRouteSelected,
    required this.onCancel,
    this.transparentBarrier = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get user's preferred route profile
    final userProfile = ref.watch(userProfileProvider).value;
    final preferredProfile = userProfile?.defaultRouteProfile ?? 'bike';

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.05, // 5% from bottom
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 400, // Maximum width
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6), // 60% opacity
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Text(
                      'Choose Your Route',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),

                  // Routes list
                  ...routes.map((route) => _buildRouteOption(context, route, preferredProfile)),

                  // Cancel button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onCancel();
                        },
                        child: const Text('CANCEL', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteOption(BuildContext context, RouteResult route, String preferredProfile) {
    // Determine icon, color, label based on route type
    final IconData icon;
    final Color color;
    final String label;
    final String description;
    final String profileType;

    switch (route.type) {
      case RouteType.fastest:
        icon = Icons.directions_car;
        color = Colors.red;
        label = 'Fastest Route (car)';
        description = 'Optimized for speed';
        profileType = 'car';
        break;
      case RouteType.safest:
        icon = Icons.shield;
        color = Colors.green;
        label = 'Safest Route (bike)';
        description = 'Prioritizes cycle lanes & quiet roads';
        profileType = 'bike';
        break;
      case RouteType.shortest:
        icon = Icons.directions_walk;
        color = Colors.blue;
        label = 'Walking Route (foot)';
        description = 'Walking/pedestrian route';
        profileType = 'foot';
        break;
    }

    // Check if this is the user's preferred route
    final isPreferred = profileType == preferredProfile;

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onRouteSelected(route);
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        leading: Icon(icon, color: color, size: 28),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: isPreferred ? TextDecoration.underline : null,
            decorationColor: color,
            decorationThickness: 2,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              '${route.distanceKm} km • ${route.durationMin} min',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        trailing: isPreferred
            ? Icon(Icons.star, color: Colors.amber, size: 20)
            : null,
      ),
    );
  }

  /// Show route selection dialog
  ///
  /// Convenience method to show the dialog
  ///
  /// Example:
  /// ```dart
  /// RouteSelectionDialog.show(
  ///   context: context,
  ///   routes: routes,
  ///   onRouteSelected: (route) {
  ///     ref.read(searchProvider.notifier).clearPreviewRoutes();
  ///     _displaySelectedRoute(route);
  ///   },
  ///   onCancel: () {
  ///     ref.read(searchProvider.notifier).clearPreviewRoutes();
  ///   },
  ///   transparentBarrier: true,
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    required List<RouteResult> routes,
    required Function(RouteResult) onRouteSelected,
    required VoidCallback onCancel,
    bool transparentBarrier = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: transparentBarrier ? Colors.transparent : null,
      builder: (context) => RouteSelectionDialog(
        routes: routes,
        onRouteSelected: onRouteSelected,
        onCancel: onCancel,
        transparentBarrier: transparentBarrier,
      ),
    );
  }
}
