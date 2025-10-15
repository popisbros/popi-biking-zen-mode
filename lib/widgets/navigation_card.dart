import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path; // Hide Path from latlong2 to avoid conflict with Flutter UI Path
import '../models/navigation_state.dart';
import '../providers/navigation_provider.dart';
import '../services/routing_service.dart';
import '../services/route_hazard_detector.dart';

/// Navigation card overlay showing turn-by-turn instructions
/// Option B design: Medium-sized card at top of map
class NavigationCard extends ConsumerStatefulWidget {
  const NavigationCard({super.key});

  @override
  ConsumerState<NavigationCard> createState() => _NavigationCardState();
}

class _NavigationCardState extends ConsumerState<NavigationCard> {
  bool _isGraphHopperDataExpanded = false;

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

  /// Get next segment info (surface type and distance)
  /// Only returns info if the IMMEDIATE next segment (different from current) needs a warning
  Map<String, dynamic>? _getNextSegmentInfo(int currentSegmentIndex, Map<String, dynamic>? pathDetails, List<LatLng>? routePoints) {
    if (pathDetails == null || !pathDetails.containsKey('surface') || routePoints == null) return null;

    final surfaceList = pathDetails['surface'] as List?;
    if (surfaceList == null || surfaceList.isEmpty) return null;

    // First, find which segment we're currently on
    String? currentSurface;
    int? currentSegmentEnd;

    for (final detail in surfaceList) {
      final detailData = detail as List;
      final start = detailData[0] as int;
      final end = detailData[1] as int;
      final surfaceType = detailData[2] as String;

      if (start <= currentSegmentIndex && currentSegmentIndex < end) {
        currentSurface = surfaceType;
        currentSegmentEnd = end;
        break;
      }
    }

    // Now find the IMMEDIATE next segment (the one with smallest start >= currentSegmentEnd)
    if (currentSegmentEnd != null) {
      int? closestStart;
      Map<String, dynamic>? nextSegment;

      for (final detail in surfaceList) {
        final detailData = detail as List;
        final start = detailData[0] as int;
        final end = detailData[1] as int;
        final surfaceType = detailData[2] as String;

        // Find segment that starts at or right after current segment ends
        // Track the one with the SMALLEST start index
        if (start >= currentSegmentEnd && start > currentSegmentIndex) {
          if (closestStart == null || start < closestStart) {
            closestStart = start;

            // Calculate distance to this segment
            double distance = 0;
            for (int i = currentSegmentIndex; i < start && i < routePoints.length - 1; i++) {
              distance += const Distance().as(
                LengthUnit.Meter,
                routePoints[i],
                routePoints[i + 1],
              );
            }

            // Calculate segment length
            double segmentLength = 0;
            for (int i = start; i < end && i < routePoints.length - 1; i++) {
              segmentLength += const Distance().as(
                LengthUnit.Meter,
                routePoints[i],
                routePoints[i + 1],
              );
            }

            nextSegment = {
              'surface': surfaceType,
              'distanceTo': distance,
              'segmentLength': segmentLength,
            };
          }
        }
      }

      return nextSegment;
    }

    return null;
  }

  /// Check if surface requires warning (not excellent or good)
  bool _surfaceNeedsWarning(dynamic surface) {
    if (surface == null) return false;
    final surfaceStr = surface.toString().toLowerCase();

    // Excellent surfaces (no warning)
    if (surfaceStr.contains('asphalt') ||
        surfaceStr.contains('concrete') ||
        surfaceStr.contains('paved')) {
      return false;
    }

    // Good surfaces (no warning)
    if (surfaceStr.contains('compacted') ||
        surfaceStr.contains('fine_gravel')) {
      return false;
    }

    // Everything else needs warning
    return true;
  }

  /// Get icon for surface type
  IconData _getSurfaceIcon(dynamic surface) {
    if (surface == null) return Icons.help_outline;
    final surfaceStr = surface.toString().toLowerCase();

    // Moderate surfaces (gravel, unpaved)
    if (surfaceStr.contains('gravel') || surfaceStr.contains('unpaved')) {
      return Icons.texture;
    }

    // Poor surfaces (dirt, sand, grass, mud)
    if (surfaceStr.contains('dirt') ||
        surfaceStr.contains('sand') ||
        surfaceStr.contains('grass') ||
        surfaceStr.contains('mud')) {
      return Icons.warning;
    }

    // Special surfaces (cobblestone, sett)
    if (surfaceStr.contains('cobble') || surfaceStr.contains('sett')) {
      return Icons.grid_4x4;
    }

    return Icons.warning;
  }

