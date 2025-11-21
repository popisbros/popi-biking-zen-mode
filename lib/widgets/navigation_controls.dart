import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../providers/navigation_mode_provider.dart';
import '../providers/search_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_profile.dart';
import '../services/audio_announcement_service.dart';
import '../utils/route_calculation_helper.dart';
import 'common_dialog.dart';

/// Navigation control FABs (Audio Toggle + End Navigation)
/// These appear alongside existing FABs when navigation is active
class NavigationControls extends ConsumerWidget {
  final VoidCallback? onNavigationEnded;

  const NavigationControls({super.key, this.onNavigationEnded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);

    // Only show if navigation is active
    if (!navState.isNavigating) {
      return const SizedBox.shrink();
    }

    // Get current audio mode from user profile
    final userProfile = ref.watch(userProfileProvider).value;
    final currentAudioMode = userProfile?.audioMode ?? AudioMode.informationAndAlerts;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Audio toggle button
        FloatingActionButton(
          mini: true,
          heroTag: 'nav_audio',
          onPressed: () {
            _cycleAudioMode(ref, currentAudioMode);
          },
          backgroundColor: _getAudioButtonColor(currentAudioMode),
          foregroundColor: Colors.white,
          tooltip: 'Audio: ${currentAudioMode.label}',
          child: Icon(_getAudioIcon(currentAudioMode)),
        ),
        const SizedBox(height: 6),
        // End navigation button
        FloatingActionButton(
          mini: true,
          heroTag: 'nav_end',
          onPressed: () {
            _showEndNavigationDialog(context, ref, onNavigationEnded);
          },
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          tooltip: 'End navigation',
          child: const Icon(Icons.close),
        ),
      ],
    );
  }

  /// Get icon for current audio mode
  IconData _getAudioIcon(AudioMode mode) {
    switch (mode) {
      case AudioMode.informationAndAlerts:
        return Icons.volume_up;
      case AudioMode.justAlerts:
        return Icons.volume_down;
      case AudioMode.none:
        return Icons.volume_off;
    }
  }

  /// Get button color for current audio mode
  Color _getAudioButtonColor(AudioMode mode) {
    switch (mode) {
      case AudioMode.informationAndAlerts:
        return Colors.blue[700]!;
      case AudioMode.justAlerts:
        return Colors.orange[700]!;
      case AudioMode.none:
        return Colors.grey[600]!;
    }
  }

  /// Cycle through audio modes: Information & Alerts → Just Alerts → No → Information & Alerts
  void _cycleAudioMode(WidgetRef ref, AudioMode currentMode) {
    AudioMode nextMode;
    switch (currentMode) {
      case AudioMode.informationAndAlerts:
        nextMode = AudioMode.justAlerts;
        break;
      case AudioMode.justAlerts:
        nextMode = AudioMode.none;
        break;
      case AudioMode.none:
        nextMode = AudioMode.informationAndAlerts;
        break;
    }

    // Update user profile
    ref.read(authNotifierProvider.notifier).updateProfile(audioMode: nextMode);

    // Update audio service immediately
    AudioAnnouncementService().setAudioMode(nextMode);
  }

  /// Show confirmation dialog before ending navigation
  static void _showEndNavigationDialog(BuildContext context, WidgetRef ref, VoidCallback? onNavigationEnded) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF2C2C2C).withValues(alpha: CommonDialog.backgroundOpacity)
        : Colors.white.withValues(alpha: CommonDialog.backgroundOpacity);

    showDialog(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          titlePadding: CommonDialog.titlePadding,
          contentPadding: CommonDialog.contentPadding,
          actionsPadding: CommonDialog.actionsPadding,
          title: const Text('End Navigation?'),
          content: const Text('Are you sure you want to stop navigation?'),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CommonDialog.buildBorderedTextButton(
                  label: 'Cancel',
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                CommonDialog.buildBorderedTextButton(
                  label: 'End',
                  textColor: Colors.red,
                  onPressed: () {
                    Navigator.of(context).pop();

                    // Clear route from provider
                    ref.read(searchProvider.notifier).clearRoute();

                    // Stop turn-by-turn navigation
                    ref.read(navigationProvider.notifier).stopNavigation();

                    // Exit navigation mode (return to exploration)
                    ref.read(navigationModeProvider.notifier).stopRouteNavigation();

                    // Restore POI visibility to pre-route-selection state
                    RouteCalculationHelper.restorePOIStateAfterNavigation(ref);

                    // Call callback to clear route from map
                    onNavigationEnded?.call();

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Navigation ended'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
