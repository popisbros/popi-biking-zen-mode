import 'package:flutter/material.dart';

/// A reusable toggle button widget for map layer controls.
///
/// Features:
/// - Active/inactive state with customizable colors
/// - Count badge overlay (with optional 99+ limit)
/// - Enable/disable functionality
/// - Tooltip support
/// - Consistent styling across 2D and 3D map screens
///
/// Used for toggling:
/// - OSM POIs (blue)
/// - Warnings/Hazards (orange)
class MapToggleButton extends StatelessWidget {
  /// Whether the toggle is currently active
  final bool isActive;

  /// Icon to display in the button
  final IconData icon;

  /// Color when the toggle is active
  final Color activeColor;

  /// Number to display in the count badge (0 = no badge)
  final int count;

  /// Callback when button is pressed
  final VoidCallback onPressed;

  /// Tooltip text for the button
  final String tooltip;

  /// If true, shows actual count. If false, shows "99+" for counts > 99
  final bool showFullCount;

  /// If false, button is disabled and greyed out
  final bool enabled;

  const MapToggleButton({
    super.key,
    required this.isActive,
    required this.icon,
    required this.activeColor,
    required this.count,
    required this.onPressed,
    required this.tooltip,
    this.showFullCount = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final disabledForeground = isDark ? Colors.grey.shade600 : Colors.grey.shade400;

    return Tooltip(
      message: enabled ? tooltip : '$tooltip (disabled at zoom ≤ 12)',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FloatingActionButton(
            mini: true,
            backgroundColor: enabled
                ? (isActive ? activeColor : inactiveColor)
                : disabledColor,
            foregroundColor: enabled ? Colors.white : disabledForeground,
            onPressed: enabled ? onPressed : null,
            heroTag: tooltip,
            child: Icon(icon),
          ),
          // Only show count when toggle is active AND count > 0
          if (isActive && count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                child: Center(
                  child: Text(
                    showFullCount ? count.toString() : (count > 99 ? '99+' : count.toString()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
