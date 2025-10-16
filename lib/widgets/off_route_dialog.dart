import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';

/// Dialog shown when user goes off the planned route
/// Asks if they want to recalculate or continue with current route
class OffRouteDialog extends ConsumerWidget {
  const OffRouteDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);

    // Only show if off-route flag is set
    if (!navState.showingOffRouteDialog) {
      return const SizedBox.shrink();
    }

    // Show dialog immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navState.showingOffRouteDialog) {
        _showDialog(context, ref);
      }
    });

    return const SizedBox.shrink();
  }

  void _showDialog(BuildContext context, WidgetRef ref) {
    final navState = ref.read(navigationProvider);
    final distanceMeters = navState.offRouteDistanceMeters;
    final distanceText = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text('Off Route'),
            ],
          ),
          content: Text(
            'You have deviated from the planned route.\n'
            'Distance from route: $distanceText\n\n'
            'Would you like to recalculate the route from your current location?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(navigationProvider.notifier).dismissOffRouteDialog();
              },
              child: const Text('Continue'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                // Show loading indicator
                // For native apps, use fixed bottom position (30px from bottom)
                // For web/PWA, use standard vertical margin (10px)
                final bottomMargin = kIsWeb ? 10.0 : 30.0;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Recalculating route...',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(
                      left: 60,
                      right: 60,
                      bottom: bottomMargin,
                      top: 10,
                    ),
                  ),
                );

                // Recalculate route
                await ref.read(navigationProvider.notifier).recalculateRoute();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Recalculate'),
            ),
          ],
        );
      },
    );
  }
}
