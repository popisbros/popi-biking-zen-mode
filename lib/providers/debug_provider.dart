import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    state = state.copyWith(
      isVisible: !state.isVisible,
      messages: state.isVisible ? '' : state.messages, // Clear when closing
    );
  }

  void addDebugMessage(String message) {
    if (!state.isVisible) return; // Only collect when sheet is open

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final newMessage = '[$timestamp] $message\n';
    var updatedMessages = newMessage + state.messages;

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
