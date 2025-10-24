import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/routing_provider.dart';
import '../utils/app_logger.dart';

/// Notifier for managing the selected routing provider
class RoutingProviderNotifier extends Notifier<RoutingProvider> {
  static const String _storageKey = 'routing_provider';

  @override
  RoutingProvider build() {
    _loadFromPreferences();
    return RoutingProvider.graphhopper; // Default
  }

  /// Load saved provider from shared preferences
  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProvider = prefs.getString(_storageKey);

      if (savedProvider != null) {
        final provider = RoutingProviderExtension.fromStorageString(savedProvider);
        AppLogger.debug('Loaded routing provider from preferences', tag: 'ROUTING', data: {
          'provider': provider.displayName,
        });
        state = provider;
      }
    } catch (e) {
      AppLogger.error('Failed to load routing provider from preferences', tag: 'ROUTING', error: e);
    }
  }

  /// Set the routing provider and persist to preferences
  Future<void> setProvider(RoutingProvider provider) async {
    AppLogger.debug('Setting routing provider', tag: 'ROUTING', data: {
      'provider': provider.displayName,
    });

    state = provider;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, provider.toStorageString());
      AppLogger.success('Saved routing provider to preferences', tag: 'ROUTING');
    } catch (e) {
      AppLogger.error('Failed to save routing provider to preferences', tag: 'ROUTING', error: e);
    }
  }
}

/// Provider for routing provider state
final routingProviderProvider = NotifierProvider<RoutingProviderNotifier, RoutingProvider>(
  RoutingProviderNotifier.new,
);
