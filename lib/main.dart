import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with proper configuration
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Firebase initialization failed: $e');
  }
  
  runApp(const ProviderScope(child: PopiBikingApp()));
}

class PopiBikingApp extends StatelessWidget {
  const PopiBikingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Popi Is Biking Zen Mode',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MapScreen(),
    );
  }
}