import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to manage visibility of user's favorites and destinations on the map
class FavoritesVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Enabled by default
    return true;
  }

  /// Toggle visibility
  void toggle() {
    state = !state;
  }

  /// Set visibility explicitly
  void setVisible(bool visible) {
    state = visible;
  }

  /// Disable (used when entering navigation mode)
  void disable() {
    state = false;
  }
}

/// Provider instance
final favoritesVisibilityProvider = NotifierProvider<FavoritesVisibilityNotifier, bool>(() {
  return FavoritesVisibilityNotifier();
});
