import 'package:flutter/material.dart';

/// Helper class for responsive layouts and orientation handling
class ResponsiveHelper {
  /// Check if device is in landscape mode
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Check if device is in portrait mode
  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  /// Get screen width
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Get screen height
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// Check if screen is small (phone)
  static bool isSmallScreen(BuildContext context) {
    return screenWidth(context) < 600;
  }

  /// Check if screen is medium (tablet)
  static bool isMediumScreen(BuildContext context) {
    final width = screenWidth(context);
    return width >= 600 && width < 1200;
  }

  /// Check if screen is large (desktop)
  static bool isLargeScreen(BuildContext context) {
    return screenWidth(context) >= 1200;
  }

  /// Get responsive value based on screen size
  /// Usage: ResponsiveHelper.responsive(context, mobile: 16, tablet: 20, desktop: 24)
  static T responsive<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isLargeScreen(context)) {
      return desktop ?? tablet ?? mobile;
    } else if (isMediumScreen(context)) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
  }

  /// Get responsive padding based on orientation
  static EdgeInsets responsivePadding(BuildContext context) {
    if (isLandscape(context)) {
      // Landscape: More horizontal padding, less vertical
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 8);
    } else {
      // Portrait: Balanced padding
      return const EdgeInsets.all(16);
    }
  }

  /// Get button size based on screen size
  static double buttonSize(BuildContext context) {
    return responsive(
      context,
      mobile: 48.0,
      tablet: 56.0,
      desktop: 64.0,
    );
  }

  /// Get spacing value based on screen size
  static double spacing(BuildContext context, {double factor = 1.0}) {
    final baseSpacing = responsive(
      context,
      mobile: 8.0,
      tablet: 12.0,
      desktop: 16.0,
    );
    return baseSpacing * factor;
  }
}