  @override
  Widget build(BuildContext context) {
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

    // Get next segment info
    final nextSegmentInfo = _getNextSegmentInfo(
      navState.currentSegmentIndex,
      navState.activeRoute?.pathDetails,
      navState.activeRoute?.points,
    );

    return Positioned(
      top: MediaQuery.of(context).padding.top + 1, // 5px lower than before (-4 + 5 = 1)
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          navState.nextManeuver!.icon,
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Instruction text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            navState.nextManeuver!.instruction,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDistance(navState.distanceToNextManeuver),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          // Next segment info (only show if next segment has a warning)
                          if (nextSegmentInfo != null && _surfaceNeedsWarning(nextSegmentInfo['surface'])) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.warning, size: 14, color: Colors.orange),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Next: ${(nextSegmentInfo['segmentLength'] as double).toInt()}m - ${nextSegmentInfo['surface']} [DEBUG: dist=${(nextSegmentInfo['distanceTo'] as double).toInt()}m idx=${navState.currentSegmentIndex}]',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Surface warning triangle (only for moderate/poor/special surfaces)
                    if (_surfaceNeedsWarning(surface))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildSurfaceWarningSign(surface),
                      ),
                    // Speed limit traffic sign (same size as maneuver icon: 48x48)
                    _buildSpeedLimitSign(maxSpeed),
                  ],
                ),
                const SizedBox(height: 12),
                // Divider
                Divider(
                  color: Colors.grey.shade300,
                  height: 1,
                ),
                const SizedBox(height: 8),
              ],
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
                          navState.etaText,
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

              // Hazard Section (above GraphHopper data)
              ..._buildHazardSection(navState),

              // GraphHopper Path Details Section (Collapsible)
              if (streetName != null || lanes != null || roadClass != null || maxSpeed != null || surface != null) ...[
                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade300, height: 1),
                const SizedBox(height: 8),
                // Section header with expand/collapse button
                InkWell(
                  onTap: () {
                    setState(() {
                      _isGraphHopperDataExpanded = !_isGraphHopperDataExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'GRAPHHOPPER DATA (LIVE)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isGraphHopperDataExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: Colors.orange.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                // Expandable data grid
                if (_isGraphHopperDataExpanded) ...[
                  const SizedBox(height: 8),
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
                      if (surface != null)
                        _buildDataChip(
                          icon: Icons.texture,
                          label: 'Surface',
                          value: surface.toString(),
                          color: Colors.brown,
                        ),
                    ],
                  ),
                  // GraphHopper Instruction (inside collapsible section)
                  if (currentInstruction != null) ...[
                    const SizedBox(height: 8),
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build a surface warning triangle sign
  Widget _buildSurfaceWarningSign(dynamic surface) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: Colors.red.shade700,
          width: 3,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _TriangleBorderPainter(Colors.red.shade700),
        child: Center(
          child: Icon(
            _getSurfaceIcon(surface),
            size: 24,
            color: Colors.black87,
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
            color: Colors.black.withOpacity(0.1),
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

  /// Build hazard warning section
  List<Widget> _buildHazardSection(NavigationState navState) {
    // Check if we have hazards on the route
    if (navState.activeRoute?.routeHazards == null || navState.activeRoute!.routeHazards!.isEmpty) {
      // No hazards - show positive message
      return [
        const SizedBox(height: 12),
        Divider(color: Colors.grey.shade300, height: 1),
        const SizedBox(height: 8),
        // Positive message (no title to save space)
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Route clear, enjoy your ride ✌️',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ];
    }

    // Get upcoming hazards
    final routeHazards = navState.activeRoute!.routeHazards!;
    final currentPosition = navState.currentPosition;
    final routePoints = navState.activeRoute!.points;
    if (currentPosition == null || routePoints.isEmpty) return [];

    // Calculate current position's distance along route
    final Distance distance = const Distance();
    double currentDistanceAlongRoute = 0;

    // Find current segment and calculate distance from start
    final currentSegmentIndex = navState.currentSegmentIndex;
    for (int i = 0; i < currentSegmentIndex && i < routePoints.length - 1; i++) {
      currentDistanceAlongRoute += distance.as(
        LengthUnit.Meter,
        routePoints[i],
        routePoints[i + 1],
      );
    }

    // Add distance from current segment start to current position
    if (currentSegmentIndex < routePoints.length) {
      currentDistanceAlongRoute += distance.as(
        LengthUnit.Meter,
        routePoints[currentSegmentIndex],
        currentPosition,
      );
    }

    // Find all upcoming hazards (ahead of current position)
    final List<Map<String, dynamic>> upcomingHazards = [];

    for (final hazard in routeHazards) {
      // Only consider hazards ahead on the route
      if (hazard.distanceAlongRoute > currentDistanceAlongRoute) {
        final distanceAhead = hazard.distanceAlongRoute - currentDistanceAlongRoute;
        upcomingHazards.add({
          'hazard': hazard,
          'distanceAhead': distanceAhead,
        });
      }
    }

    // Sort by distance ahead
    upcomingHazards.sort((a, b) => (a['distanceAhead'] as double).compareTo(b['distanceAhead'] as double));

    if (upcomingHazards.isEmpty) return [];

    // Build UI for all upcoming hazards
    final List<Widget> hazardWidgets = [
      const SizedBox(height: 12),
      Divider(color: Colors.grey.shade300, height: 1),
      const SizedBox(height: 8),
    ];

    // Add each hazard as a row
    for (int i = 0; i < upcomingHazards.length; i++) {
      final hazardData = upcomingHazards[i];
      final RouteHazard hazard = hazardData['hazard'] as RouteHazard;
      final double distanceAhead = hazardData['distanceAhead'] as double;
      final hazardIcon = _getHazardIcon(hazard.warning.type);

      if (i > 0) {
        hazardWidgets.add(const SizedBox(height: 6)); // Spacing between hazards
      }

      hazardWidgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              Icon(hazardIcon, color: Colors.red.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hazard.warning.title,
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
                '${distanceAhead.toStringAsFixed(0)}m',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return hazardWidgets;
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

  /// Get icon for hazard type
  IconData _getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pothole':
        return Icons.warning;
      case 'broken_glass':
        return Icons.dangerous;
      case 'roadwork':
        return Icons.construction;
      case 'debris':
        return Icons.warning_amber;
      case 'poor_surface':
        return Icons.terrain;
      case 'traffic':
        return Icons.traffic;
      case 'accident':
        return Icons.car_crash;
      default:
        return Icons.warning;
    }
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

/// Custom painter for triangle border in warning sign
class _TriangleBorderPainter extends CustomPainter {
  final Color color;

  _TriangleBorderPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final path = Path();
    // Draw triangle pointing up
    path.moveTo(size.width / 2, 8); // Top center
    path.lineTo(size.width - 8, size.height - 8); // Bottom right
    path.lineTo(8, size.height - 8); // Bottom left
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TriangleBorderPainter oldDelegate) => false;
}
