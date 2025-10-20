import 'package:flutter/material.dart';
import 'community_warning.dart';
import '../config/poi_type_config.dart';

/// Type of route warning
enum RouteWarningType {
  /// Community-reported warning (construction, hazard, etc.)
  community,

  /// Road surface quality warning (poor or unknown surface)
  roadSurface,
}

/// Road surface quality classification
enum RoadSurfaceQuality {
  /// Poor surface quality (gravel, dirt, mud, etc.)
  poor,

  /// Unknown surface quality
  unknown,
}

/// Unified warning model for navigation
/// Combines community warnings and road surface warnings
class RouteWarning {
  /// Type of warning
  final RouteWarningType type;

  /// Distance from route start in meters
  final double distanceAlongRoute;

  /// Distance from user's current position in meters
  final double distanceFromUser;

  // ============================================================================
  // Community Warning Fields
  // ============================================================================

  /// Community warning data (only for type == community)
  final CommunityWarning? communityWarning;

  // ============================================================================
  // Road Surface Warning Fields
  // ============================================================================

  /// Road surface quality (only for type == roadSurface)
  final RoadSurfaceQuality? surfaceQuality;

  /// Length of poor/unknown surface segment in meters (only for type == roadSurface)
  final double? surfaceLength;

  /// Surface type string from GraphHopper (only for type == roadSurface)
  final String? surfaceType;

  const RouteWarning({
    required this.type,
    required this.distanceAlongRoute,
    required this.distanceFromUser,
    this.communityWarning,
    this.surfaceQuality,
    this.surfaceLength,
    this.surfaceType,
  });

  // ============================================================================
  // UI Properties
  // ============================================================================

  /// Get emoji icon for this warning
  String get icon {
    switch (type) {
      case RouteWarningType.community:
        // Use existing icon mapping from POITypeConfig
        return POITypeConfig.getWarningEmoji(communityWarning?.type ?? 'hazard');

      case RouteWarningType.roadSurface:
        switch (surfaceQuality!) {
          case RoadSurfaceQuality.poor:
            return '⚠️'; // Warning triangle for poor surfaces
          case RoadSurfaceQuality.unknown:
            return 'ℹ️'; // Info icon for unknown surfaces
        }
    }
  }

  /// Get formatted title for display
  String get title {
    switch (type) {
      case RouteWarningType.community:
        return communityWarning?.title ?? 'Warning';

      case RouteWarningType.roadSurface:
        final qualityText = surfaceQuality == RoadSurfaceQuality.poor ? 'Poor' : 'Unknown surface';
        final lengthText = surfaceLength != null
            ? (surfaceLength! >= 1000
                ? '${(surfaceLength! / 1000).toStringAsFixed(1)}km'
                : '${surfaceLength!.toStringAsFixed(0)}m')
            : '';
        return lengthText.isNotEmpty ? '$qualityText - $lengthText' : qualityText;
    }
  }

  /// Get background color for warning container
  Color get backgroundColor {
    switch (type) {
      case RouteWarningType.community:
        return Colors.red.shade50;
      case RouteWarningType.roadSurface:
        return Colors.orange.shade50;
    }
  }

  /// Get border color for warning container
  Color get borderColor {
    switch (type) {
      case RouteWarningType.community:
        return Colors.red.shade200;
      case RouteWarningType.roadSurface:
        return Colors.orange.shade200;
    }
  }

  /// Get text color for warning
  Color get textColor {
    switch (type) {
      case RouteWarningType.community:
        return Colors.red.shade700;
      case RouteWarningType.roadSurface:
        return Colors.orange.shade700;
    }
  }

  /// Get formatted distance text (e.g., "in 250m")
  String get distanceText {
    final meters = distanceFromUser;
    if (meters < 1000) {
      return 'in ${meters.toStringAsFixed(0)}m';
    } else {
      return 'in ${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  @override
  String toString() {
    return 'RouteWarning(type: $type, distance: ${distanceAlongRoute.toStringAsFixed(0)}m, '
        'fromUser: ${distanceFromUser.toStringAsFixed(0)}m, title: $title)';
  }
}
