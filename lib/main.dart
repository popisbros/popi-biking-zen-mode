import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'screens/map_screen.dart';
import 'screens/mapbox_map_screen_simple.dart';

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

  // Initialize Firebase on all platforms
  try {
    print('🔥 iOS DEBUG [MAIN]: Initializing Firebase with 10s timeout...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('⏱️ iOS DEBUG [MAIN]: Firebase initialization TIMED OUT after 10s');
        print('⚠️ iOS DEBUG [MAIN]: Continuing without Firebase...');
        throw TimeoutException('Firebase initialization timed out');
      },
    );
    print('✅ iOS DEBUG [MAIN]: Firebase initialized successfully on ${kIsWeb ? "WEB" : "MOBILE"}');
  } catch (e, stackTrace) {
    print('❌ iOS DEBUG [MAIN]: Firebase initialization FAILED');
    print('❌ iOS DEBUG [MAIN]: Error: $e');
    print('❌ iOS DEBUG [MAIN]: Error type: ${e.runtimeType}');
    print('❌ iOS DEBUG [MAIN]: Stack trace:');
    print(stackTrace.toString().split('\n').take(10).join('\n'));
    print('⚠️ iOS DEBUG [MAIN]: Continuing anyway - Firebase not critical for map display');
    // Continue anyway - Firebase is not critical for map display
  }

  print('🚀 iOS DEBUG [MAIN]: Starting app with ProviderScope...');

  runApp(const ProviderScope(child: MyApp()));

  print('✅ iOS DEBUG [MAIN]: App started successfully');
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    print('🎨 iOS DEBUG [MyApp]: Building MaterialApp...');

    // Always start with 2D map, but on Native we'll auto-navigate to 3D
    print('🎨 iOS DEBUG [MyApp]: Starting with 2D map (${kIsWeb ? "WEB" : "NATIVE will auto-navigate to 3D"})');

    return MaterialApp(
      title: 'Popi Biking',
      theme: AppTheme.lightTheme,
      home: kIsWeb ? const MapScreen() : const NativeStartupScreen(),
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

/// Startup screen for Native apps - navigates to 2D map which then auto-opens 3D
class NativeStartupScreen extends StatefulWidget {
  const NativeStartupScreen({super.key});

  @override
  State<NativeStartupScreen> createState() => _NativeStartupScreenState();
}

class _NativeStartupScreenState extends State<NativeStartupScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to 2D map immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🚀 iOS DEBUG [NativeStartup]: Navigating to 2D map...');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MapScreen(autoOpen3D: true),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
