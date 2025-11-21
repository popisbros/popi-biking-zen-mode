// Web-specific implementation for audio announcements
import 'dart:html' as html;
import 'dart:ui' as ui;
import '../utils/app_logger.dart';

/// Speak using Web Speech API
Future<dynamic> speakWeb(String message) async {
  try {
    final utterance = html.SpeechSynthesisUtterance(message);

    // Auto-detect device language for web
    final deviceLocale = ui.PlatformDispatcher.instance.locale;
    final languageCode = deviceLocale.languageCode;
    final countryCode = deviceLocale.countryCode;
    utterance.lang = countryCode != null ? '$languageCode-$countryCode' : languageCode;

    utterance.rate = 0.9; // Slightly slower than normal
    utterance.pitch = 1.0;
    utterance.volume = 1.0;

    html.window.speechSynthesis!.speak(utterance);
    return 1; // Success
  } catch (e) {
    AppLogger.error('Web Speech API error', tag: 'AUDIO', error: e);
    return 0; // Failure
  }
}

/// Stop web speech synthesis
void stopWeb() {
  try {
    html.window.speechSynthesis!.cancel();
  } catch (e) {
    AppLogger.error('Failed to stop web speech synthesis', tag: 'AUDIO', error: e);
  }
}
