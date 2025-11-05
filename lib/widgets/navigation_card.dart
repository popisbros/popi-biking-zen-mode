import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path; // Hide Path from latlong2 to avoid conflict with Flutter UI Path
import '../models/maneuver_instruction.dart';
import '../models/navigation_state.dart';
import '../models/route_warning.dart';
import '../providers/navigation_provider.dart';
import '../services/routing_service.dart';

/// Navigation card overlay showing turn-by-turn instructions
/// Option B design: Medium-sized card at top of map
class NavigationCard extends ConsumerStatefulWidget {
  const NavigationCard({super.key});

  @override
  ConsumerState<NavigationCard> createState() => _NavigationCardState();
}

class _NavigationCardState extends ConsumerState<NavigationCard> {
  bool _isManeuversExpanded = false;

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

  /// Map GraphHopper sign to emoji icon
  String _mapGraphHopperSignToIcon(int sign) {
    switch (sign) {
      case -7: return '⮪';  // TURN_SHARP_LEFT
      case -3: return '↰';  // TURN_LEFT
      case -2: return '↖';  // KEEP_LEFT
      case 0:  return '↑';  // CONTINUE
      case 2:  return '↗';  // KEEP_RIGHT
      case 3:  return '↱';  // TURN_RIGHT
      case 7:  return '⮫';  // TURN_SHARP_RIGHT
      case -99: return '↶'; // U_TURN_LEFT
      case 4:  return '🏁'; // FINISH
      default: return '↑';
    }
  }

  /// Calculate distance from current position to GraphHopper instruction
  double _calculateDistanceToGHInstruction(
    LatLng currentPos,
    List<LatLng> routePoints,
    int currentSegmentIndex,
    RouteInstruction instruction,
  ) {
    final Distance distance = const Distance();
    final instructionStartIndex = instruction.interval[0];

    if (instructionStartIndex <= currentSegmentIndex) {
      return 0; // Already at or past this instruction
    }

    // Distance from current position to next waypoint
    double totalDistance = distance.as(
      LengthUnit.Meter,
      currentPos,
      routePoints[currentSegmentIndex + 1],
    );

    // Add distances for segments between next waypoint and instruction start
    for (int i = currentSegmentIndex + 1; i < instructionStartIndex && i < routePoints.length - 1; i++) {
      totalDistance += distance.as(
        LengthUnit.Meter,
        routePoints[i],
        routePoints[i + 1],
      );
    }

    return totalDistance;
  }

  /// Find next GraphHopper instruction after current segment
  RouteInstruction? _getNextGraphHopperInstruction(
    int currentSegmentIndex,
    List<RouteInstruction>? instructions,
  ) {
    if (instructions == null || instructions.isEmpty) return null;

    // Find first instruction that starts after current segment
    for (final instruction in instructions) {
      final start = instruction.interval[0];
      if (start > currentSegmentIndex) {
        return instruction;
      }
    }

    // If no future instruction, return last one (arrival)
    return instructions.last;
  }

  /// Convert GraphHopper instruction to compact format
  String _convertToCompactText(RouteInstruction instruction) {
    final text = instruction.text.toLowerCase();
    final streetName = instruction.streetName;

    // Extract action and add street name if available
    if (text.contains('turn left')) {
      return streetName != null ? 'Left ($streetName)' : 'Left';
    } else if (text.contains('turn right')) {
      return streetName != null ? 'Right ($streetName)' : 'Right';
    } else if (text.contains('sharp left')) {
      return streetName != null ? 'Sharp left ($streetName)' : 'Sharp left';
    } else if (text.contains('sharp right')) {
      return streetName != null ? 'Sharp right ($streetName)' : 'Sharp right';
    } else if (text.contains('keep left')) {
      return streetName != null ? 'Keep left ($streetName)' : 'Keep left';
    } else if (text.contains('keep right')) {
      return streetName != null ? 'Keep right ($streetName)' : 'Keep right';
    } else if (text.contains('continue')) {
      return streetName != null ? 'Continue ($streetName)' : 'Continue';
    } else if (text.contains('u-turn')) {
      return 'U-turn';
    } else if (text.contains('arrive')) {
      return 'Arrive';
    }

    // Fallback: use street name or truncated text
    if (streetName != null) {
      return 'Continue ($streetName)';
    }
    return text.length > 20 ? '${text.substring(0, 20)}...' : text;
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);

