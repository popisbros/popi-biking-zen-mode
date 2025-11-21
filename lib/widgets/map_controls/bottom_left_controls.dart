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
    final debugState = ref.watch(debugProvider);
    final navState = ref.watch(navigationProvider);
    final navModeState = ref.watch(navigationModeProvider);
    final mapState = ref.watch(mapProvider);
    final isNavigationMode = navModeState.mode == NavMode.navigation;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Debug toggle button (always at the top)
        FloatingActionButton(
          mini: true,
          heroTag: 'debug_toggle',
          onPressed: () {
            ref.read(debugProvider.notifier).toggleVisibility();
          },
          backgroundColor: debugState.isVisible ? Colors.red : inactiveColor,
          foregroundColor: Colors.white,
          tooltip: 'Debug Tracking',
          child: const Icon(Icons.bug_report),
        ),
        const SizedBox(height: 6),

        // Auto-zoom toggle button (only show in navigation mode)
        if (isNavigationMode && onAutoZoomToggle != null)
          FloatingActionButton(
            mini: true,
            heroTag: 'auto_zoom_toggle',
            onPressed: onAutoZoomToggle,
            backgroundColor: mapState.autoZoomEnabled ? Colors.blue : inactiveColor,
            foregroundColor: mapState.autoZoomEnabled ? Colors.white : inactiveFgColor,
            tooltip: mapState.autoZoomEnabled ? 'Disable Auto-Zoom' : 'Enable Auto-Zoom',
            child: Icon(mapState.autoZoomEnabled ? Icons.zoom_out_map : Icons.zoom_out_map_outlined),
          ),

        // Spacing after auto-zoom button (only in navigation mode)
        if (isNavigationMode && onAutoZoomToggle != null)
          const SizedBox(height: 6),

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

        // Spacing after Compass (only on Native and visible when NOT navigating OR debug mode is ON)
        if (!kIsWeb && showCompass && onCompassToggle != null && (!navState.isNavigating || debugState.isVisible))
          const SizedBox(height: 6),

        // Reload POIs button (only visible when NOT navigating AND debug tracking is ON)
        if (!navState.isNavigating && debugState.isVisible && onReloadPOIs != null)
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
