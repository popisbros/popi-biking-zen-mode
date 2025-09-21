import 'dart:io';

/// Secure configuration for API keys and sensitive data
/// This class loads configuration from environment variables or secure sources
class SecureConfig {
  // MapTiler API Key
  static String get mapTilerApiKey {
    // Try to get from environment variable first
    const envKey = String.fromEnvironment('MAPTILER_API_KEY');
    if (envKey.isNotEmpty && envKey != 'YOUR_MAPTILER_API_KEY_HERE') {
      return envKey;
    }
    
    // Fallback to the actual API key for development
    // This will be overridden by environment variables in production
    return '0n3hIGbHnipUHJE5pew7';
  }
  
  // Thunderforest API Key
  static String get thunderforestApiKey {
    // Try to get from environment variable first
    const envKey = String.fromEnvironment('THUNDERFOREST_API_KEY');
    if (envKey.isNotEmpty && envKey != 'YOUR_THUNDERFOREST_API_KEY_HERE') {
      return envKey;
    }
    
    // Fallback to the actual API key for development
    // This will be overridden by environment variables in production
    return '121a02b0d4754f5ca3d296c2cf0d97bb';
  }
  
  // LocationIQ API Key
  static String get locationIQApiKey {
    // Try to get from environment variable first
    const envKey = String.fromEnvironment('LOCATIONIQ_API_KEY');
    if (envKey.isNotEmpty && envKey != 'YOUR_LOCATIONIQ_API_KEY_HERE') {
      return envKey;
    }
    
    // Fallback to a default key for development
    // This will be overridden by environment variables in production
    return 'pk.1234567890abcdef';
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
