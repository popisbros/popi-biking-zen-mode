// Stub implementation for non-web platforms (iOS/Android)
// These functions are never called on mobile platforms,
// but need to exist for conditional imports to work

/// Stub for web speak (never called on mobile)
Future<dynamic> speakWeb(String message) async {
  throw UnsupportedError('Web Speech API is only available on web platform');
}

/// Stub for web stop (never called on mobile)
void stopWeb() {
  throw UnsupportedError('Web Speech API is only available on web platform');
}
