import 'package:flutter/material.dart';

/// App color palette for Popi Is Biking Zen Mode
class AppColors {
  // Primary colors
  static const Color urbanBlue = Color(0xFF233749);
  static const Color mossGreen = Color(0xFF85A78B);
  static const Color signalYellow = Color(0xFFF4D35E);
  static const Color lightGrey = Color(0xFFECECEC);
  
  // Additional colors for cycling theme
  static const Color darkBlue = Color(0xFF1A2A3A);
  static const Color lightBlue = Color(0xFF3A4A5A);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color dangerRed = Color(0xFFF44336);
  
  // Map-specific colors
  static const Color bikeLaneBlue = Color(0xFF2196F3);
  static const Color azureBlue = Color(0xFF87CEEB); // Azure Blue for OSM POIs
  static const Color protectedPathGreen = Color(0xFF4CAF50);
  static const Color cyclewayPurple = Color(0xFF9C27B0);
  
  // UI colors
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color onBackground = Color(0xFF1A1A1A);
  
  // Gradient colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [urbanBlue, darkBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [mossGreen, successGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark theme colors
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF2A2A2A);
  static const Color darkOnSurface = Color(0xFFE0E0E0);
  static const Color darkOnBackground = Color(0xFFE0E0E0);
}

