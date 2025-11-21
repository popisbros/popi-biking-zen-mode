import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/map_provider.dart';
import '../../config/app_colors.dart';
import '../map_toggle_button.dart';
import '../profile_button.dart';

/// Top-right map controls: POI toggles, zoom, user location, profile
/// Shared between 2D and 3D map screens
class TopRightControls extends ConsumerWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenterLocation;
  final double currentZoom;
  final bool isZoomVisible;

  const TopRightControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenterLocation,
    required this.currentZoom,
    this.isZoomVisible = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navState = ref.watch(navigationProvider);

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // POI Toggles (when zoom > 12 and not navigating)
        Consumer(
          builder: (context, ref, child) {
            final mapState = ref.watch(mapProvider);
            final zoom = currentZoom;

            // Hide POI toggles during navigation or at low zoom
            if (navState.isNavigating || zoom <= 12) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                // OSM POIs toggle
                MapToggleButton(
                  isActive: mapState.showOSMPOIs,
                  icon: Icons.business,
                  activeColor: Colors.purple,
                  onPressed: () {
                    ref.read(mapProvider.notifier).toggleOSMPOIs();
                  },
                  tooltip: 'Toggle OSM POIs',
                  enabled: zoom > 12,
                ),
                const SizedBox(height: 6),
                // Wike POIs toggle
                Consumer(
                  builder: (context, ref, child) {
                    final wikePoisVisible = ref.watch(poiVisibilityProvider);
                    return MapToggleButton(
                      isActive: wikePoisVisible,
                      icon: Icons.location_on,
                      activeColor: Colors.green.shade600,
                      count: ref.watch(displayedPoisCountProvider),
                      onPressed: () {
                        ref.read(poiVisibilityProvider.notifier).toggle();
                      },
                      tooltip: 'Toggle Wike POIs',
                      enabled: zoom > 12,
                    );
                  },
                ),
                const SizedBox(height: 6),
                // Warnings toggle
                Consumer(
                  builder: (context, ref, child) {
                    final warningsVisible = ref.watch(warningsVisibilityProvider);
                    return MapToggleButton(
                      isActive: warningsVisible,
                      icon: Icons.warning,
                      activeColor: Colors.red.shade600,
                      count: ref.watch(displayedWarningsCountProvider),
                      onPressed: () {
                        ref.read(warningsVisibilityProvider.notifier).toggle();
                      },
                      tooltip: 'Toggle Hazard Warnings',
                      enabled: zoom > 12,
                    );
                  },
                ),
                const SizedBox(height: 6),
                // Favorites/Destinations toggle
                Consumer(
                  builder: (context, ref, child) {
                    final favoritesVisible = ref.watch(favoritesVisibilityProvider);
                    return MapToggleButton(
                      isActive: favoritesVisible,
                      icon: Icons.star,
                      activeColor: Colors.yellow.shade600,
                      count: ref.watch(displayedFavoritesCountProvider),
                      enabled: true, // Always enabled
                      onPressed: () {
                        ref.read(favoritesVisibilityProvider.notifier).toggle();
                      },
                      tooltip: 'Toggle Favorites & Destinations',
                    );
                  },
                ),
                const SizedBox(height: 6),
              ],
            );
          },
        ),

        // Zoom controls
        if (isZoomVisible)
          Builder(
            builder: (context) {
              final buttonColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
              return Column(
                children: [
                  // Zoom in
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'zoom_in',
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    onPressed: onZoomIn,
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 2),
                  // Zoom level display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      currentZoom.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Zoom out
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'zoom_out',
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    onPressed: onZoomOut,
                    child: const Icon(Icons.remove),
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 6),

        // User Location button (hidden during navigation)
        Consumer(
          builder: (context, ref, child) {
            final navState = ref.watch(navigationProvider);
            final buttonColor = isDark ? Colors.grey.shade700 : Colors.white;

            if (navState.isNavigating) {
              return const SizedBox.shrink();
            }

            return FloatingActionButton(
              mini: true,
              heroTag: 'user_location',
              onPressed: onCenterLocation,
              backgroundColor: buttonColor,
              foregroundColor: AppColors.urbanBlue,
              tooltip: 'Center on Location',
              child: const Icon(Icons.my_location),
            );
          },
        ),

        // Spacing before Profile (hidden when navigating)
        Consumer(
          builder: (context, ref, child) {
            final navState = ref.watch(navigationProvider);
            if (navState.isNavigating) return const SizedBox.shrink();
            return const SizedBox(height: 6);
          },
        ),

        // Profile button (hidden in navigation mode)
        Consumer(
          builder: (context, ref, child) {
            final navState = ref.watch(navigationProvider);
            if (navState.isNavigating) return const SizedBox.shrink();
            return const ProfileButton();
          },
        ),
      ],
    );
  }
}
