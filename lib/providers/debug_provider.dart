import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_logger.dart';

class DebugState {
  final bool isVisible;
  final String messages;

  const DebugState({
    this.isVisible = false,
    this.messages = '',
  });

  DebugState copyWith({bool? isVisible, String? messages}) {
    return DebugState(
      isVisible: isVisible ?? this.isVisible,
      messages: messages ?? this.messages,
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
    final existingLogs = AppLogger.recentLogs.join('\n');

    return DebugState(messages: existingLogs);
  }

  void toggleVisibility() {
    final newVisibility = !state.isVisible;

    if (newVisibility) {
      // When opening, load all recent logs from AppLogger
      final allLogs = AppLogger.recentLogs.join('\n');
      state = state.copyWith(isVisible: true, messages: allLogs);
    } else {
      // When closing, keep messages but hide overlay
      state = state.copyWith(isVisible: false);
    }
  }

  void _addLogMessage(String logMessage) {
    if (!state.isVisible) return;

    // Add new log at the top
    var updatedMessages = '$logMessage\n${state.messages}';

    // Limit to 10,000 characters
    if (updatedMessages.length > 10000) {
      updatedMessages = updatedMessages.substring(0, 10000);
    }

    state = state.copyWith(messages: updatedMessages);
  }

  void clearMessages() {
    state = state.copyWith(messages: '');
  }
}

final debugProvider = NotifierProvider<DebugNotifier, DebugState>(DebugNotifier.new);
