import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/osm_poi_provider.dart';
import '../providers/community_provider.dart';
import '../utils/app_logger.dart';

/// Service for conditionally loading POI data only if cache is empty
///
/// Consolidates duplicate "loadIfNeeded" logic from map screens
class ConditionalPOILoader {
  /// Load OSM POIs only if data doesn't exist
  static Future<void> loadOSMPOIsIfNeeded({
    required WidgetRef ref,
    required BoundingBox extendedBounds,
    VoidCallback? onComplete,
  }) async {
    final osmPOIsNotifier = ref.read(osmPOIsNotifierProvider.notifier);
    final currentData = ref.read(osmPOIsNotifierProvider).value;

    if (currentData == null || currentData.isEmpty) {
      AppLogger.map('OSM POIs: No data, loading...');
      await osmPOIsNotifier.loadPOIsInBackground(extendedBounds);
      onComplete?.call();
    } else {
      AppLogger.map('OSM POIs: Data exists (${currentData.length} items), showing without reload');
      onComplete?.call();
    }
  }

  /// Load Warnings only if data doesn't exist
  static Future<void> loadWarningsIfNeeded({
    required WidgetRef ref,
    required BoundingBox extendedBounds,
    VoidCallback? onComplete,
  }) async {
    final warningsNotifier = ref.read(communityWarningsBoundsNotifierProvider.notifier);
    final currentData = ref.read(communityWarningsBoundsNotifierProvider).value;

    if (currentData == null || currentData.isEmpty) {
      AppLogger.map('Warnings: No data, loading...');
      await warningsNotifier.loadWarningsInBackground(extendedBounds);
      onComplete?.call();
    } else {
      AppLogger.map('Warnings: Data exists (${currentData.length} items), showing without reload');
      onComplete?.call();
    }
  }
}