    // Only show if navigation is active
    if (!navState.isNavigating) {
      return const SizedBox.shrink();
    }

    // Get next GraphHopper instruction
    final nextGHInstruction = _getNextGraphHopperInstruction(
      navState.currentSegmentIndex,
      navState.activeRoute?.instructions,
    );

    // Get current max speed for speed limit sign
    final maxSpeed = _getPathDetailAtSegment(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      'max_speed',
    );

    // Calculate distance to next GH instruction
    double? distanceToNextGH;
    if (nextGHInstruction != null && navState.currentPosition != null && navState.activeRoute != null) {
      distanceToNextGH = _calculateDistanceToGHInstruction(
        navState.currentPosition!,
        navState.activeRoute!.points,
        navState.currentSegmentIndex,
        nextGHInstruction,
      );
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: MediaQuery.of(context).padding.top + 6, // Add status bar height
        bottom: 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // ============================================================
              // TIER 1: PRIMARY INSTRUCTION (GraphHopper - Rich Context)
              // ============================================================
              if (nextGHInstruction != null && distanceToNextGH != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // GraphHopper instruction icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          _mapGraphHopperSignToIcon(nextGHInstruction.sign),
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // GraphHopper instruction text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nextGHInstruction.text,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'in ${_formatDistance(distanceToNextGH)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Next warning triangle (show if next warning is < 100m away)
                    if (navState.routeWarnings.isNotEmpty && navState.routeWarnings.first.distanceFromUser < 100)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildWarningTriangleSign(navState.routeWarnings.first),
                      ),
                    // Speed limit traffic sign (keep on top right as requested)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _buildSpeedLimitSign(maxSpeed),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade300, height: 1),
                const SizedBox(height: 8),
              ],

              // ============================================================
              // TIER 2: COMPACT PREVIEW (Converted GH + Geometry Insights)
              // ============================================================
              _buildCompactPreview(navState, nextGHInstruction),

