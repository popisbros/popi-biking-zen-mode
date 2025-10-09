# Mapbox Navigation SDK iOS Integration Plan

**Version:** v3.0.0-dev
**Started:** 2025-10-09
**Safe Rollback Point:** v2.0.0 (commit: 9994cec)

---

## 🎯 PROJECT GOAL

Integrate native iOS Mapbox Navigation SDK for professional turn-by-turn navigation while keeping all existing Flutter features for map exploration, POIs, warnings, and route planning.

---

## 📊 CURRENT STATE (v2.0.0)

### What We Have
- 2D map (OpenStreetMap/Thunderforest) + 3D map (Mapbox)
- GraphHopper routing with fastest/safest options
- OSM POIs, Community POIs, Community Warnings
- LocationIQ search
- Custom route visualization
- GPS tracking with navigation mode
- Debug overlay system
- Smart toggle loading
- All features work on iOS, Android, Web

### What's Missing
- ❌ Voice turn-by-turn guidance
- ❌ Lane guidance
- ❌ Speed limits display
- ❌ Automatic rerouting
- ❌ Real-time traffic avoidance

---

## 🏗️ ARCHITECTURE DESIGN

```
┌─────────────────────────────────────────────────────────────┐
│                    FLUTTER APP (Dart)                        │
├─────────────────────────────────────────────────────────────┤
│  Map Exploration Mode (v2.0.0 features)                     │
│  ├─ 2D/3D Maps                                              │
│  ├─ Search, POIs, Warnings                                  │
│  ├─ GraphHopper route calculation                           │
│  └─ "Start Navigation" button (iOS only)                    │
│                         │                                    │
│                         ▼                                    │
│                  MethodChannel                               │
│                         │                                    │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                         ▼                                    │
│                 iOS NATIVE MODULE (Swift)                    │
├─────────────────────────────────────────────────────────────┤
│  Navigation Mode (Full Screen)                              │
│  ├─ NavigationViewController (Mapbox)                       │
│  ├─ Voice guidance (Siri voices)                            │
│  ├─ Lane guidance                                            │
│  ├─ Speed limits                                             │
│  ├─ Automatic rerouting                                      │
│  └─ Traffic avoidance                                        │
│                         │                                    │
│                         ▼                                    │
│              Navigation Events                               │
│              (arrival, cancel, error)                        │
│                         │                                    │
└─────────────────────────┼───────────────────────────────────┘
                          │
                          ▼
               Return to Flutter Map
```

---

## ⚖️ GAINS VS LOSSES

### ✅ WHAT WE GAIN

**Professional Navigation (iOS only)**
- ✅ Voice guidance with Siri quality
- ✅ Lane guidance (visual + voice)
- ✅ Speed limits display
- ✅ Automatic rerouting when off-track
- ✅ Real-time traffic avoidance
- ✅ Battery-optimized native code
- ✅ Production-ready UI
- ✅ Accessibility (VoiceOver)
- ✅ Day/night mode automatic
- ✅ Future: CarPlay support possible

### ❌ WHAT WE LOSE (During Active Navigation Only)

**Custom Features During Navigation**
- ❌ OSM POIs not visible in native UI
- ❌ Community POIs not visible in native UI
- ❌ Community Warnings not visible in native UI
- ❌ Debug overlay not available
- ❌ Custom map styles (limited to Mapbox)

**Cross-Platform Consistency**
- ❌ iOS gets native nav, Android/Web don't (yet)
- ❌ Different UX for iOS users

**Control & Flexibility**
- ❌ Limited UI customization in native view
- ❌ Can't show custom data during navigation
- ❌ Must maintain Swift code

### ⚠️ IMPORTANT CLARIFICATIONS

1. **GraphHopper is KEPT** - Calculate routes in Flutter, convert to Mapbox format
2. **Your map is KEPT** - Exploration in Flutter, navigation in native
3. **POIs/Warnings KEPT** - Visible during planning, just not during active navigation
4. **Android can come later** - Start with iOS, add Android if successful

---

## 🧪 IMPLEMENTATION PHASES

