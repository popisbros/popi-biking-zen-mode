import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_logger.dart';

class DebugLogEntry {
  final String message;
  final DateTime timestamp;

  DebugLogEntry(this.message, this.timestamp);
}

class DebugState {
  final bool isVisible;
  final List<DebugLogEntry> logEntries;

  const DebugState({
    this.isVisible = false,
    this.logEntries = const [],
  });

  DebugState copyWith({bool? isVisible, List<DebugLogEntry>? logEntries}) {
    return DebugState(
      isVisible: isVisible ?? this.isVisible,
      logEntries: logEntries ?? this.logEntries,
    );
  }
}

class DebugNotifier extends Notifier<DebugState> {
  StreamSubscription<String>? _logSubscription;

  @override
  DebugState build() {
    // Subscribe to AppLogger stream for NEW logs only
    _logSubscription = AppLogger.logStream.listen((logMessage) {
      // Add new log entry when it arrives
      _addLogMessage(logMessage);
    });

    // Clean up subscription when provider is disposed
    ref.onDispose(() {
      _logSubscription?.cancel();
    });

    // Start with empty state - logs will be loaded when overlay is opened
    return const DebugState();
  }

  void toggleVisibility() {
    final newVisibility = !state.isVisible;

    if (newVisibility) {
      // When opening, load all recent logs from AppLogger buffer (ONE TIME ONLY)
      final allLogs = AppLogger.recentLogs
          .map((msg) => DebugLogEntry(msg, DateTime.now()))
          .toList();

      // Debug: print how many logs we're loading
      print('DEBUG OVERLAY: Loading ${allLogs.length} logs from AppLogger buffer');
      if (allLogs.isNotEmpty) {
        print('DEBUG OVERLAY: First log: ${allLogs.first.message}');
      }

      state = state.copyWith(isVisible: true, logEntries: allLogs);
    } else {
      // When closing, keep messages but hide overlay
      state = state.copyWith(isVisible: false);
    }
  }

  void _addLogMessage(String logMessage) {
    // Only add if overlay is visible
    if (!state.isVisible) return;

    // Check if this message is already in the list (prevent duplicates)
    final isDuplicate = state.logEntries.any((entry) => entry.message == logMessage);
    if (isDuplicate) return;

    // Add new log at the top with current timestamp
    final newEntry = DebugLogEntry(logMessage, DateTime.now());
    final updatedEntries = [newEntry, ...state.logEntries];

    // Limit to 50 entries (last 50 lines)
    final limitedEntries = updatedEntries.length > 50
        ? updatedEntries.sublist(0, 50)
        : updatedEntries;

    state = state.copyWith(logEntries: limitedEntries);
  }

  void clearMessages() {
    state = state.copyWith(logEntries: []);
  }
}

final debugProvider = NotifierProvider<DebugNotifier, DebugState>(DebugNotifier.new);
