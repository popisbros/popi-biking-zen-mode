import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../constants/app_colors.dart';
import 'common_dialog.dart';

/// Dialog shown when user arrives at destination
class ArrivalDialog extends ConsumerStatefulWidget {
  final String destinationName;
  final double finalDistance;
  final VoidCallback? onFindParking; // Callback when "Find a parking" is pressed
  final Future<void> Function()? onEndNavigation; // Async callback when "End Navigation" is pressed

  const ArrivalDialog({
    super.key,
    required this.destinationName,
    required this.finalDistance,
    this.onFindParking,
    this.onEndNavigation,
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
    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
      titlePadding: EdgeInsets.zero,
      contentPadding: CommonDialog.contentPadding,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: null,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),

          // Success icon with animation
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
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
          const Text(
            'You\'ve Arrived!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),

          const SizedBox(height: 8),

          // Destination name
          Text(
            widget.destinationName,
            style: const TextStyle(
              fontSize: CommonDialog.titleFontSize,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 4),

          // Final distance
          CommonDialog.buildCaptionText(
            'Final distance: ${widget.finalDistance.toStringAsFixed(0)}m',
          ),

          const SizedBox(height: 8),

          // Countdown timer
          Text(
            'Auto-closing in ${_remainingSeconds}s',
            style: const TextStyle(
              fontSize: CommonDialog.smallFontSize,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // End Navigation button
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  _countdownTimer?.cancel();
                  Navigator.of(context).pop();

                  // Call custom callback if provided (for comprehensive cleanup like stopping real-time stream, restoring style, etc.)
                  await widget.onEndNavigation?.call();

                  // Stop navigation in provider (redundant with callback, but safe fallback)
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

            // Find a parking button (shows nearby bicycle parking)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _countdownTimer?.cancel();
                  Navigator.of(context).pop();
                  widget.onFindParking?.call();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.local_parking, size: 20),
                label: const Text('Find a parking'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
