import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/community_warning.dart';
import '../models/user_profile.dart';
import '../utils/app_logger.dart';

/// Service for audio announcements during navigation
///
/// Supports three modes:
/// - Information & Alerts: Turn-by-turn + milestones + hazards + off-route
/// - Just Alerts: Hazards + off-route only
/// - No: No audio announcements
class AudioAnnouncementService {
  static final AudioAnnouncementService _instance = AudioAnnouncementService._internal();
  factory AudioAnnouncementService() => _instance;
  AudioAnnouncementService._internal();

  final FlutterTts _tts = FlutterTts();
  final Set<String> _announcedHazards = {};
  final Set<String> _announcedTurns = {}; // Track announced turn instructions
  AudioMode _audioMode = AudioMode.informationAndAlerts;

  // Distance thresholds (in meters)
  static const double _hazardAnnouncementDistance = 100.0;
  static const double _turnAnnouncementDistance1 = 200.0; // First announcement
  static const double _turnAnnouncementDistance2 = 50.0; // Second announcement
  static const double _arrivalDistance = 20.0;

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

  /// Set audio announcement mode
  void setAudioMode(AudioMode mode) {
    _audioMode = mode;
    AppLogger.info('Audio mode set to: ${mode.label}');
  }

  /// Get current audio mode
  AudioMode get audioMode => _audioMode;

  /// Check if any audio is enabled
  bool get isEnabled => _audioMode != AudioMode.none;

  /// Check if information announcements are enabled (turn-by-turn, milestones)
  bool get _informationEnabled => _audioMode == AudioMode.informationAndAlerts;

  /// Check if alert announcements are enabled (hazards, off-route)
  bool get _alertsEnabled => _audioMode != AudioMode.none;

  /// Clear announced items (e.g., when starting a new route)
  void clearAnnouncedItems() {
    _announcedHazards.clear();
    _announcedTurns.clear();
    AppLogger.info('Cleared announced hazards and turns');
  }

  /// Clear announced hazards (backward compatibility)
  @Deprecated('Use clearAnnouncedItems() instead')
  void clearAnnouncedHazards() {
    clearAnnouncedItems();
  }

  /// Check hazards proximity and announce if necessary
  /// Returns list of newly announced hazard IDs
  Future<List<String>> checkHazardsProximity(
    Position currentPosition,
    List<CommunityWarning> hazards,
  ) async {
    if (!_alertsEnabled) {
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
      if (distance <= _hazardAnnouncementDistance) {
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

  // ========== INFORMATION ANNOUNCEMENTS (turn-by-turn, milestones) ==========

  /// Announce navigation start
  Future<void> announceNavigationStart({
    required double distanceKm,
    required int durationMin,
  }) async {
    if (!_informationEnabled) return;

    try {
      final message = 'Starting navigation. '
          'Distance: ${distanceKm.toStringAsFixed(1)} kilometers. '
          'Estimated time: $durationMin minutes.';
      AppLogger.info('Announcing: $message', tag: 'AUDIO');
      await _tts.speak(message);
    } catch (e) {
      AppLogger.error('Failed to announce navigation start', error: e);
    }
  }

  /// Announce turn instruction with distance
  Future<void> announceTurnInstruction({
    required String instruction,
    required double distanceMeters,
    required String turnId, // Unique ID to prevent duplicate announcements
  }) async {
    if (!_informationEnabled) return;
    if (_announcedTurns.contains(turnId)) return;

    try {
      String message;
      if (distanceMeters >= _turnAnnouncementDistance1) {
        message = 'In ${distanceMeters.round()} meters, $instruction';
      } else if (distanceMeters >= _turnAnnouncementDistance2) {
        message = 'In ${distanceMeters.round()} meters, $instruction';
      } else {
        message = instruction;
      }

      AppLogger.info('Announcing turn: $message', tag: 'AUDIO');
      await _tts.speak(message);
      _announcedTurns.add(turnId);
    } catch (e) {
      AppLogger.error('Failed to announce turn instruction', error: e);
    }
  }

  /// Announce arrival at destination
  Future<void> announceArrival() async {
    if (!_informationEnabled) return;

    try {
      const message = 'You have arrived at your destination.';
      AppLogger.info('Announcing: $message', tag: 'AUDIO');
      await _tts.speak(message);
    } catch (e) {
      AppLogger.error('Failed to announce arrival', error: e);
    }
  }

  /// Announce rerouting
  Future<void> announceRerouting() async {
    if (!_informationEnabled) return;

    try {
      const message = 'Recalculating route.';
      AppLogger.info('Announcing: $message', tag: 'AUDIO');
      await _tts.speak(message);
    } catch (e) {
      AppLogger.error('Failed to announce rerouting', error: e);
    }
  }

  // ========== ALERT ANNOUNCEMENTS (hazards, off-route) ==========

  /// Announce off-route alert
  Future<void> announceOffRoute() async {
    if (!_alertsEnabled) return;

    try {
      const message = 'You are off route. Please return to the route or recalculate.';
      AppLogger.info('Announcing: $message', tag: 'AUDIO');
      await _tts.speak(message);
    } catch (e) {
      AppLogger.error('Failed to announce off-route', error: e);
    }
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
    _announcedTurns.clear();
  }
}
