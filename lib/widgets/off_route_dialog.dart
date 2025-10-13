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
          content: const Text(
            'You have deviated from the planned route.\n\n'
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Recalculating route...'),
                      ],
                    ),
                    duration: Duration(seconds: 3),
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