              // Route summary
              Row(
                children: [
                  // Remaining distance
                  Icon(
                    Icons.straighten,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    navState.remainingDistanceText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Remaining time
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    navState.remainingTimeText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  // Off-route distance (DEBUG) with countdown timer until next check - only shown when debug enabled
                  if (navState.debugModeEnabled) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: navState.isOffRoute ? Colors.red.shade600 : Colors.green.shade600,
                    ),
                    const SizedBox(width: 4),
                    Builder(
                      builder: (context) {
                        final color = navState.isOffRoute ? Colors.red.shade800 : Colors.green.shade800;

                        // Distance text
                        final distanceText = navState.isOffRoute
                          ? '${navState.offRouteDistanceMeters.toStringAsFixed(0)}m'
                          : '0m';

                        // Time as MM:SS (not full timestamp)
                        String timeText = '--:--';
                        if (navState.lastUpdateTime != null) {
                          final time = navState.lastUpdateTime!;
                          timeText = '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                        }

                        // Format: "0m @12:34" or "25m @12:34"
                        return Text(
                          '$distanceText @$timeText',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        );
                      },
                    ),
                  ],
                  const Spacer(),
                  // ETA
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          navState.etaRangeText,
                          style: TextStyle(
                            fontSize: 13,
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
              // Current speed (always visible) with debug button
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
                  const Spacer(),
                  // Debug toggle button (20x20px)
                  GestureDetector(
                    onTap: () {
                      ref.read(navigationProvider.notifier).toggleDebugMode();
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: navState.debugModeEnabled ? Colors.orange : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          'D',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: navState.debugModeEnabled ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Warnings Section (community + road surface)
              ..._buildWarningsSection(navState),

              // Upcoming Instructions & Geometries Section (Collapsible, DEBUG) - only shown when debug enabled
              if (navState.debugModeEnabled) ...[
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300, height: 1),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isManeuversExpanded = !_isManeuversExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'UPCOMING INSTRUCTIONS & GEOMETRIES (DEBUG)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isManeuversExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: Colors.purple.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isManeuversExpanded)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4, // Max 40% of screen height
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildUpcomingInstructionsDebugSection(navState, nextGHInstruction),
                      ),
                    ),
                  ),
              ],
        ], // End main Column children
      ), // End Column
    ); // End Container
  }

  /// Build compact preview section (Tier 2)
  Widget _buildCompactPreview(NavigationState navState, RouteInstruction? currentGHInstruction) {
    final instructions = navState.activeRoute?.instructions;
    final currentPos = navState.currentPosition;
    final routePoints = navState.activeRoute?.points;

    if (instructions == null || instructions.isEmpty || currentPos == null || routePoints == null) {
      return const SizedBox.shrink();
    }

    // Get next 2-3 GH instructions after current
    final nextInstructions = <RouteInstruction>[];
    bool foundCurrent = currentGHInstruction == null;

    for (final instruction in instructions) {
      if (!foundCurrent) {
        if (instruction == currentGHInstruction) {
          foundCurrent = true;
        }
        continue;
      }

      // Skip if this is the current instruction we're showing in Tier 1
      if (currentGHInstruction != null && instruction.interval[0] == currentGHInstruction.interval[0]) {
        continue;
      }

      nextInstructions.add(instruction);
      if (nextInstructions.length >= 3) break;
    }

    // Generate geometry insight
    final geometryInsight = _generateGeometryInsight(navState);

    // Don't show section if nothing to display
    if (nextInstructions.isEmpty && geometryInsight == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact upcoming instructions - each on separate line
        if (nextInstructions.isNotEmpty) ...[
          // "Then:" label
          Text(
            'Then:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // Each instruction on its own line
          ...nextInstructions.map((instruction) {
            final icon = _mapGraphHopperSignToIcon(instruction.sign);
            final compactText = _convertToCompactText(instruction);
            final distance = _calculateDistanceToGHInstruction(
              currentPos,
              routePoints,
              navState.currentSegmentIndex,
              instruction,
            );

            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Row(
                children: [
                  Text(
                    icon,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      compactText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  Text(
                    _formatDistance(distance),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
        ],

        // Geometry insight (if valuable)
        if (geometryInsight != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: geometryInsight['color'],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: geometryInsight['borderColor']),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Geometry: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: geometryInsight['textColor'],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    geometryInsight['text'],
                    style: TextStyle(
                      fontSize: 12,
                      color: geometryInsight['textColor'],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    geometryInsight['icon'],
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Divider
        Divider(color: Colors.grey.shade300, height: 1),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Generate geometry insight when it adds value
  Map<String, dynamic>? _generateGeometryInsight(NavigationState navState) {
    final nextManeuver = navState.nextManeuver;
    final allManeuvers = navState.allManeuvers;

    if (nextManeuver == null || allManeuvers.isEmpty) return null;

    // Calculate angle from maneuver type
    double? angle;
    if (nextManeuver.type == ManeuverType.sharpLeft || nextManeuver.type == ManeuverType.sharpRight) {
      angle = 125.0; // Approximate sharp turn angle
    } else if (nextManeuver.type == ManeuverType.uTurn) {
      angle = 160.0;
    }

    // Show warning for sharp turns
    if (angle != null && angle > 120) {
      return {
        'icon': '⚠️',
        'text': 'Sharp ${nextManeuver.type == ManeuverType.sharpLeft ? "left" : "right"} ${angle.toInt()}° - Slow approach',
        'color': Colors.orange.shade50,
        'borderColor': Colors.orange.shade300,
        'textColor': Colors.orange.shade900,
      };
    }

    // Check for multiple quick turns (within 200m)
    int quickTurnsCount = 0;
    double cumulativeDistance = 0;
    final currentIndex = navState.currentSegmentIndex;

    for (final maneuver in allManeuvers) {
      if (maneuver.routePointIndex > currentIndex) {
        final distanceToManeuver = maneuver.distanceMeters - cumulativeDistance;
        if (distanceToManeuver < 200 && maneuver.type != ManeuverType.straight && maneuver.type != ManeuverType.arrive) {
          quickTurnsCount++;
        }
      }
    }

    if (quickTurnsCount >= 3) {
      return {
        'icon': '🔄',
        'text': '$quickTurnsCount quick turns ahead - Stay focused',
        'color': Colors.blue.shade50,
        'borderColor': Colors.blue.shade300,
        'textColor': Colors.blue.shade900,
      };
    }

    // For gentle curves at speed, show reassurance
    if (nextManeuver.type == ManeuverType.slightLeft || nextManeuver.type == ManeuverType.slightRight) {
      final speed = navState.currentSpeed ?? 0;
      if (speed > 25) {
        return {
          'icon': '✓',
          'text': 'Gentle curve - Maintain speed',
          'color': Colors.green.shade50,
          'borderColor': Colors.green.shade300,
          'textColor': Colors.green.shade900,
        };
      }
    }

    // Don't show for normal turns
    return null;
  }

  /// Build debug section showing upcoming instructions and all geometries
  List<Widget> _buildUpcomingInstructionsDebugSection(NavigationState navState, RouteInstruction? currentGHInstruction) {
    final instructions = navState.activeRoute?.instructions;
    final currentPos = navState.currentPosition;
    final routePoints = navState.activeRoute?.points;
    final allManeuvers = navState.allManeuvers;

    final List<Widget> widgets = [const SizedBox(height: 8)];

    if (instructions == null || instructions.isEmpty || currentPos == null || routePoints == null) {
      widgets.add(
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'No instructions available.',
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      );
      return widgets;
    }

    // Get next upcoming GH instructions (same as Tier 2)
    final nextInstructions = <RouteInstruction>[];
    bool foundCurrent = currentGHInstruction == null;

    for (final instruction in instructions) {
      if (!foundCurrent) {
        if (instruction == currentGHInstruction) {
          foundCurrent = true;
        }
        continue;
      }

      if (currentGHInstruction != null && instruction.interval[0] == currentGHInstruction.interval[0]) {
        continue;
      }

      nextInstructions.add(instruction);
      if (nextInstructions.length >= 10) break; // Show more in debug mode
    }

    // Section 1: Upcoming GraphHopper Instructions
    if (nextInstructions.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'UPCOMING GRAPHHOPPER INSTRUCTIONS (${nextInstructions.length}):',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.purple.shade900,
            ),
          ),
        ),
      );

      for (final instruction in nextInstructions) {
        final icon = _mapGraphHopperSignToIcon(instruction.sign);
        final compactText = _convertToCompactText(instruction);
        final distance = _calculateDistanceToGHInstruction(
          currentPos,
          routePoints,
          navState.currentSegmentIndex,
          instruction,
        );

        widgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    compactText,
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ),
                Text(
                  _formatDistance(distance),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      widgets.add(const SizedBox(height: 12));
    }

    // Section 2: All Geometry Insights
    if (allManeuvers.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'ALL GEOMETRY INSIGHTS (${allManeuvers.length}):',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.purple.shade900,
            ),
          ),
        ),
      );

      for (final maneuver in allManeuvers) {
        // Generate insight for each maneuver
        final insight = _generateGeometryInsightForManeuver(maneuver, navState);

        if (insight != null) {
          widgets.add(
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: insight['color'],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: insight['borderColor']),
              ),
              child: Row(
                children: [
                  Text(insight['icon'], style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      insight['text'],
                      style: TextStyle(
                        fontSize: 11,
                        color: insight['textColor'],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${maneuver.distanceMeters.toStringAsFixed(0)}m',
                    style: TextStyle(
                      fontSize: 10,
                      color: insight['textColor'],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Show all maneuvers, even those without special insights
          widgets.add(
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Text(maneuver.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      maneuver.instruction,
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                  Text(
                    '${maneuver.distanceMeters.toStringAsFixed(0)}m',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    return widgets;
  }

  /// Generate geometry insight for a specific maneuver (for debug section)
  Map<String, dynamic>? _generateGeometryInsightForManeuver(ManeuverInstruction maneuver, NavigationState navState) {
    // Calculate angle from maneuver type
    double? angle;
    if (maneuver.type == ManeuverType.sharpLeft || maneuver.type == ManeuverType.sharpRight) {
      angle = 125.0;
    } else if (maneuver.type == ManeuverType.uTurn) {
      angle = 160.0;
    }

    // Sharp turns
    if (angle != null && angle > 120) {
      return {
        'icon': '⚠️',
        'text': 'Sharp ${maneuver.type == ManeuverType.sharpLeft ? "left" : "right"} ${angle.toInt()}°',
        'color': Colors.orange.shade50,
        'borderColor': Colors.orange.shade300,
        'textColor': Colors.orange.shade900,
      };
    }

    // Gentle curves
    if (maneuver.type == ManeuverType.slightLeft || maneuver.type == ManeuverType.slightRight) {
      return {
        'icon': '✓',
        'text': 'Gentle ${maneuver.type == ManeuverType.slightLeft ? "left" : "right"} curve',
        'color': Colors.green.shade50,
        'borderColor': Colors.green.shade300,
        'textColor': Colors.green.shade900,
      };
    }

    // No special insight for this maneuver
    return null;
  }

  /// Build a warning triangle sign for next upcoming warning
  Widget _buildWarningTriangleSign(RouteWarning warning) {
    // Determine border color based on warning type
    final borderColor = warning.type == RouteWarningType.community
        ? Colors.red.shade700
        : Colors.orange.shade700;

    return SizedBox(
      width: 48,
      height: 48,
      child: CustomPaint(
        painter: _WarningTrianglePainter(borderColor),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4), // Slight offset to center in triangle
            child: Text(
              warning.icon,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }

  /// Build a speed limit traffic sign (European style circular sign)
  Widget _buildSpeedLimitSign(dynamic speedLimit) {
    // Cast speed to integer, or show "?" if null
    final String speedText = speedLimit != null
        ? (speedLimit is int ? speedLimit.toString() : (speedLimit as num).toInt().toString())
        : '?';

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: Colors.red.shade700,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          speedText,
          style: TextStyle(
            fontSize: speedText.length > 2 ? 18 : 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  /// Build unified warnings section (community + road surface)
  List<Widget> _buildWarningsSection(NavigationState navState) {
    final warnings = navState.routeWarnings;

    // No warnings - show positive message
    if (warnings.isEmpty) {
      return [
        const SizedBox(height: 12),
        Divider(color: Colors.grey.shade300, height: 1),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              '🚴🏾‍♀️',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Clear road ahead - Enjoy your ride safely',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ];
    }

    // Has warnings - show list with counter on first warning
    final List<Widget> warningWidgets = [
      const SizedBox(height: 12),
      Divider(color: Colors.grey.shade300, height: 1),
      const SizedBox(height: 8),
    ];

    // Show warnings based on expanded state
    final warningsToShow = navState.warningsExpanded
        ? warnings
        : [warnings.first];

    for (int i = 0; i < warningsToShow.length; i++) {
      final warning = warningsToShow[i];
      final isFirst = i == 0;

      if (i > 0) {
        warningWidgets.add(const SizedBox(height: 6));
      }

      warningWidgets.add(
        GestureDetector(
          // Only make first warning tappable if there are multiple warnings
          onTap: warnings.length > 1 && isFirst
              ? () {
                  ref.read(navigationProvider.notifier).toggleWarningsExpanded();
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: warning.backgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: warning.borderColor),
            ),
            child: Row(
              children: [
                Text(
                  warning.icon,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  warning.distanceText,
                  style: TextStyle(
                    fontSize: 12,
                    color: warning.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Show counter and expand arrow on first warning if there are multiple warnings
                if (isFirst && warnings.length > 1) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${warnings.length})',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    navState.warningsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey.shade700,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return warningWidgets;
  }

  /// Format distance in meters to human-readable string
  String _formatDistance(double meters) {
    if (meters < 100) {
      return '${meters.toStringAsFixed(0)} meters';
    } else if (meters < 1000) {
      return '${(meters / 10).round() * 10} meters';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

}

/// Custom painter for warning triangle sign (like European road signs)
class _WarningTrianglePainter extends CustomPainter {
  final Color borderColor;

  _WarningTrianglePainter(this.borderColor);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    // Draw triangle pointing up (equilateral-ish)
    final double margin = 2;
    path.moveTo(size.width / 2, margin); // Top center
    path.lineTo(size.width - margin, size.height - margin); // Bottom right
    path.lineTo(margin, size.height - margin); // Bottom left
    path.close();

    // Fill with white
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);

    // Add shadow
    canvas.drawShadow(path, Colors.black26, 3.0, false);
  }

  @override
  bool shouldRepaint(_WarningTrianglePainter oldDelegate) =>
      oldDelegate.borderColor != borderColor;
}