### **PHASE 1: Platform Channel Setup (Day 1)**
**Goal:** Prove Flutter ↔ iOS communication works

#### Step 1.1: Create MethodChannel (30 mins)
**Files to modify:**
- `ios/Runner/AppDelegate.swift`
- Create: `lib/services/ios_navigation_service.dart`

**Implementation:**
```swift
// ios/Runner/AppDelegate.swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var navigationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    navigationChannel = FlutterMethodChannel(
      name: "com.popi.biking/navigation",
      binaryMessenger: controller.binaryMessenger
    )

    navigationChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startNavigation":
      result("Navigation not implemented yet")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

```dart
// lib/services/ios_navigation_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../utils/app_logger.dart';

class IOSNavigationService {
  static const _channel = MethodChannel('com.popi.biking/navigation');

  /// Check if native navigation is available (iOS only)
  static bool get isAvailable => Platform.isIOS;

  /// Start native navigation with given route
  Future<void> startNavigation({
    required List<LatLng> routePoints,
    required String destinationName,
  }) async {
    if (!isAvailable) {
      AppLogger.warning('Native navigation only available on iOS', tag: 'NAV');
      return;
    }

    try {
      AppLogger.map('Starting iOS native navigation', data: {
        'points': routePoints.length,
        'destination': destinationName,
      });

      final result = await _channel.invokeMethod('startNavigation', {
        'points': routePoints.map((p) => {
          'latitude': p.latitude,
          'longitude': p.longitude,
        }).toList(),
        'destination': destinationName,
      });

      AppLogger.success('Navigation started: $result', tag: 'NAV');
    } on PlatformException catch (e) {
      AppLogger.error('Navigation platform error', error: e, tag: 'NAV');
      rethrow;
    } catch (e) {
      AppLogger.error('Navigation error', error: e, tag: 'NAV');
      rethrow;
    }
  }
}
```

**Test:**
- Add test button to map screen
- Call `startNavigation()` with dummy coordinates
- Verify console shows "Navigation not implemented yet"

**✅ Success Criteria:**
- No build errors
- Button tap triggers iOS code
- Console shows expected message
- No crashes

**STOP HERE - WAIT FOR USER CONFIRMATION**

---

#### Step 1.2: Pass Route Data (30 mins)
**Files to modify:**
- `ios/Runner/AppDelegate.swift` (update handleMethodCall)
- Test with real GraphHopper route

**Implementation:**
```swift
// Update handleMethodCall in AppDelegate.swift
private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
  switch call.method {
  case "startNavigation":
    guard let args = call.arguments as? [String: Any],
          let points = args["points"] as? [[String: Double]],
          let destination = args["destination"] as? String else {
      result(FlutterError(code: "INVALID_ARGS",
                         message: "Missing points or destination",
                         details: nil))
      return
    }

    print("📍 Received \(points.count) route points to: \(destination)")
    points.enumerated().forEach { index, point in
      if let lat = point["latitude"], let lon = point["longitude"] {
        print("  Point \(index): \(lat), \(lon)")
      }
    }

    result("Received route with \(points.count) points")

  default:
    result(FlutterMethodNotImplemented)
  }
}
```

**Test:**
- Calculate route with GraphHopper
- Pass route to `startNavigation()`
- Check Xcode console for printed coordinates
- Verify coordinates match GraphHopper response

**✅ Success Criteria:**
- Route data passes correctly
- Coordinates are accurate
- No data loss or corruption
- Console output is readable

**STOP HERE - WAIT FOR USER CONFIRMATION**

---

### **PHASE 2: Mapbox Navigation SDK Setup (Day 2)**
**Goal:** Install and configure Mapbox Navigation SDK

#### Step 2.1: Install Mapbox Navigation SDK (1 hour)
**Files to modify:**
- `ios/Podfile`
- `ios/Runner/Info.plist`

**Implementation:**
```ruby
# ios/Podfile - Add to target 'Runner' section
target 'Runner' do
  use_frameworks!

  # Add Mapbox Navigation SDK
  pod 'MapboxNavigation', '~> 3.1.0'

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # ... rest of target
end
```

```xml
<!-- ios/Runner/Info.plist - Add before </dict> -->
<key>MBXAccessToken</key>
<string>$(MAPBOX_ACCESS_TOKEN)</string>

