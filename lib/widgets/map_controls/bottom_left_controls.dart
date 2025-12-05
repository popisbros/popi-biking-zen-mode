import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/navigation_mode_provider.dart';
import '../../providers/map_provider.dart';
import '../../providers/debug_provider.dart';

/// Bottom-left map controls: debug, auto-zoom, compass, reload
/// Shared between 2D and 3D map screens
class BottomLeftControls extends ConsumerWidget {
  final VoidCallback? onAutoZoomToggle;
  final VoidCallback? onCompassToggle;
  final VoidCallback? onReloadPOIs;
  final bool? compassEnabled;
  final bool showCompass;

  const BottomLeftControls({
    super.key,
    this.onAutoZoomToggle,
    this.onCompassToggle,
    this.onReloadPOIs,
    this.compassEnabled,
    this.showCompass = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final inactiveFgColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    // Use select() to only watch specific properties we need
    final debugVisible = ref.watch(debugProvider.select((s) => s.isVisible));
    final isNavigating = ref.watch(navigationProvider.select((s) => s.isNavigating));
    final isNavigationMode = ref.watch(navigationModeProvider.select((s) => s.mode == NavMode.navigation));
    final autoZoomEnabled = ref.watch(mapProvider.select((s) => s.autoZoomEnabled));

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Debug toggle button (always at the top)
        FloatingActionButton(
          mini: true,
          heroTag: 'debug_toggle',
          onPressed: () {
            ref.read(debugProvider.notifier).toggleVisibility();
          },
          backgroundColor: debugVisible ? Colors.red : inactiveColor,
          foregroundColor: Colors.white,
          tooltip: 'Debug Tracking',
          child: const Icon(Icons.bug_report),
        ),

        // Spacing after debug button (only show when there's a button below it)
        if ((isNavigationMode && onAutoZoomToggle != null) || (!kIsWeb && showCompass && onCompassToggle != null))
          const SizedBox(height: 4),

        // Auto-zoom toggle button (only show in navigation mode)
        if (isNavigationMode && onAutoZoomToggle != null)
          FloatingActionButton(
            mini: true,
            heroTag: 'auto_zoom_toggle',
            onPressed: onAutoZoomToggle,
            backgroundColor: autoZoomEnabled ? Colors.blue : inactiveColor,
            foregroundColor: autoZoomEnabled ? Colors.white : inactiveFgColor,
            tooltip: autoZoomEnabled ? 'Disable Auto-Zoom' : 'Enable Auto-Zoom',
            child: Icon(autoZoomEnabled ? Icons.zoom_out_map : Icons.zoom_out_map_outlined),
          ),

        // Spacing after auto-zoom button (only in navigation mode)
        if (isNavigationMode && onAutoZoomToggle != null)
          const SizedBox(height: 4),

        // Compass rotation toggle button (Native only)
        if (!kIsWeb && showCompass && onCompassToggle != null)
          FloatingActionButton(
            mini: true,
            heroTag: 'compass_rotation_toggle',
            onPressed: onCompassToggle,
            backgroundColor: (compassEnabled ?? false) ? Colors.purple : inactiveColor,
            foregroundColor: (compassEnabled ?? false) ? Colors.white : inactiveFgColor,
            tooltip: 'Toggle Compass Rotation',
            child: Icon((compassEnabled ?? false) ? Icons.explore : Icons.explore_off),
          ),

        // Spacing after Compass (only show when reload button below is visible)
        if (!kIsWeb && showCompass && onCompassToggle != null && !isNavigating && debugVisible && onReloadPOIs != null)
          const SizedBox(height: 4),

        // Reload POIs button (only visible when NOT navigating AND debug tracking is ON)
        if (!isNavigating && debugVisible && onReloadPOIs != null)
          FloatingActionButton(
            mini: true,
            heroTag: 'reload_pois',
            onPressed: onReloadPOIs,
            backgroundColor: Colors.orange,
            tooltip: 'Reload POIs',
            child: const Icon(Icons.refresh),
          ),
      ],
    );
  }
}
