import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a single log entry
class LogEntry {
  final String icon;
  final String tag;
  final String message;
  final String timestamp;
  final LogLevel level;
  final Map<String, dynamic>? data;

  const LogEntry({
    required this.icon,
    required this.tag,
    required this.message,
    required this.timestamp,
    required this.level,
    this.data,
  });

  Color get color {
    switch (level) {
      case LogLevel.error:
        return Colors.red;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.success:
        return Colors.green;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.map:
        return Colors.purple;
      case LogLevel.location:
        return Colors.teal;
      case LogLevel.firebase:
        return Colors.deepOrange;
      case LogLevel.api:
        return Colors.indigo;
    }
  }
}

/// Log levels matching AppLogger
enum LogLevel {
  info,
  debug,
  warning,
  error,
  success,
  map,
  location,
  firebase,
  api,
}

class DebugState {
  final bool isVisible;
  final List<LogEntry> logs;

  const DebugState({
    this.isVisible = false,
    this.logs = const [],
  });

  DebugState copyWith({bool? isVisible, List<LogEntry>? logs}) {
    return DebugState(
      isVisible: isVisible ?? this.isVisible,
      logs: logs ?? this.logs,
    );
  }
}

class DebugNotifier extends Notifier<DebugState> {
  static const int _maxLogs = 100; // Keep last 100 logs

  @override
  DebugState build() => const DebugState();

  void toggleVisibility() {
    final newVisibility = !state.isVisible;
    state = state.copyWith(isVisible: newVisibility);
  }

  void addLog({
    required String icon,
    required String tag,
    required String message,
    required LogLevel level,
    Map<String, dynamic>? data,
  }) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    final entry = LogEntry(
      icon: icon,
      tag: tag,
      message: message,
      timestamp: timestamp,
      level: level,
      data: data,
    );

    final updatedLogs = [entry, ...state.logs];

    // Keep only last N logs
    final trimmedLogs = updatedLogs.length > _maxLogs
        ? updatedLogs.sublist(0, _maxLogs)
        : updatedLogs;

    state = state.copyWith(logs: trimmedLogs);
  }

  void clearLogs() {
    state = state.copyWith(logs: []);
  }

  // Legacy method for backward compatibility
  void addDebugMessage(String message) {
    addLog(
      icon: '🔍',
      tag: 'DEBUG',
      message: message,
      level: LogLevel.debug,
    );
  }
}

final debugProvider = NotifierProvider<DebugNotifier, DebugState>(DebugNotifier.new);
