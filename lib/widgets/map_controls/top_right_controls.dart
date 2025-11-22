import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/navigation_provider.dart';
import '../../constants/app_colors.dart';
import '../profile_button.dart';

/// Top-right map controls: zoom, user location, profile
/// Shared between 2D and 3D map screens
/// Note: POI toggles are handled separately by each map screen
class TopRightControls extends ConsumerWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenterLocation;
  final double currentZoom;
  final bool isZoomVisible;
  final Widget? poiToggles; // Optional POI toggles widget

  const TopRightControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenterLocation,
    required this.currentZoom,
    this.isZoomVisible = true,
    this.poiToggles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navState = ref.watch(navigationProvider);

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // POI Toggles (provided by parent screen)
        if (poiToggles != null) ...[
          poiToggles!,
          const SizedBox(height: 4),
        ],

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
        const SizedBox(height: 4),

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
            return const SizedBox(height: 4);
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
