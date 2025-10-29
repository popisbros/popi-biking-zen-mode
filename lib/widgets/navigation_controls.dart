import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../providers/navigation_mode_provider.dart';
import '../providers/search_provider.dart';
import 'common_dialog.dart';

/// Navigation control FAB (End Navigation)
/// This appears alongside existing FABs when navigation is active
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

    return FloatingActionButton(
      mini: true,
      heroTag: 'nav_end',
      onPressed: () {
        _showEndNavigationDialog(context, ref, onNavigationEnded);
      },
      backgroundColor: Colors.red,
      foregroundColor: Colors.white,
      tooltip: 'End navigation',
      child: const Icon(Icons.close),
    );
  }

  /// Show confirmation dialog before ending navigation
  static void _showEndNavigationDialog(BuildContext context, WidgetRef ref, VoidCallback? onNavigationEnded) {
    showDialog(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
          titlePadding: CommonDialog.titlePadding,
          contentPadding: CommonDialog.contentPadding,
          actionsPadding: CommonDialog.actionsPadding,
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

                // Clear route from provider
                ref.read(searchProvider.notifier).clearRoute();

                // Stop turn-by-turn navigation
                ref.read(navigationProvider.notifier).stopNavigation();

                // Exit navigation mode (return to exploration)
                ref.read(navigationModeProvider.notifier).stopRouteNavigation();

                // Call callback to clear route from map
                onNavigationEnded?.call();

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
