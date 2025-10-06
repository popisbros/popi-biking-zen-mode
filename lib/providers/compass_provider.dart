import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../utils/app_logger.dart';

/// Provider for compass heading (Native only, returns null on Web)
final compassHeadingProvider = StreamProvider<double?>((ref) {
  // Compass doesn't work on web
  if (kIsWeb) {
    AppLogger.debug('Web platform detected - compass not available', tag: 'COMPASS');
    return Stream.value(null);
  }

  AppLogger.debug('Setting up compass stream (Native)', tag: 'COMPASS');

  return FlutterCompass.events!.map((event) {
    final heading = event.heading;
    if (heading != null) {
      AppLogger.debug('Heading', tag: 'COMPASS', data: {
        'heading': '${heading.toStringAsFixed(1)}°',
      });
    }
    return heading;
  }).handleError((error) {
    AppLogger.error('Compass error', tag: 'COMPASS', error: error);
    return null;
  });
});

/// Notifier for managing compass state
class CompassNotifier extends Notifier<double?> {
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  double? build() {
    _initializeCompass();
    return null;
  }

  void _initializeCompass() {
    if (kIsWeb) {
      AppLogger.debug('Web platform - compass disabled', tag: 'COMPASS');
      return;
    }

    AppLogger.debug('Initializing compass', tag: 'COMPASS');

    _compassSubscription = FlutterCompass.events?.listen(
      (CompassEvent event) {
        final heading = event.heading;
        if (heading != null) {
          state = heading;
          AppLogger.debug('Updated heading', tag: 'COMPASS', data: {
            'heading': '${heading.toStringAsFixed(1)}°',
          });
        }
      },
      onError: (error) {
        AppLogger.error('Compass error', tag: 'COMPASS', error: error);
        state = null;
      },
      onDone: () {
        AppLogger.debug('Compass stream completed', tag: 'COMPASS');
      },
    );

    AppLogger.success('Compass initialized', tag: 'COMPASS');
  }

  void disposeCompass() {
    AppLogger.debug('Disposing compass', tag: 'COMPASS');
    _compassSubscription?.cancel();
  }
}

/// Provider for compass notifier
final compassNotifierProvider = NotifierProvider<CompassNotifier, double?>(CompassNotifier.new);