<!-- Add location permissions if not present -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location for navigation</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location for navigation even in background</string>
```

**Commands:**
```bash
cd ios
pod install
cd ..
flutter clean
flutter pub get
```

**Test:**
- Run `pod install` - should succeed
- Build iOS app - should compile without errors
- Check for Mapbox frameworks in `ios/Pods/`

**✅ Success Criteria:**
- Pod installation succeeds
- Build completes without errors
- No framework conflicts
- App launches normally

**STOP HERE - WAIT FOR USER CONFIRMATION**

---

#### Step 2.2: Create Navigation Handler (2 hours)
**Files to create:**
- `ios/Runner/MapboxNavigationHandler.swift`

**Implementation:**
```swift
// ios/Runner/MapboxNavigationHandler.swift
import Foundation
import MapboxNavigation
import MapboxDirections
import MapboxCoreNavigation
import CoreLocation

class MapboxNavigationHandler: NSObject {
  private var navigationViewController: NavigationViewController?
  private weak var flutterViewController: FlutterViewController?

  init(flutterViewController: FlutterViewController) {
    self.flutterViewController = flutterViewController
    super.init()
  }

  /// Start navigation with route points from Flutter
  func startNavigation(
    points: [[String: Double]],
    destination: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    // Convert Flutter points to CLLocationCoordinate2D
    let coordinates = points.compactMap { point -> CLLocationCoordinate2D? in
      guard let lat = point["latitude"],
            let lon = point["longitude"] else { return nil }
      return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    guard coordinates.count >= 2 else {
      let error = NSError(domain: "MapboxNavigation",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Need at least 2 coordinates"])
      completion(.failure(error))
      return
    }

    print("🗺️ Starting navigation with \(coordinates.count) points to: \(destination)")

    // Create waypoints
    let waypoints = [
      Waypoint(coordinate: coordinates.first!, name: "Start"),
      Waypoint(coordinate: coordinates.last!, name: destination)
    ]

    // Configure route options for cycling
    let options = NavigationRouteOptions(waypoints: waypoints, profileIdentifier: .cycling)

    // Calculate route with Mapbox Directions API
    Directions.shared.calculate(options) { [weak self] session, result in
      switch result {
      case .success(let response):
        guard let route = response.routes?.first else {
          let error = NSError(domain: "MapboxNavigation",
                             code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "No route found"])
          completion(.failure(error))
          return
        }

        print("✅ Route calculated: \(route.distance)m, \(route.expectedTravelTime)s")
        self?.showNavigationViewController(with: route)
        completion(.success(()))

      case .failure(let error):
        print("❌ Route calculation failed: \(error.localizedDescription)")
        completion(.failure(error))
      }
    }
  }

  /// Present the navigation view controller
  private func showNavigationViewController(with route: Route) {
    // Create navigation service
    let navigationService = MapboxNavigationService(
      route: route,
      routeIndex: 0,
      routeOptions: route.routeOptions,
      credentials: Credentials()
    )

    // Create navigation options
    let navigationOptions = NavigationOptions(
      navigationService: navigationService
    )

    // Create navigation view controller
    let navigationViewController = NavigationViewController(
      for: route,
      navigationOptions: navigationOptions
    )

    navigationViewController.delegate = self
    navigationViewController.modalPresentationStyle = .fullScreen

    // Present from Flutter view controller
    DispatchQueue.main.async { [weak self] in
      self?.flutterViewController?.present(navigationViewController, animated: true) {
        print("🚀 Navigation UI presented")
      }
    }

    self.navigationViewController = navigationViewController
  }

  /// Stop navigation and dismiss
  func stopNavigation() {
    navigationViewController?.dismiss(animated: true) {
      print("🛑 Navigation dismissed")
    }
    navigationViewController = nil
  }
}

// MARK: - NavigationViewControllerDelegate
extension MapboxNavigationHandler: NavigationViewControllerDelegate {
  func navigationViewControllerDidDismiss(
    _ navigationViewController: NavigationViewController,
    byCanceling canceled: Bool
  ) {
    print("📱 Navigation dismissed - cancelled: \(canceled)")
    self.navigationViewController = nil
    // TODO: Send event to Flutter
  }

