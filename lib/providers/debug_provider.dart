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
    // Subscribe to AppLogger stream
    _logSubscription = AppLogger.logStream.listen((logMessage) {
      if (state.isVisible) {
        _addLogMessage(logMessage);
      }
    });

    // Clean up subscription when provider is disposed
    ref.onDispose(() {
      _logSubscription?.cancel();
    });

    // Load existing logs from AppLogger buffer
    final existingLogs = AppLogger.recentLogs
        .map((msg) => DebugLogEntry(msg, DateTime.now()))
        .toList();

    return DebugState(logEntries: existingLogs);
  }

  void toggleVisibility() {
    final newVisibility = !state.isVisible;

    if (newVisibility) {
      // When opening, load all recent logs from AppLogger
      final allLogs = AppLogger.recentLogs
          .map((msg) => DebugLogEntry(msg, DateTime.now()))
          .toList();
      state = state.copyWith(isVisible: true, logEntries: allLogs);
    } else {
      // When closing, keep messages but hide overlay
      state = state.copyWith(isVisible: false);
    }
  }

  void _addLogMessage(String logMessage) {
    if (!state.isVisible) return;

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
