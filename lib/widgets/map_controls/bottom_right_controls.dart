import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/debug_provider.dart';
import '../navigation_controls.dart';

/// Bottom-right map controls: navigation controls OR map style/3D pickers
/// Shared between 2D and 3D map screens
class BottomRightControls extends ConsumerWidget {
  final VoidCallback? onNavigationEnded;
  final VoidCallback? onLayerPicker;
  final VoidCallback? on3DSwitch;
  final VoidCallback? onPitchPicker;
  final Widget? customStylePicker;

  const BottomRightControls({
    super.key,
    this.onNavigationEnded,
    this.onLayerPicker,
    this.on3DSwitch,
    this.onPitchPicker,
    this.customStylePicker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only watch specific properties we need
    final isNavigating = ref.watch(navigationProvider.select((s) => s.isNavigating));
    final debugVisible = ref.watch(debugProvider.select((s) => s.isVisible));

    // Show Navigation Controls when navigating
    if (isNavigating) {
      return NavigationControls(
        onNavigationEnded: onNavigationEnded,
      );
    }

    // Show map controls when not navigating
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Custom style picker (for 3D map) OR Layer picker (for 2D map)
        if (customStylePicker != null)
          customStylePicker!
        else if (onLayerPicker != null)
          FloatingActionButton(
            mini: true,
            heroTag: 'layer_picker',
            onPressed: onLayerPicker,
            backgroundColor: Colors.blue,
            tooltip: 'Change Map Layer',
            child: const Icon(Icons.layers),
          ),

        // Pitch picker (3D map only) OR 3D Map switch (2D map only)
        if (onPitchPicker != null) ...[
          const SizedBox(height: 4),
          FloatingActionButton(
            mini: true,
            heroTag: 'pitch_picker',
            onPressed: onPitchPicker,
            backgroundColor: Colors.green,
            tooltip: 'Change Camera Pitch',
            child: const Icon(Icons.threesixty),
          ),
        ] else if (on3DSwitch != null && !kIsWeb) ...[
          const SizedBox(height: 4),
          FloatingActionButton(
            mini: true,
            heroTag: '3d_map',
            onPressed: on3DSwitch,
            backgroundColor: Colors.green,
            tooltip: 'Switch to 3D Map',
            child: const Icon(Icons.terrain),
          ),
        ],

        // 2D/3D switch (3D map only - only show when debug tracking is enabled)
        if (on3DSwitch != null && customStylePicker != null && !kIsWeb && debugVisible) ...[
          const SizedBox(height: 4),
          FloatingActionButton(
            mini: true,
            heroTag: '2d_3d_switch',
            onPressed: on3DSwitch,
            backgroundColor: Colors.teal,
            tooltip: 'Switch to 2D Map',
            child: const Icon(Icons.map),
          ),
        ],
      ],
    );
  }
}
