import 'dart:io';

/// Secure configuration for API keys and sensitive data
/// This class loads configuration from environment variables or secure sources
class SecureConfig {
  // MapTiler API Key
  static String get mapTilerApiKey {
    // Try to get from environment variable first
    const envKey = String.fromEnvironment('MAPTILER_API_KEY');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    
    // Fallback to a placeholder for development
    // In production, this should always be set via environment variables
    return 'YOUR_MAPTILER_API_KEY_HERE';
  }
  
  // Firebase Configuration
  static String get firebaseApiKey {
    const envKey = String.fromEnvironment('FIREBASE_API_KEY');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    return 'YOUR_FIREBASE_API_KEY_HERE';
  }
  
  static String get firebaseProjectId {
    const envKey = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    return 'YOUR_FIREBASE_PROJECT_ID_HERE';
  }
  
  static String get firebaseAuthDomain {
    const envKey = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    return 'YOUR_FIREBASE_AUTH_DOMAIN_HERE';
  }
  
  static String get firebaseStorageBucket {
    const envKey = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    return 'YOUR_FIREBASE_STORAGE_BUCKET_HERE';
  }
  
  static String get firebaseMessagingSenderId {
    const envKey = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    return 'YOUR_FIREBASE_MESSAGING_SENDER_ID_HERE';
  }
  
  static String get firebaseAppId {
    const envKey = String.fromEnvironment('FIREBASE_APP_ID');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    return 'YOUR_FIREBASE_APP_ID_HERE';
  }
  
  // Check if we're in development mode
  static bool get isDevelopment {
    return const String.fromEnvironment('FLUTTER_ENV') == 'development' ||
           const bool.fromEnvironment('dart.vm.product') == false;
  }
  
  // Check if we're in production mode
  static bool get isProduction {
    return const String.fromEnvironment('FLUTTER_ENV') == 'production' ||
           const bool.fromEnvironment('dart.vm.product') == true;
  }
}
