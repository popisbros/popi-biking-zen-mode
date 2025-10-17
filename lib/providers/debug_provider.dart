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
  @override
  DebugState build() => const DebugState();

  void toggleVisibility() {
    final newVisibility = !state.isVisible;
    AppLogger.debug('Changing visibility', tag: 'DEBUG', data: {
      'from': state.isVisible,
      'to': newVisibility,
    });
    state = state.copyWith(
      isVisible: newVisibility,
      messages: state.isVisible ? '' : state.messages, // Clear when closing
    );
  }

  void addDebugMessage(String message) {
    AppLogger.debug('Called', tag: 'DEBUG', data: {
      'message': message,
      'isVisible': state.isVisible,
    });

    if (!state.isVisible) {
      AppLogger.debug('Skipped - overlay not visible', tag: 'DEBUG');
      return; // Only collect when sheet is open
    }

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final newMessage = '[$timestamp] $message\n';
    var updatedMessages = newMessage + state.messages;

    // Limit to 10,000 characters
    if (updatedMessages.length > 10000) {
      updatedMessages = updatedMessages.substring(0, 10000);
    }

    AppLogger.debug('Adding message', tag: 'DEBUG', data: {
      'currentLength': state.messages.length,
      'newLength': updatedMessages.length,
    });
    state = state.copyWith(messages: updatedMessages);
  }

  void clearMessages() {
    state = state.copyWith(messages: '');
  }
}

final debugProvider = NotifierProvider<DebugNotifier, DebugState>(DebugNotifier.new);
