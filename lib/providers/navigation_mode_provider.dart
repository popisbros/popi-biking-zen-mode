import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_logger.dart';

/// Navigation mode enum (renamed to avoid Flutter's NavigationMode conflict)
enum NavMode {
  exploration, // Static map, north-up, auto-center on 10m movement
  navigation,  // Rotating map, follows GPS direction, continuous tracking
}

/// Navigation mode state
class NavigationModeState {
  final NavMode mode;
  final bool isRouteActive; // True when a route is being followed

  const NavigationModeState({
    required this.mode,
    this.isRouteActive = false,
  });

  NavigationModeState copyWith({
    NavMode? mode,
    bool? isRouteActive,
  }) {
    return NavigationModeState(
      mode: mode ?? this.mode,
      isRouteActive: isRouteActive ?? this.isRouteActive,
    );
  }
}

/// Navigation mode notifier
class NavigationModeNotifier extends Notifier<NavigationModeState> {
  @override
  NavigationModeState build() {
    return const NavigationModeState(mode: NavMode.exploration);
  }

  /// Toggle between exploration and navigation modes
  void toggleMode() {
    final newMode = state.mode == NavMode.exploration
        ? NavMode.navigation
        : NavMode.exploration;

    state = state.copyWith(mode: newMode);

    AppLogger.map('Navigation mode switched', data: {
      'mode': newMode.name,
      'routeActive': state.isRouteActive,
    });
  }

  /// Set navigation mode explicitly
  void setMode(NavMode mode) {
    if (state.mode == mode) return;

    state = state.copyWith(mode: mode);

    AppLogger.map('Navigation mode set', data: {
      'mode': mode.name,
      'routeActive': state.isRouteActive,
    });
  }

  /// Activate navigation mode when route starts
  void startRouteNavigation() {
    state = state.copyWith(
      mode: NavMode.navigation,
      isRouteActive: true,
    );
  }

  /// Stop route navigation and return to exploration mode
  void stopRouteNavigation() {
    state = state.copyWith(
      mode: NavMode.exploration,
      isRouteActive: false,
    );

    AppLogger.map('Route navigation stopped');
  }
}

/// Provider for navigation mode
final navigationModeProvider = NotifierProvider<NavigationModeNotifier, NavigationModeState>(
  NavigationModeNotifier.new,
);
