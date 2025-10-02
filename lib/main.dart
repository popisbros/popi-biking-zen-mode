import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'screens/map_screen.dart';

void main() async {
  // Catch all errors
  FlutterError.onError = (FlutterErrorDetails details) {
    print('❌ iOS DEBUG [FLUTTER ERROR]: ${details.exception}');
    print('❌ iOS DEBUG [STACK TRACE]: ${details.stack}');
    FlutterError.presentError(details);
  };

  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 iOS DEBUG [MAIN]: ========== App Starting ==========');
  print('🚀 iOS DEBUG [MAIN]: Platform: ${kIsWeb ? "WEB" : "MOBILE"}');
  print('🚀 iOS DEBUG [MAIN]: Timestamp: ${DateTime.now().toIso8601String()}');

  // Only initialize Firebase on mobile platforms (not web)
  if (!kIsWeb) {
    try {
      print('🔥 iOS DEBUG [MAIN]: Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ iOS DEBUG [MAIN]: Firebase initialized successfully');
    } catch (e, stackTrace) {
      print('❌ iOS DEBUG [MAIN]: Firebase initialization FAILED');
      print('❌ iOS DEBUG [MAIN]: Error: $e');
      print('❌ iOS DEBUG [MAIN]: Stack trace:');
      print(stackTrace.toString().split('\n').take(10).join('\n'));
      // Continue anyway - Firebase is not critical for map display
    }
  } else {
    print('⚠️ iOS DEBUG [MAIN]: Firebase disabled on web platform');
  }

  print('🚀 iOS DEBUG [MAIN]: Starting app with ProviderScope...');

  runApp(const ProviderScope(child: MyApp()));

  print('✅ iOS DEBUG [MAIN]: App started successfully');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('🎨 iOS DEBUG [MyApp]: Building MaterialApp...');
    return MaterialApp(
      title: 'Popi Biking',
      theme: AppTheme.lightTheme,
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        print('🎨 iOS DEBUG [MyApp]: MaterialApp builder called');
        // Add error boundary
        ErrorWidget.builder = (FlutterErrorDetails details) {
          print('❌ iOS DEBUG [ErrorWidget]: Error caught in widget tree');
          print('   Error: ${details.exception}');
          return Material(
            child: Container(
              color: Colors.white,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text(
                        'Application Error',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${details.exception}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Check the console logs for details',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        };
        return child ?? const Center(child: CircularProgressIndicator());
      },
    );
  }
}
