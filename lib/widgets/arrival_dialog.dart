import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../constants/app_colors.dart';

/// Dialog shown when user arrives at destination
class ArrivalDialog extends ConsumerStatefulWidget {
  final String destinationName;
  final double finalDistance;

  const ArrivalDialog({
    super.key,
    required this.destinationName,
    required this.finalDistance,
  });

  @override
  ConsumerState<ArrivalDialog> createState() => _ArrivalDialogState();
}

class _ArrivalDialogState extends ConsumerState<ArrivalDialog> {
  Timer? _countdownTimer;
  int _remainingSeconds = 10;

  @override
  void initState() {
    super.initState();

    // Trigger haptic feedback
    HapticFeedback.mediumImpact();

    // Start countdown timer
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        // Auto-close after 10 seconds
        timer.cancel();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon with animation
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 60,
              ),
            ),

            const SizedBox(height: 16),

            // "You've Arrived!" text
            Text(
              'You\'ve Arrived!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
            ),

            const SizedBox(height: 8),

            // Destination name
            Text(
              widget.destinationName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 4),

            // Final distance
            Text(
              'Final distance: ${widget.finalDistance.toStringAsFixed(0)}m',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),

            const SizedBox(height: 8),

            // Countdown timer
            Text(
              'Auto-closing in ${_remainingSeconds}s',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // End Navigation button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _countdownTimer?.cancel();
                      Navigator.of(context).pop();
                      ref.read(navigationProvider.notifier).stopNavigation();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mossGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('End Navigation'),
                  ),
                ),

                const SizedBox(width: 12),

                // OK button (dismiss but keep navigation active)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _countdownTimer?.cancel();
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.mossGreen,
                      side: BorderSide(color: AppColors.mossGreen),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
