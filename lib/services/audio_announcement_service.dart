import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/community_warning.dart';
import '../utils/app_logger.dart';

/// Service for audio announcements of hazards during navigation
class AudioAnnouncementService {
  static final AudioAnnouncementService _instance = AudioAnnouncementService._internal();
  factory AudioAnnouncementService() => _instance;
  AudioAnnouncementService._internal();

  final FlutterTts _tts = FlutterTts();
  final Set<String> _announcedHazards = {};
  bool _isEnabled = true;

  // Distance threshold for audio announcements (in meters)
  static const double _audioAnnouncementDistance = 100.0;

  /// Initialize TTS settings
  Future<void> initialize() async {
    try {
      // Set language
      await _tts.setLanguage("en-US");

      // Set speech rate (0.0 to 1.0, where 0.5 is normal)
      await _tts.setSpeechRate(0.5);

      // Set volume (0.0 to 1.0)
      await _tts.setVolume(1.0);

      // Set pitch (0.5 to 2.0, where 1.0 is normal)
      await _tts.setPitch(1.0);

      AppLogger.success('Audio announcement service initialized');
    } catch (e) {
      AppLogger.error('Failed to initialize TTS', error: e);
    }
  }

  /// Enable or disable audio announcements
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    AppLogger.info('Audio announcements ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if audio announcements are enabled
  bool get isEnabled => _isEnabled;

  /// Clear announced hazards (e.g., when starting a new route)
  void clearAnnouncedHazards() {
    _announcedHazards.clear();
    AppLogger.info('Cleared announced hazards list');
  }

  /// Check hazards proximity and announce if necessary
  /// Returns list of newly announced hazard IDs
  Future<List<String>> checkHazardsProximity(
    Position currentPosition,
    List<CommunityWarning> hazards,
  ) async {
    if (!_isEnabled) {
      return [];
    }

    final List<String> newlyAnnounced = [];
    final currentLatLng = LatLng(currentPosition.latitude, currentPosition.longitude);

    for (final hazard in hazards) {
      // Skip if already announced
      if (hazard.id == null || _announcedHazards.contains(hazard.id!)) {
        continue;
      }

      // Skip if not active
      if (hazard.status != 'active') {
        continue;
      }

      // Calculate distance
      final hazardLatLng = LatLng(hazard.latitude, hazard.longitude);
      final distance = _calculateDistance(currentLatLng, hazardLatLng);

      // Announce if within threshold
      if (distance <= _audioAnnouncementDistance) {
        await _announceHazard(hazard);
        _announcedHazards.add(hazard.id!);
        newlyAnnounced.add(hazard.id!);
      }
    }

    return newlyAnnounced;
  }

  /// Announce a specific hazard
  Future<void> _announceHazard(CommunityWarning hazard) async {
    try {
      // Build announcement message
      final message = _buildAnnouncementMessage(hazard);

      AppLogger.info('Announcing hazard: $message');
      await _tts.speak(message);
    } catch (e) {
      AppLogger.error('Failed to announce hazard', error: e);
    }
  }

  /// Build announcement message for a hazard
  String _buildAnnouncementMessage(CommunityWarning hazard) {
    final typeText = _getHazardTypeAnnouncement(hazard.type);
    final severityText = _getSeverityAnnouncement(hazard.severity);

    // Basic announcement
    String message = 'Warning. $severityText $typeText ahead.';

    // Add verification status
    if (hazard.isVerified) {
      message += ' Verified by community.';
    }

    // Add title if meaningful (not just repeating the type)
    if (hazard.title.isNotEmpty &&
        !hazard.title.toLowerCase().contains(hazard.type.toLowerCase())) {
      message += ' ${hazard.title}.';
    }

    return message;
  }

  /// Get human-readable hazard type for announcement
  String _getHazardTypeAnnouncement(String type) {
    switch (type) {
      case 'pothole':
        return 'Pothole';
      case 'construction':
        return 'Construction zone';
      case 'dangerous_intersection':
        return 'Dangerous intersection';
      case 'poor_surface':
        return 'Poor road surface';
      case 'debris':
        return 'Debris on road';
      case 'traffic_hazard':
        return 'Traffic hazard';
      case 'steep':
        return 'Steep section';
      case 'flooding':
        return 'Flooding';
      case 'other':
      default:
        return 'Hazard';
    }
  }

  /// Get severity announcement text
  String _getSeverityAnnouncement(String severity) {
    switch (severity) {
      case 'high':
        return 'High severity';
      case 'medium':
        return 'Moderate';
      case 'low':
        return 'Minor';
      default:
        return '';
    }
  }

  /// Calculate distance between two coordinates (in meters)
  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Stop any ongoing speech
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      AppLogger.error('Failed to stop TTS', error: e);
    }
  }

  /// Test audio announcement
  Future<void> testAnnouncement() async {
    await _tts.speak('Audio announcements are working correctly.');
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    _announcedHazards.clear();
  }
}
