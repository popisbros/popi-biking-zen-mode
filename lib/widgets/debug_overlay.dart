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

  @override
  void initState() {
    super.initState();
    // Refresh every second to update colors
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {}); // Trigger rebuild to update colors
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debugState = ref.watch(debugProvider);

    if (!debugState.isVisible) {
      return const SizedBox.shrink();
    }

    if (debugState.logEntries.isEmpty) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Container(
            color: Colors.white.withOpacity(0.2),
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

    for (var i = 0; i < debugState.logEntries.length; i++) {
      final entry = debugState.logEntries[i];
      final ageInSeconds = now.difference(entry.timestamp).inSeconds;

      // Fade from black (new) to dark grey (old)
      // Age 0-5 seconds: black
      // Age 5+ seconds: dark grey
      final color = ageInSeconds < 5 ? Colors.black : Colors.grey[700]!;

      textSpans.add(TextSpan(
        text: i == debugState.logEntries.length - 1
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
