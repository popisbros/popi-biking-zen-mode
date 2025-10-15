import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../services/routing_service.dart';

/// Navigation card overlay showing turn-by-turn instructions
/// Option B design: Medium-sized card at top of map
class NavigationCard extends ConsumerWidget {
  const NavigationCard({super.key});

  /// Get current GraphHopper instruction based on segment index
  RouteInstruction? _getCurrentInstruction(int segmentIndex, List<RouteInstruction>? instructions) {
    if (instructions == null || instructions.isEmpty) return null;

    // Find instruction that contains the current segment
    for (final instruction in instructions) {
      final start = instruction.interval[0];
      final end = instruction.interval[1];
      if (segmentIndex >= start && segmentIndex <= end) {
        return instruction;
      }
    }
    return null;
  }

  /// Get path detail value at current segment
  dynamic _getPathDetailAtSegment(int segmentIndex, Map<String, dynamic>? pathDetails, String key) {
    if (pathDetails == null || !pathDetails.containsKey(key)) return null;

    final detailList = pathDetails[key] as List?;
    if (detailList == null || detailList.isEmpty) return null;

    // Each detail entry is [startIndex, endIndex, value]
    for (final detail in detailList) {
      final detailData = detail as List;
      final start = detailData[0] as int;
      final end = detailData[1] as int;
      if (segmentIndex >= start && segmentIndex <= end) {
        return detailData[2]; // The value
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);

    // Only show if navigation is active
    if (!navState.isNavigating) {
      return const SizedBox.shrink();
    }

    // Get current GraphHopper data
    final currentInstruction = _getCurrentInstruction(
      navState.currentSegmentIndex,
      navState.activeRoute?.instructions,
    );
    final streetName = _getPathDetailAtSegment(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      'street_name',
    );
    final lanes = _getPathDetailAtSegment(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      'lanes',
    );
    final roadClass = _getPathDetailAtSegment(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      'road_class',
    );
    final maxSpeed = _getPathDetailAtSegment(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      'max_speed',
    );
    final surface = _getPathDetailAtSegment(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      'surface',
    );

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16, // Below status bar
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey.shade50,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Maneuver instruction
              if (navState.nextManeuver != null) ...[
                Row(
                  children: [
                    // Maneuver icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          navState.nextManeuver!.icon,
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Instruction text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            navState.nextManeuver!.instruction,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            navState.nextManeuver!.distanceText,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Divider
                Divider(
                  color: Colors.grey.shade300,
                  height: 1,
                ),
                const SizedBox(height: 12),
              ],
              // Route summary
              Row(
                children: [
                  // Remaining distance
                  Icon(
                    Icons.straighten,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    navState.remainingDistanceText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Remaining time
                  Icon(
                    Icons.access_time,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    navState.remainingTimeText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  // ETA
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 16,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          navState.etaText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Progress bar
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: navState.progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade600,
                  ),
                ),
              ),
              // Current speed (if available)
              if (navState.currentSpeed != null && navState.currentSpeed! > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.speed,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      navState.speedText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],

              // GraphHopper Path Details Section
              if (streetName != null || lanes != null || roadClass != null || maxSpeed != null || surface != null) ...[
                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade300, height: 1),
                const SizedBox(height: 12),
                // Section header
                Text(
                  'GRAPHHOPPER DATA (LIVE)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                // Data grid
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (streetName != null)
                      _buildDataChip(
                        icon: Icons.signpost,
                        label: 'Street',
                        value: streetName.toString(),
                        color: Colors.blue,
                      ),
                    if (currentInstruction?.streetRef != null)
                      _buildDataChip(
                        icon: Icons.route,
                        label: 'Ref',
                        value: currentInstruction!.streetRef!,
                        color: Colors.green,
                      ),
                    if (currentInstruction?.streetDestination != null)
                      _buildDataChip(
                        icon: Icons.location_on,
                        label: 'To',
                        value: currentInstruction!.streetDestination!,
                        color: Colors.purple,
                      ),
                    if (lanes != null)
                      _buildDataChip(
                        icon: Icons.multiple_stop,
                        label: 'Lanes',
                        value: lanes.toString(),
                        color: Colors.orange,
                      ),
                    if (roadClass != null)
                      _buildDataChip(
                        icon: Icons.category,
                        label: 'Class',
                        value: roadClass.toString(),
                        color: Colors.teal,
                      ),
                    if (maxSpeed != null)
                      _buildDataChip(
                        icon: Icons.speed,
                        label: 'Max Speed',
                        value: '$maxSpeed km/h',
                        color: Colors.red,
                      ),
                    if (surface != null)
                      _buildDataChip(
                        icon: Icons.texture,
                        label: 'Surface',
                        value: surface.toString(),
                        color: Colors.brown,
                      ),
                  ],
                ),
              ],

              // GraphHopper Instruction (if different from custom maneuver)
              if (currentInstruction != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GraphHopper Instruction:',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentInstruction.text,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build a data chip for GraphHopper details
  Widget _buildDataChip({
    required IconData icon,
    required String label,
    required String value,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