  func navigationViewController(
    _ navigationViewController: NavigationViewController,
    didArriveAt waypoint: Waypoint
  ) {
    print("🎯 Arrived at destination")

    // Dismiss after a short delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      self?.stopNavigation()
      // TODO: Send event to Flutter
    }
  }
}
```

**Test:**
- File compiles without errors
- No API deprecation warnings
- Code analysis passes

**✅ Success Criteria:**
- Swift file compiles
- No syntax errors
- Mapbox SDK APIs used correctly
- Delegate methods implemented

**STOP HERE - WAIT FOR USER CONFIRMATION**

---

#### Step 2.3: Connect Handler to AppDelegate (1 hour)
**Files to modify:**
- `ios/Runner/AppDelegate.swift`

**Implementation:**
```swift
// ios/Runner/AppDelegate.swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var navigationChannel: FlutterMethodChannel?
  private var navigationHandler: MapboxNavigationHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController

    // Initialize navigation handler
    navigationHandler = MapboxNavigationHandler(flutterViewController: controller)

    // Setup method channel
    navigationChannel = FlutterMethodChannel(
      name: "com.popi.biking/navigation",
      binaryMessenger: controller.binaryMessenger
    )

    navigationChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startNavigation":
      guard let args = call.arguments as? [String: Any],
            let points = args["points"] as? [[String: Double]],
            let destination = args["destination"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGS",
          message: "Missing points or destination",
          details: nil
        ))
        return
      }

      navigationHandler?.startNavigation(
        points: points,
        destination: destination
      ) { navResult in
        switch navResult {
        case .success:
          result("Navigation started successfully")
        case .failure(let error):
          result(FlutterError(
            code: "NAV_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }

    case "stopNavigation":
      navigationHandler?.stopNavigation()
      result("Navigation stopped")

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

**Test:**
- Build app - should compile
- Run on iOS device/simulator
- Tap "Start Navigation" button
- Verify Mapbox navigation UI appears

**✅ Success Criteria:**
- App builds successfully
- Navigation UI appears full-screen
- Voice guidance starts
- Can see turn-by-turn instructions
- Map displays route

**STOP HERE - WAIT FOR USER CONFIRMATION**

---

### **PHASE 3: Navigation Lifecycle (Day 3)**
**Goal:** Handle navigation events and state transitions

#### Step 3.1: Event Streaming to Flutter (2 hours)
**Files to modify:**
- `ios/Runner/MapboxNavigationHandler.swift`
- `lib/services/ios_navigation_service.dart`

**Implementation:**
```swift
// Add to MapboxNavigationHandler
private var eventChannel: FlutterEventChannel?
private var eventSink: FlutterEventSink?

func setupEventChannel(binaryMessenger: FlutterBinaryMessenger) {
  eventChannel = FlutterEventChannel(
    name: "com.popi.biking/navigation_events",
    binaryMessenger: binaryMessenger
  )
  eventChannel?.setStreamHandler(self)
}

private func sendEvent(_ event: [String: Any]) {
  DispatchQueue.main.async { [weak self] in
    self?.eventSink?(event)
  }
}

// In delegate methods:
func navigationViewControllerDidDismiss(...) {
  sendEvent([
    "type": "navigationCancelled",
    "cancelled": canceled
  ])
}

func navigationViewController(..., didArriveAt waypoint: Waypoint) {
  sendEvent([
    "type": "navigationArrived",
    "destination": waypoint.name ?? "Unknown"
  ])
}
```

```dart
// Update IOSNavigationService
class IOSNavigationService {
  static const _methodChannel = MethodChannel('com.popi.biking/navigation');
  static const _eventChannel = EventChannel('com.popi.biking/navigation_events');

  Stream<NavigationEvent>? _eventStream;

  /// Listen to navigation events
  Stream<NavigationEvent> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<dynamic, dynamic>;
      final type = map['type'] as String;

      switch (type) {
        case 'navigationArrived':
          return NavigationEvent.arrived(map['destination'] as String);
        case 'navigationCancelled':
          return NavigationEvent.cancelled();
        default:
          return NavigationEvent.unknown();
      }
    });
    return _eventStream!;
  }
}

class NavigationEvent {
  final String type;
  final Map<String, dynamic> data;

  NavigationEvent.arrived(String destination)
      : type = 'arrived',
        data = {'destination': destination};

  NavigationEvent.cancelled()
      : type = 'cancelled',
        data = {};

  NavigationEvent.unknown()
      : type = 'unknown',
        data = {};
}
```

**Test:**
- Start navigation
- Listen to event stream in Flutter
- Cancel navigation - verify event received
- Complete navigation - verify arrival event

**✅ Success Criteria:**
- Events received in Flutter
- Event data is accurate
- No memory leaks
- Stream closes properly

**STOP HERE - WAIT FOR USER CONFIRMATION**

---

### **PHASE 4: Real-World Testing (Day 4-5)**
**Goal:** Test in actual usage scenarios

#### Test Scenario 1: Full Navigation Flow
```
1. Open app
2. Search for destination
3. Calculate route with GraphHopper
4. Review fastest vs safest
5. Tap "Start Navigation" (iOS)
6. Follow voice guidance
7. Verify arrival detection
8. Return to Flutter map
```

#### Test Scenario 2: Navigation Interruptions
```
1. Start navigation
2. Receive phone call
3. Background app
4. Foreground app
5. Cancel navigation
```

#### Test Scenario 3: Edge Cases
```
1. No GPS signal
2. Route calculation fails
3. Mapbox API error
4. Memory pressure
```

**✅ Success Criteria:**
- All scenarios work correctly
- No crashes
- Smooth transitions
- Good user experience

---

## 📋 FILES TO CREATE/MODIFY

### New Files
- ✅ `MAPBOX_NAVIGATION_PLAN.md` (this file)
- `lib/services/ios_navigation_service.dart`
- `ios/Runner/MapboxNavigationHandler.swift`

### Modified Files
- `ios/Podfile`
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `lib/screens/map_screen.dart` (add navigation button)
- `lib/screens/mapbox_map_screen_simple.dart` (add navigation button)

---

## 🔄 ROLLBACK PROCEDURE

### Return to v2.0.0 Anytime
```bash
# See what changed
git status
git diff

# Discard all changes
git reset --hard v2.0.0

# Or create new branch from v2
git checkout -b back-to-v2 v2.0.0
```

### Clean iOS Build
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter clean
flutter pub get
```

---

## ✅ APPROVAL PROCESS

**Each phase requires explicit approval:**
- ✅ "Step X.Y completed and working - proceed to next step"
- ⚠️ "Issues found - let's debug before continuing"
- 🛑 "Abort - rollback to v2.0.0"

**NEVER proceed to next step without explicit confirmation.**

---

## 📊 SUCCESS METRICS

After PoC completion, evaluate:
1. **Voice guidance quality** - Is it clear and helpful?
2. **Rerouting speed** - How fast does it recalculate?
3. **UI polish** - Does it feel professional?
4. **Integration smoothness** - Any glitches or crashes?
5. **Development effort** - Was it worth the time?
6. **Maintenance burden** - Will it be hard to maintain?

**Decision Point:**
- Score > 8/10 → Complete integration (v3.0.0)
- Score 5-7/10 → Hybrid approach (optional feature)
- Score < 5/10 → Rollback to v2.0.0

---

## 📝 NOTES

- All v2.0.0 features remain functional during development
- iOS-only feature for now (Android can be added later)
- GraphHopper routing is preserved
- POIs/Warnings remain in exploration mode
- Safe to experiment - v2.0.0 is tagged

---

**Last Updated:** 2025-10-09
**Status:** Ready to start Phase 1
**Awaiting:** User confirmation to begin Step 1.1
