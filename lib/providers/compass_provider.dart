import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Provider for compass heading (Native only, returns null on Web)
final compassHeadingProvider = StreamProvider<double?>((ref) {
  // Compass doesn't work on web
  if (kIsWeb) {
    print('🧭 DEBUG [Compass]: Web platform detected - compass not available');
    return Stream.value(null);
  }

  print('🧭 DEBUG [Compass]: Setting up compass stream (Native)');

  return FlutterCompass.events!.map((event) {
    final heading = event.heading;
    if (heading != null) {
      print('🧭 DEBUG [Compass]: Heading = ${heading.toStringAsFixed(1)}°');
    }
    return heading;
  }).handleError((error) {
    print('❌ DEBUG [Compass]: Error: $error');
    return null;
  });
});

/// Notifier for managing compass state
class CompassNotifier extends StateNotifier<double?> {
  StreamSubscription<CompassEvent>? _compassSubscription;

  CompassNotifier() : super(null) {
    _initializeCompass();
  }

  void _initializeCompass() {
    if (kIsWeb) {
      print('🧭 DEBUG [CompassNotifier]: Web platform - compass disabled');
      return;
    }

    print('🧭 DEBUG [CompassNotifier]: Initializing compass...');

    _compassSubscription = FlutterCompass.events?.listen(
      (CompassEvent event) {
        final heading = event.heading;
        if (heading != null) {
          state = heading;
          print('🧭 DEBUG [CompassNotifier]: Updated heading = ${heading.toStringAsFixed(1)}°');
        }
      },
      onError: (error) {
        print('❌ DEBUG [CompassNotifier]: Compass error: $error');
        state = null;
      },
      onDone: () {
        print('🧭 DEBUG [CompassNotifier]: Compass stream completed');
      },
    );

    print('✅ DEBUG [CompassNotifier]: Compass initialized');
  }

  @override
  void dispose() {
    print('🗑️ DEBUG [CompassNotifier]: Disposing...');
    _compassSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for compass notifier
final compassNotifierProvider = StateNotifierProvider<CompassNotifier, double?>((ref) {
  print('🧭 DEBUG [Provider]: Creating CompassNotifier instance');
  return CompassNotifier();
});
