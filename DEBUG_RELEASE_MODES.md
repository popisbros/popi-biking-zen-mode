# Debug vs Release Build Modes

This app uses `AppLogger` for intelligent logging that is **completely removed** in release builds for maximum performance.

## 🐛 Debug Mode (Development)

Debug mode includes:
- All console logs via `AppLogger`
- Hot reload support
- Detailed error messages
- Debug banners
- **2-5x slower than release mode**

### Run in Debug Mode

**iOS:**
```bash
flutter run
```

**Web:**
```bash
flutter run -d chrome
```

**Android:**
```bash
flutter run
```

## 🚀 Release Mode (Production)

Release mode includes:
- **Zero logging overhead** (all AppLogger calls removed by tree-shaking)
- **2-5x faster performance**
- Optimized bundle size
- No debug banners
- Compiled/minified code

### Build in Release Mode

**iOS (Simulator - for testing):**
```bash
flutter run --release
```

**iOS (Device - full release build):**
```bash
flutter build ios --release
# Then open ios/Runner.xcworkspace in Xcode and run
```

**Web:**
```bash
flutter build web --release
```

**Android:**
```bash
flutter build apk --release
# or for app bundle:
flutter build appbundle --release
```

## ⚡ Profile Mode (Performance Testing)

Profile mode is a middle ground - optimized like release but with profiling tools enabled.

```bash
flutter run --profile
```

Use this to:
- Test performance
- Use Flutter DevTools
- Profile CPU/memory usage
- Measure frame rates

## 📊 AppLogger Usage

The app uses a custom `AppLogger` utility instead of `print()`:

```dart
import '../utils/app_logger.dart';

// General logs
AppLogger.info('User logged in');
AppLogger.debug('Processing data', data: {'count': 42});
AppLogger.success('Operation completed');
AppLogger.warning('Low battery');
AppLogger.error('Failed to save', error: e, stackTrace: st);

// Domain-specific logs
AppLogger.map('Map initialized');
AppLogger.location('GPS position updated');
AppLogger.firebase('Document saved to Firestore');
AppLogger.api('OSM API response received');

// Performance timing
final timer = AppLogger.startTimer('Load POIs');
// ... do work ...
AppLogger.endTimer(timer, 'Load POIs');

// Section separators
AppLogger.separator('Map Initialization');
```

### How It Works

**In Debug Mode:**
- All logs print to console with emojis and formatting
- Example: `[12:34:56.789] 🗺️ [MAP] Map initialized | zoom: 15, center: 48.8566,2.3522`

**In Release Mode:**
- All `AppLogger` calls are **completely removed** at compile time
- Zero runtime overhead
- No console output
- Optimized bundle size

This is achieved through Flutter's `kDebugMode` constant and tree-shaking optimization.

## 🎯 Performance Impact

### Before (with print statements)
- **377 print() calls** throughout the app
- Each print() call has overhead even in release mode
- Slows down critical paths (location updates, map rendering, POI loading)

### After (with AppLogger)
- **0 logging overhead** in release builds
- All logging code removed at compile time
- Significantly faster iOS app experience

## 📱 Testing Performance

Always test performance in **release mode** or **profile mode**, never debug mode:

```bash
# iOS
flutter run --release

# Web
flutter run -d chrome --release

# Profile mode (with DevTools)
flutter run --profile
```

## 🔍 Debugging Tips

1. **Use debug mode for development**: `flutter run`
2. **Check performance in release mode**: `flutter run --release`
3. **Profile with profile mode**: `flutter run --profile`
4. **View logs**: Look for emoji icons in console:
   - 🗺️ Map operations
   - 📍 Location updates
   - 🔥 Firebase operations
   - 🌐 API calls
   - ✅ Success
   - ❌ Errors
   - ⚠️ Warnings

## 📦 Files Updated

The following files now use `AppLogger` instead of `print()`:

**Core Performance Files:**
- `lib/providers/location_provider.dart` - Location tracking
- `lib/services/location_service.dart` - GPS service
- `lib/screens/mapbox_map_screen_simple.dart` - 3D map
- `lib/screens/map_screen.dart` - 2D map
- `lib/providers/compass_provider.dart` - Compass
- `lib/main.dart` - App startup

**Data & API Files:**
- `lib/providers/osm_poi_provider.dart` - OSM POI provider
- `lib/providers/community_provider.dart` - Community data
- `lib/services/firebase_service.dart` - Firebase operations
- `lib/services/osm_service.dart` - OSM API

**Utility Files:**
- `lib/utils/poi_icons.dart` - Icon resolution

## 🚦 Build Checklist

Before releasing to production:

- [ ] Test in release mode: `flutter run --release`
- [ ] Verify no console logs in release build
- [ ] Check app performance on real iOS device
- [ ] Test with Flutter DevTools in profile mode
- [ ] Build final release: `flutter build ios --release`
