import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path; // Hide Path from latlong2 to avoid conflict with Flutter UI Path
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
  bool _isGraphHopperDataExpanded = false;
  bool _isManeuversExpanded = false;
  bool _showDebugSections = false; // Controls visibility of all debug sections

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
        mainAxisAlignment: MainAxisAlignment.start, // Align content to top
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Maneuver instruction
              if (navState.nextManeuver != null) ...[
                Row(
                  children: [
                    // Maneuver icon with debug button overlay
                    Stack(
                      children: [
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
                        // Small debug button (10x10px) in top-right corner
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showDebugSections = !_showDebugSections;
                              });
                            },
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _showDebugSections ? Colors.orange : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                          // GraphHopper instruction (for comparison) - only shown when debug enabled
                          if (_showDebugSections && currentInstruction != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amber.shade300, width: 1),
                              ),
                              child: Text(
                                'GH: ${currentInstruction.text}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Next warning triangle (show if next warning is < 100m away)
                    if (navState.routeWarnings.isNotEmpty && navState.routeWarnings.first.distanceFromUser < 100)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildWarningTriangleSign(navState.routeWarnings.first),
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
                  // Off-route distance (DEBUG) with countdown timer until next check - only shown when debug enabled
                  if (_showDebugSections) ...[
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
                          ? '${navState.offRouteDistanceMeters?.toStringAsFixed(0) ?? "?"}m'
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
              // Current speed (always visible)
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

              // Warnings Section (community + road surface)
              ..._buildWarningsSection(navState),

              // GraphHopper Path Details Section (Collapsible) - only shown when debug enabled
              if (_showDebugSections && (streetName != null || lanes != null || roadClass != null || maxSpeed != null || surface != null)) ...[
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

              // Maneuvers Section (Collapsible, DEBUG) - only shown when debug enabled
              if (_showDebugSections) ...[
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
                          'MANEUVERS (DEBUG)',
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
                if (_isManeuversExpanded) ..._buildManeuversSection(navState),
              ],
        ], // End main Column children
      ), // End Column
    ); // End Container
  }

  /// Build all maneuvers list with distances
  List<Widget> _buildManeuversSection(NavigationState navState) {
    final allManeuvers = navState.allManeuvers;
    final currentPosition = navState.currentPosition;
    final routePoints = navState.activeRoute?.points;
    final nextManeuver = navState.nextManeuver;

    if (allManeuvers.isEmpty) {
      return [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'No maneuvers detected on this route.',
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ];
    }

    if (currentPosition == null || routePoints == null) {
      return [const SizedBox(height: 8)];
    }

    // Calculate current distance along route
    final Distance distance = const Distance();
    double currentDistanceAlongRoute = 0;
    final currentSegmentIndex = navState.currentSegmentIndex;

    for (int i = 0; i < currentSegmentIndex && i < routePoints.length - 1; i++) {
      currentDistanceAlongRoute += distance.as(
        LengthUnit.Meter,
        routePoints[i],
        routePoints[i + 1],
      );
    }
    if (currentSegmentIndex < routePoints.length) {
      currentDistanceAlongRoute += distance.as(
        LengthUnit.Meter,
        routePoints[currentSegmentIndex],
        currentPosition,
      );
    }

    // Build list of maneuvers with distances
    final List<Widget> widgets = [const SizedBox(height: 8)];

    for (final maneuver in allManeuvers) {
      // Calculate distance to this maneuver
      double distanceToManeuver = 0;
      for (int i = 0; i < maneuver.routePointIndex && i < routePoints.length - 1; i++) {
        distanceToManeuver += distance.as(
          LengthUnit.Meter,
          routePoints[i],
          routePoints[i + 1],
        );
      }

      // Distance from current position (negative = passed, positive = ahead)
      final double relativeDistance = distanceToManeuver - currentDistanceAlongRoute;
      final bool isNext = nextManeuver != null && maneuver.routePointIndex == nextManeuver.routePointIndex;

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isNext ? Colors.green.shade50 : Colors.purple.shade50,
            borderRadius: BorderRadius.circular(6),
            border: isNext ? Border.all(color: Colors.green.shade700, width: 2) : null,
          ),
          child: Row(
            children: [
              // Maneuver icon
              Text(
                maneuver.icon,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              // Maneuver instruction
              Expanded(
                child: Text(
                  maneuver.instruction,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Distance indicator
              Text(
                relativeDistance >= 0
                    ? '+${relativeDistance.toStringAsFixed(0)}m'
                    : '${relativeDistance.toStringAsFixed(0)}m',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: relativeDistance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
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

    // Has warnings - show header + list
    final List<Widget> warningWidgets = [
      const SizedBox(height: 12),
      Divider(color: Colors.grey.shade300, height: 1),
      const SizedBox(height: 8),
    ];

    // Header: "⚠️ Warnings (N) ▼/▶" - tap to toggle
    warningWidgets.add(
      GestureDetector(
        onTap: () {
          ref.read(navigationProvider.notifier).toggleWarningsExpanded();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Text(
                'Warnings (${warnings.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Icon(
                navState.warningsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: Colors.grey.shade700,
              ),
            ],
          ),
        ),
      ),
    );

    // Show warnings based on expanded state
    final warningsToShow = navState.warningsExpanded
        ? warnings
        : (warnings.isNotEmpty ? [warnings.first] : <RouteWarning>[]);

    for (int i = 0; i < warningsToShow.length; i++) {
      final warning = warningsToShow[i];

      warningWidgets.add(const SizedBox(height: 6));

      warningWidgets.add(
        Container(
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
            ],
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
