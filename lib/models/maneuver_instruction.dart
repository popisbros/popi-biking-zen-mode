import 'package:latlong2/latlong.dart';

/// Type of navigation maneuver
enum ManeuverType {
  /// Continue straight ahead
  straight,

  /// Turn left
  turnLeft,

  /// Turn right
  turnRight,

  /// Sharp left turn
  sharpLeft,

  /// Sharp right turn
  sharpRight,

  /// Slight left turn
  slightLeft,

  /// Slight right turn
  slightRight,

  /// Make U-turn
  uTurn,

  /// Arrived at destination
  arrive,

  /// Depart (start of navigation)
  depart,
}

/// Instruction for a navigation maneuver
class ManeuverInstruction {
  /// Type of maneuver to perform
  final ManeuverType type;

  /// Human-readable instruction (e.g., "Turn left onto Main Street")
  final String instruction;

  /// Distance to this maneuver in meters
  final double distanceMeters;

  /// Location where maneuver should be executed
  final LatLng location;

  /// Index of route point where maneuver occurs
  final int routePointIndex;

  const ManeuverInstruction({
    required this.type,
    required this.instruction,
    required this.distanceMeters,
    required this.location,
    required this.routePointIndex,
  });

  /// Get human-readable distance string
  String get distanceText {
    if (distanceMeters < 100) {
      return '${distanceMeters.toStringAsFixed(0)} meters';
    } else if (distanceMeters < 1000) {
      return '${(distanceMeters / 10).round() * 10} meters';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Get short instruction for voice guidance
  String get voiceInstruction {
    switch (type) {
      case ManeuverType.turnLeft:
        return 'Turn left';
      case ManeuverType.turnRight:
        return 'Turn right';
      case ManeuverType.sharpLeft:
        return 'Sharp left turn';
      case ManeuverType.sharpRight:
        return 'Sharp right turn';
      case ManeuverType.slightLeft:
        return 'Keep left';
      case ManeuverType.slightRight:
        return 'Keep right';
      case ManeuverType.straight:
        return 'Continue straight';
      case ManeuverType.uTurn:
        return 'Make a U-turn';
      case ManeuverType.arrive:
        return 'Arrived at your destination';
      case ManeuverType.depart:
        return 'Start your route';
    }
  }

  /// Get icon for maneuver (emoji representation)
  String get icon {
    switch (type) {
      case ManeuverType.turnLeft:
        return '↰';
      case ManeuverType.turnRight:
        return '↱';
      case ManeuverType.sharpLeft:
        return '⮪';
      case ManeuverType.sharpRight:
        return '⮫';
      case ManeuverType.slightLeft:
        return '↖';
      case ManeuverType.slightRight:
        return '↗';
      case ManeuverType.straight:
        return '↑';
      case ManeuverType.uTurn:
        return '↶';
      case ManeuverType.arrive:
        return '🏁';
      case ManeuverType.depart:
        return '🚴';
    }
  }

  @override
  String toString() {
    return 'ManeuverInstruction(type: $type, distance: $distanceText, instruction: $instruction)';
  }

  ManeuverInstruction copyWith({
    ManeuverType? type,
    String? instruction,
    double? distanceMeters,
    LatLng? location,
    int? routePointIndex,
  }) {
    return ManeuverInstruction(
      type: type ?? this.type,
      instruction: instruction ?? this.instruction,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      location: location ?? this.location,
      routePointIndex: routePointIndex ?? this.routePointIndex,
    );
  }
}
