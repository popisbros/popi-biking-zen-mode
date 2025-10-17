# 📝 Logging Guide - How to View AppLogger Logs

## Overview

After replacing `print()` statements with `AppLogger`, logs will appear in different places depending on the platform and how you're running the app.

**Important:** `AppLogger` only logs in **DEBUG mode**. In RELEASE builds, all logs are completely removed (zero overhead).

---

## 🖥️ **Desktop (macOS Development)**

### **1. Terminal / Command Line**

When running via terminal, logs appear directly in stdout:

```bash
# Run in debug mode (logs enabled)
flutter run

# Run in release mode (logs disabled)
flutter run --release
```

**Example Output:**
```
[14:23:45.123] 🗺️ [MAP] Calculating multiple routes | from: 48.8566,2.3522, to: 48.8584,2.2945
[14:23:45.456] 📍 [LOCATION] GPS update received | lat: 48.8566, lon: 2.3522, accuracy: 5.0
[14:23:46.789] ✅ [SUCCESS] Route calculated | distance: 4.2km, duration: 12min
```

### **2. VS Code / IDE**

If running from VS Code, logs appear in the **DEBUG CONSOLE** panel:

1. View → Debug Console (or `⌘+Shift+Y`)
2. Logs appear with timestamp and emoji icons
3. Use search/filter to find specific logs

### **3. Android Studio / IntelliJ**

Logs appear in the **Run** tab at the bottom:

1. Click the **Run** tab
2. Logs appear with colored output
3. Use filter box to search

---

## 📱 **Mobile Web (PWA/Browser)**

### **1. Chrome DevTools**

When running web version:

```bash
flutter run -d chrome
```

**View Logs:**
1. Open Chrome DevTools: `⌘+Option+I` (Mac) or `F12` (Windows/Linux)
2. Click **Console** tab
3. Logs appear with emoji icons and timestamps

**Example:**
```
[14:23:45.123] 🗺️ [MAP] Calculating multiple routes | from: 48.8566,2.3522, to: 48.8584,2.2945
```

**Filter Logs:**
- Type keywords in the filter box (e.g., "MAP", "LOCATION", "ERROR")
- Use DevTools filter levels: All / Errors / Warnings / Info / Verbose

### **2. Safari Web Inspector (for PWA)**

If testing PWA in Safari:

1. Safari → Develop → Show Web Inspector (`⌘+Option+I`)
2. Click **Console** tab
3. Logs appear there

### **3. Firefox Developer Tools**

1. Open Developer Tools: `⌘+Option+I`
2. Console tab
3. Logs appear with emoji icons

---

## 📱 **Mobile Native (iOS)**

### **1. Xcode Console (When Running from Xcode)**

When running from Xcode:

1. Show debug area: `⌘+Shift+Y`
2. Logs appear in the **Console** pane at bottom
3. Use filter box to search

**Example:**
```
[14:23:45.123] 🗺️ [MAP] Calculating multiple routes | from: 48.8566,2.3522, to: 48.8584,2.2945
```

### **2. Terminal with flutter run**

When running via terminal:

```bash
# Run on your iPhone
./run_ios_device.sh

# Or manually
flutter run --release -d 00008103-000908642279001E
```

**Logs appear directly in terminal** with emoji icons and timestamps.

### **3. Console.app (macOS Built-in)**

For viewing logs from a release build or installed app:

1. Open **Console.app** (in Applications/Utilities)
2. Connect your iPhone via USB
3. Select your device in the left sidebar
4. Type your app name or bundle ID in search: `com.popibiking.popiBikingFresh`
5. Logs appear in real-time

**Note:** Only works if app is in DEBUG mode. Release builds have all logs removed.

### **4. iPhone Settings → Analytics (Crash Logs Only)**

For crash logs (not regular logs):

1. Settings → Privacy & Security → Analytics & Improvements
2. Analytics Data
3. Find your app logs

**Note:** This only shows crash logs, not AppLogger output.

---

## 📱 **Mobile Native (Android)**

### **1. Terminal with flutter run**

```bash
flutter run -d <android-device-id>
```

Logs appear in terminal.

### **2. Android Studio Logcat**

1. View → Tool Windows → Logcat
2. Filter by package: `com.popibiking.popiBikingFresh`
3. Logs appear with emoji icons

### **3. adb logcat (Command Line)**

```bash
# View all logs
adb logcat

# Filter by tag
adb logcat | grep "flutter"

# Filter by your app
adb logcat | grep "popibiking"
```

---

## 🎯 **Log Levels and Icons**

### **AppLogger Methods:**

| Method | Icon | Tag | Use Case |
|--------|------|-----|----------|
| `AppLogger.info()` | ℹ️ | INFO | General information |
| `AppLogger.debug()` | 🔍 | DEBUG | Detailed debugging |
| `AppLogger.warning()` | ⚠️ | WARNING | Potential issues |
| `AppLogger.error()` | ❌ | ERROR | Errors and exceptions |
| `AppLogger.success()` | ✅ | SUCCESS | Successful operations |
| `AppLogger.map()` | 🗺️ | MAP | Map-related logs |
| `AppLogger.location()` | 📍 | LOCATION | Location/GPS logs |
| `AppLogger.firebase()` | 🔥 | FIREBASE | Firebase operations |
| `AppLogger.api()` | 🌐 | API | API/Network calls |
| `AppLogger.ios()` | 🔍 | iOS DEBUG | iOS-specific logs |

---

## 🔍 **Filtering and Searching Logs**

