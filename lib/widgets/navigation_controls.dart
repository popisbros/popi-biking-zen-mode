import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';

/// Navigation control FABs (End Navigation + Voice Mute)
/// These appear alongside existing FABs when navigation is active
class NavigationControls extends ConsumerStatefulWidget {
  final VoidCallback? onNavigationEnded;

  const NavigationControls({super.key, this.onNavigationEnded});

  @override
  ConsumerState<NavigationControls> createState() => _NavigationControlsState();
}

class _NavigationControlsState extends ConsumerState<NavigationControls> {
  bool _isVoiceMuted = false;

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);

    // Only show if navigation is active
    if (!navState.isNavigating) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Voice mute/unmute button
        FloatingActionButton(
          mini: true,
          heroTag: 'nav_voice_toggle',
          onPressed: () {
            setState(() {
              _isVoiceMuted = !_isVoiceMuted;
            });
            // TODO: In Phase 4, connect to VoiceService
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isVoiceMuted ? 'Voice guidance muted' : 'Voice guidance enabled',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          backgroundColor: _isVoiceMuted ? Colors.grey : Colors.green,
          foregroundColor: Colors.white,
          tooltip: _isVoiceMuted ? 'Unmute voice' : 'Mute voice',
          child: Icon(_isVoiceMuted ? Icons.volume_off : Icons.volume_up),
        ),
        const SizedBox(height: 8),
        // End navigation button
        FloatingActionButton(
          mini: true,
          heroTag: 'nav_end',
          onPressed: () {
            _showEndNavigationDialog(context);
          },
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          tooltip: 'End navigation',
          child: const Icon(Icons.close),
        ),
      ],
    );
  }

  /// Show confirmation dialog before ending navigation
  void _showEndNavigationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Navigation?'),
          content: const Text('Are you sure you want to stop navigation?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(navigationProvider.notifier).stopNavigation();

                // Call callback to clear route from map
                widget.onNavigationEnded?.call();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Navigation ended'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text(
                'End',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}
