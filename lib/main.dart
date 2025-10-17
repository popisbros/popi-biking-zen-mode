import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'screens/map_screen.dart';
import 'screens/splash_screen.dart';
// Conditional import: Only import 3D Mapbox map on native platforms (iOS/Android)
// On Web, import stub that redirects to 2D map (Mapbox not supported on Web)
import 'screens/mapbox_map_screen_simple.dart'
    if (dart.library.html) 'screens/mapbox_map_screen_simple_stub.dart';
import 'utils/app_logger.dart';
import 'utils/api_logger.dart';
import 'services/toast_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style (status bar and navigation bar)
  // Use light grey matching splash screen background
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF1F1F1), // Light grey matching splash screen
      statusBarIconBrightness: Brightness.dark, // Dark icons on light background
      statusBarBrightness: Brightness.light, // For iOS
      systemNavigationBarColor: Color(0xFFF1F1F1), // Light grey for bottom nav bar
      systemNavigationBarIconBrightness: Brightness.dark, // Dark icons
    ),
  );

  AppLogger.separator('App Starting');
  AppLogger.info('Platform: ${kIsWeb ? "WEB" : "MOBILE"}');
  AppLogger.info('Timestamp: ${DateTime.now().toIso8601String()}');

  // Initialize Firebase on all platforms
  try {
    AppLogger.firebase('Initializing Firebase with 10s timeout');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        AppLogger.warning('Firebase initialization TIMED OUT after 10s', tag: 'FIREBASE');
        AppLogger.warning('Continuing without Firebase', tag: 'FIREBASE');
        throw TimeoutException('Firebase initialization timed out');
      },
    );
    AppLogger.success('Firebase initialized successfully', tag: 'FIREBASE', data: {
      'platform': kIsWeb ? "WEB" : "MOBILE",
    });

    // Initialize Firebase Crashlytics (only on native platforms, not web)
    if (!kIsWeb) {
      AppLogger.info('Initializing Firebase Crashlytics', tag: 'CRASHLYTICS');

      // Pass all uncaught "fatal" errors from the framework to Crashlytics
      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.error('Flutter error (sent to Crashlytics)', error: details.exception, stackTrace: details.stack);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };

      // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.error('Async error (sent to Crashlytics)', error: error, stackTrace: stack);
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      AppLogger.success('Crashlytics initialized successfully', tag: 'CRASHLYTICS');
    } else {
      AppLogger.info('Crashlytics skipped on web platform', tag: 'CRASHLYTICS');

      // Still log Flutter errors locally on web
      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.error('Flutter error', error: details.exception, stackTrace: details.stack);
        FlutterError.presentError(details);
      };
    }

    // Initialize log cleanup (runs on app startup)
    AppLogger.info('Initializing log cleanup (2h retention)', tag: 'FIREBASE');
    unawaited(ApiLogger.initializeLogCleanup(age: const Duration(hours: 2)));
  } catch (e, stackTrace) {
    AppLogger.error('Firebase initialization FAILED', tag: 'FIREBASE', error: e, stackTrace: stackTrace);
    AppLogger.warning('Continuing anyway - Firebase not critical for map display', tag: 'FIREBASE');
    // Continue anyway - Firebase is not critical for map display
  }

  AppLogger.info('Starting app with ProviderScope');

  runApp(const ProviderScope(child: MyApp()));

  AppLogger.success('App started successfully', tag: 'MAIN');
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppLogger.info('Building MaterialApp', tag: 'MyApp');

    // Web starts with 2D map, Native starts directly with 3D map
    AppLogger.info('Starting with ${kIsWeb ? "2D map (WEB)" : "3D map (NATIVE)"}', tag: 'MyApp');

    return MaterialApp(
      title: 'Popi Biking',
      theme: AppTheme.lightTheme,
      navigatorKey: ToastService.navigatorKey,
      home: SplashScreen(
        child: kIsWeb ? const MapScreen() : const MapboxMapScreenSimple(),
      ),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        AppLogger.debug('MaterialApp builder called', tag: 'MyApp');
        // Add error boundary
        ErrorWidget.builder = (FlutterErrorDetails details) {
          AppLogger.error('Error caught in widget tree', error: details.exception);
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

// NativeStartupScreen removed - app now starts directly in 3D map on Native