### **By Tag:**
```
Search for: "[MAP]"        → Shows all map-related logs
Search for: "[LOCATION]"   → Shows all location logs
Search for: "[ERROR]"      → Shows all errors
```

### **By Icon:**
```
Search for: "🗺️"   → Map logs
Search for: "📍"   → Location logs
Search for: "❌"   → Errors
Search for: "✅"   → Success logs
```

### **By Keyword:**
```
Search for: "route"        → All route-related logs
Search for: "GPS"          → All GPS logs
Search for: "Failed"       → Failure messages
```

---

## 📊 **Log Format**

All AppLogger logs follow this format:

```
[HH:mm:ss.mmm] ICON [TAG] Message | key1: value1, key2: value2
```

**Example:**
```
[14:23:45.123] 🗺️ [MAP] Calculating route | from: 48.8566,2.3522, to: 48.8584,2.2945, profile: balanced
[14:23:45.456] 📍 [LOCATION] GPS update | lat: 48.8566, lon: 2.3522, accuracy: 5.0
[14:23:46.789] ❌ [ERROR] API request failed | endpoint: /route, status: 500
  ↳ Error: Connection timeout
  ↳ Stack: ...
```

---

## 🚀 **Quick Reference by Platform**

| Platform | How to View Logs |
|----------|------------------|
| **Desktop Dev** | Terminal where you ran `flutter run` |
| **Web (Chrome)** | Chrome DevTools → Console (`⌘+Option+I`) |
| **Web (Safari)** | Safari → Develop → Web Inspector → Console |
| **iOS (Terminal)** | Terminal where you ran `./run_ios_device.sh` |
| **iOS (Xcode)** | Xcode → Debug Area → Console (`⌘+Shift+Y`) |
| **iOS (Console.app)** | Console.app → Select device → Filter by app |
| **Android (Terminal)** | Terminal where you ran `flutter run` |
| **Android (Studio)** | Android Studio → Logcat |
| **Android (adb)** | `adb logcat \| grep flutter` |

---

## ⚠️ **Important Notes**

### **1. Debug vs Release Mode**

```dart
// DEBUG mode (development)
flutter run                    // ✅ Logs visible
./run_ios_device.sh            // ⚠️ Runs in --release (logs hidden)

// RELEASE mode (production)
flutter run --release          // ❌ All logs removed (zero overhead)
flutter build ios              // ❌ All logs removed
```

**Why?** `AppLogger` uses `if (kDebugMode)` which is completely removed during release compilation.

### **2. Release Builds Have NO Logs**

For production builds, you need:
- Firebase Crashlytics for crash reporting
- Analytics for user behavior
- Remote logging service (if needed)

AppLogger is intentionally removed in release for performance.

### **3. Viewing Logs on Your iPhone (Debug Build)**

To see logs on your iPhone in real-time:

```bash
# Option 1: Run with terminal connected
./run_ios_device.sh
# Logs appear in terminal

# Option 2: Use Xcode
open ios/Runner.xcworkspace
# Run from Xcode, logs appear in Xcode console
```

---

## 💡 **Pro Tips**

### **1. Use Descriptive Tags**

```dart
// Good
AppLogger.map('Route calculated', data: {'distance': '4.2km'});

// Better - easy to search
AppLogger.map('ROUTE_CALC_SUCCESS', data: {'distance': 4.2, 'duration': 720});
```

### **2. Use Data Parameter**

```dart
// Instead of string concatenation:
AppLogger.debug('User: $userId, Status: $status');

// Better:
AppLogger.debug('User status changed', data: {
  'userId': userId,
  'status': status,
  'timestamp': DateTime.now().toString(),
});
```

### **3. Use Separators for Clarity**

```dart
AppLogger.separator('NAVIGATION SESSION');
AppLogger.map('Starting navigation');
// ... many logs ...
AppLogger.separator();
```

### **4. Performance Timing**

```dart
final timer = AppLogger.startTimer('Route calculation');
// ... do work ...
AppLogger.endTimer(timer, 'Route calculation');
// Output: ⚡ Finished: Route calculation (42ms)
```

---

## 🎓 **Examples**

### **Before (print):**
```dart
print('[MAP] Calculating multiple routes');
print('[LOCATION] GPS update: ${location.latitude}, ${location.longitude}');
print('[ERROR] Failed to load route: $error');
```

### **After (AppLogger):**
```dart
AppLogger.map('Calculating multiple routes');
AppLogger.location('GPS update', data: {
  'lat': location.latitude,
  'lon': location.longitude,
  'accuracy': location.accuracy,
});
AppLogger.error('Failed to load route', error: error, stackTrace: stackTrace);
```

### **Viewing:**
```
[14:23:45.123] 🗺️ [MAP] Calculating multiple routes
[14:23:45.456] 📍 [LOCATION] GPS update | lat: 48.8566, lon: 2.3522, accuracy: 5.0
[14:23:46.789] ❌ [ERROR] Failed to load route
  ↳ Error: Connection timeout
  ↳ Stack: #0 RoutingService.fetchRoute...
```

---

## 📚 **Summary**

**To view logs after switching to AppLogger:**

1. **Development (any platform):** Run `flutter run` (debug mode) → Logs appear in terminal/console
2. **iOS Device:** Run `./run_ios_device.sh` → Logs appear in terminal
3. **Web:** Chrome DevTools → Console tab
4. **Xcode:** Debug Area → Console pane

**Production:** Use Firebase Crashlytics (not AppLogger)

---

Need help? Check `lib/utils/app_logger.dart` for all available methods.
