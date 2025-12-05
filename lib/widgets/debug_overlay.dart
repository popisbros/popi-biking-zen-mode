import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/debug_provider.dart';

class DebugOverlay extends ConsumerStatefulWidget {
  const DebugOverlay({super.key});

  @override
  ConsumerState<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends ConsumerState<DebugOverlay> {
  Timer? _refreshTimer;
  bool _wasVisible = false;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Start the refresh timer (only when visible)
  void _startTimer() {
    if (_refreshTimer != null) return; // Already running
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {}); // Trigger rebuild to update colors
      }
    });
  }

  /// Stop the refresh timer (when hidden)
  void _stopTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    // First check visibility to avoid unnecessary rebuilds when debug overlay is hidden
    final isVisible = ref.watch(debugProvider.select((s) => s.isVisible));

    // Start/stop timer based on visibility (optimization: no timer when hidden)
    if (isVisible && !_wasVisible) {
      _startTimer();
    } else if (!isVisible && _wasVisible) {
      _stopTimer();
    }
    _wasVisible = isVisible;

    if (!isVisible) {
      return const SizedBox.shrink();
    }

    // Only watch log entries when visible (optimization)
    final logEntries = ref.watch(debugProvider.select((s) => s.logEntries));

    if (logEntries.isEmpty) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Container(
            color: Colors.white.withValues(alpha: 0.2),
            padding: const EdgeInsets.all(16),
            child: const Align(
              alignment: Alignment.topLeft,
              child: Text(
                'No debug messages yet',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Calculate age for each log entry and assign colors
    final now = DateTime.now();
    final textSpans = <TextSpan>[];

    for (var i = 0; i < logEntries.length; i++) {
      final entry = logEntries[i];
      final ageInSeconds = now.difference(entry.timestamp).inSeconds;

      // Fade from black (new) to dark grey (old)
      // Age 0-5 seconds: black
      // Age 5+ seconds: dark grey
      final color = ageInSeconds < 5 ? Colors.black : Colors.grey[700]!;

      textSpans.add(TextSpan(
        text: i == logEntries.length - 1
            ? entry.message  // Last entry, no newline
            : '${entry.message}\n',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ));
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.white.withOpacity(0.2),
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: RichText(
                text: TextSpan(children: textSpans),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
