import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/poi_type_config.dart';
import '../providers/map_provider.dart';

/// OSM POI Type Selector Button
///
/// Replaces the simple toggle with a multi-select dropdown menu.
/// Features:
/// - "None of these" option (removes all markers, button grey/inactive)
/// - Individual POI type options with emoji icons
/// - "All of these" option (shows all POI types, button blue/active)
/// - Count badge showing number of visible POIs
/// - Closes automatically on selection
class OSMPOISelectorButton extends ConsumerWidget {
  final int count;
  final bool enabled;

  const OSMPOISelectorButton({
    super.key,
    required this.count,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapState = ref.watch(mapProvider);
    final selectedTypes = mapState.selectedOSMPOITypes;

    // Determine button state
    final bool isActive = mapState.showOSMPOIs &&
                         (selectedTypes == null || selectedTypes.isNotEmpty);
    final Color activeColor = Colors.blue;

    return Tooltip(
      message: enabled ? 'Select OSM POI types' : 'POI selector (disabled at zoom ≤ 12)',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FloatingActionButton(
            mini: true,
            backgroundColor: enabled
                ? (isActive ? activeColor : Colors.grey.shade300)
                : Colors.grey.shade200,
            foregroundColor: enabled ? Colors.white : Colors.grey.shade400,
            onPressed: enabled ? () => _showPOISelector(context, ref) : null,
            heroTag: 'osm_poi_selector',
            child: const Icon(Icons.location_on),
          ),
          // Count badge
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
                    count > 999 ? '999+' : count.toString(),
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

  void _showPOISelector(BuildContext context, WidgetRef ref) {
    final mapState = ref.read(mapProvider);
    final selectedTypes = mapState.selectedOSMPOITypes ?? {};

    // Get button position for dropdown alignment
    final RenderBox button = context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero);
    final buttonSize = button.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + buttonSize.height,
        buttonPosition.dx + 250, // menu width
        buttonPosition.dy,
      ),
      items: [
        // "None of these" option
        PopupMenuItem(
          value: 'none',
          child: Row(
            children: [
              Icon(
                selectedTypes.isEmpty ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: selectedTypes.isEmpty ? Colors.grey : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              const Text(
                'None of these',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),

        // Individual POI types
        ...POITypeConfig.osmPOITypes.entries
            .where((entry) => entry.key != 'unknown') // Exclude 'unknown'
            .map((entry) {
          final poiType = entry.key;
          final label = entry.value['label']!;
          final emoji = entry.value['emoji']!;
          final isSelected = selectedTypes.contains(poiType);

          return PopupMenuItem(
            value: poiType,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: isSelected ? Colors.blue : Colors.grey.shade400,
                ),
                const SizedBox(width: 12),
                Text(
                  '$emoji  $label',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),

        const PopupMenuDivider(),

        // "All of these" option
        PopupMenuItem(
          value: 'all',
          child: Row(
            children: [
              Icon(
                selectedTypes.length == POITypeConfig.osmPOITypes.length - 1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selectedTypes.length == POITypeConfig.osmPOITypes.length - 1
                    ? Colors.blue
                    : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              const Text(
                'All of these',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return; // User dismissed menu

      if (value == 'none') {
        // Clear all selections
        ref.read(mapProvider.notifier).setSelectedOSMPOITypes({});
      } else if (value == 'all') {
        // Select all types (except 'unknown')
        final allTypes = POITypeConfig.osmPOITypes.keys
            .where((key) => key != 'unknown')
            .toSet();
        ref.read(mapProvider.notifier).setSelectedOSMPOITypes(allTypes);
      } else {
        // Toggle individual type
        final newTypes = Set<String>.from(selectedTypes);
        if (newTypes.contains(value)) {
          newTypes.remove(value);
        } else {
          newTypes.add(value);
        }
        ref.read(mapProvider.notifier).setSelectedOSMPOITypes(newTypes);
      }
    });
  }
}
