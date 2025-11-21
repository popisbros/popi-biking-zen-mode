# Map Screens Refactoring Guide

## Current Progress

### ✅ Phase 1: Shared UI Controls (COMPLETE)
**Status**: Completed
**Lines Saved**: ~400 lines
**Files Created**:
- `lib/widgets/map_controls/top_right_controls.dart`
- `lib/widgets/map_controls/bottom_left_controls.dart`
- `lib/widgets/map_controls/bottom_right_controls.dart`

**Impact**: Both 2D and 3D maps can now use these shared controls instead of duplicate code.

---

## Phase 2: Implement Shared Controls (TODO)

### Step 1: Update 2D Map (map_screen.dart)

**Lines to replace**: ~200 lines (1950-2315)

**Before**:
```dart
// Top-right controls (POI toggles, zoom, location, profile)
Positioned(
  top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
  right: 10,
  child: Column(
    // 150+ lines of button definitions...
  ),
),
```

**After**:
```dart
// Top-right controls
Positioned(
  top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
  right: 10,
  child: TopRightControls(
    onZoomIn: () {
      final currentZoom = _mapController.camera.zoom;
      final newZoom = currentZoom.floor() + 1.0;
      _mapController.move(_mapController.camera.center, newZoom);
      setState(() {});
    },
    onZoomOut: () {
      final currentZoom = _mapController.camera.zoom;
      final newZoom = currentZoom.floor() - 1.0;
      _mapController.move(_mapController.camera.center, newZoom);
      // Auto-disable POI toggles at zoom <= 12
      if (newZoom <= 12.0) {
        final mapState = ref.read(mapProvider);
        if (mapState.showOSMPOIs) ref.read(mapProvider.notifier).toggleOSMPOIs();
        if (mapState.showPOIs) ref.read(mapProvider.notifier).togglePOIs();
        if (mapState.showWarnings) ref.read(mapProvider.notifier).toggleWarnings();
      }
      setState(() {});
    },
    onCenterLocation: () {
      final locationAsync = ref.read(locationNotifierProvider);
      locationAsync.whenData((location) {
        if (location != null) {
          _mapController.move(LatLng(location.latitude, location.longitude), 15);
          _loadAllMapDataWithBounds();
        }
      });
    },
    currentZoom: _isMapReady ? _mapController.camera.zoom : 13.0,
    isZoomVisible: _isMapReady,
  ),
),

// Bottom-left controls
Positioned(
  bottom: kIsWeb ? 10 : 30,
  left: 10,
  child: BottomLeftControls(
    onAutoZoomToggle: () {
      final wasEnabled = ref.read(mapProvider).autoZoomEnabled;
      ref.read(mapProvider.notifier).toggleAutoZoom();
      if (!wasEnabled) {
        final location = ref.read(locationNotifierProvider).value;
        if (location != null && _isMapReady) {
          // Re-center logic...
        }
      }
    },
    onCompassToggle: () {
      setState(() {
        _compassRotationEnabled = !_compassRotationEnabled;
        if (!_compassRotationEnabled) {
          _mapController.rotate(0);
          _lastBearing = null;
        }
      });
    },
    onReloadPOIs: () => _loadAllMapDataWithBounds(forceReload: true),
    compassEnabled: _compassRotationEnabled,
  ),
),

// Bottom-right controls
Positioned(
  bottom: kIsWeb ? 10 : 30,
  right: 10,
  child: BottomRightControls(
    onNavigationEnded: () {
      setState(() {
        _activeRoute = null;
      });
      _mapController.rotate(0.0);
    },
    onLayerPicker: _showLayerPicker,
    on3DSwitch: _open3DMap,
  ),
),
```

**Estimated Time**: 2-3 hours
**Testing Required**: All button functionality, navigation mode, exploration mode

---

### Step 2: Update 3D Map (mapbox_map_screen_simple.dart)

**Lines to replace**: ~250 lines (1350-1730)

**Similar pattern as 2D map**, but with Mapbox-specific camera controls:

```dart
// Top-right controls
Positioned(
  top: kIsWeb ? MediaQuery.of(context).padding.top + 10 : 40,
  right: 10,
  child: TopRightControls(
    onZoomIn: () async {
      final camera = await mapboxMap?.getCameraState();
      if (camera != null) {
        await mapboxMap?.setCamera(CameraOptions(
          zoom: camera.zoom + 1,
          center: camera.center,
        ));
      }
    },
    onZoomOut: () async {
      final camera = await mapboxMap?.getCameraState();
      if (camera != null) {
        final newZoom = camera.zoom - 1;
        await mapboxMap?.setCamera(CameraOptions(
          zoom: newZoom,
          center: camera.center,
        ));
        // Auto-disable POI toggles at zoom <= 12
        if (newZoom <= 12.0) {
          // Toggle logic...
        }
      }
    },
    onCenterLocation: _centerOnUserLocation,
    currentZoom: _currentZoom,
  ),
),
// ... similar for other controls
```

**Estimated Time**: 2-3 hours
**Testing Required**: 3D camera movements, pitch changes, style switching

---

## Phase 3: Extract Common Services (TODO)

### Service 1: MapDataLoader

**Purpose**: Centralize POI and warning loading logic

**File**: `lib/services/map/map_data_loader.dart`

**Features**:
- Load OSM POIs by bounds
- Load Wike POIs by bounds
- Load community warnings by bounds
- Debouncing logic
- Cache management
- Error handling

**API**:
```dart
class MapDataLoader {
  static Future<void> loadDataForBounds({
    required LatLngBounds bounds,
    required WidgetRef ref,
    bool forceReload = false,
  }) async {
    // Load OSM POIs
    await ref.read(osmPOIsNotifierProvider.notifier).loadPOIs(bounds);

    // Load Wike POIs
    await ref.read(poiNotifierProvider.notifier).loadPOIsWithinBounds(bounds);

    // Load warnings
    await ref.read(communityWarningsBoundsNotifierProvider.notifier)
        .loadWarningsWithinBounds(bounds);
  }
}
```

**Lines Saved**: ~200-300 lines
**Files Affected**: map_screen.dart, mapbox_map_screen_simple.dart
**Estimated Time**: 3-4 hours

---

### Service 2: LocationHandler

**Purpose**: Centralize location/bearing/heading logic

**File**: `lib/services/map/location_handler.dart`

**Features**:
- Calculate travel direction from breadcrumbs
- Handle compass heading
- Calculate bearing between points
- GPS heading fallback logic
- Threshold-based updates

**API**:
```dart
class LocationHandler {
  static double? calculateTravelDirection(List<LatLng> breadcrumbs);
  static double calculateBearing(LatLng from, LatLng to);
  static double? getEffectiveHeading({
    required double? gpsHeading,
    required double? compassHeading,
    required double? navigationBearing,
    required bool isNavigating,
  });
}
```

**Lines Saved**: ~150-200 lines
**Files Affected**: map_screen.dart, mapbox_map_screen_simple.dart
**Estimated Time**: 3-4 hours
**Challenge**: Different implementations for 2D (flutter_map) vs 3D (Mapbox)

---

### Service 3: MapCameraController (Abstract)

**Purpose**: Unified interface for camera operations

**File**: `lib/services/map/map_camera_controller.dart`

**Features**:
- Abstract interface for both map types
- Zoom in/out
- Move to location
- Rotate
- Set bearing/pitch
- Fit bounds

**API**:
```dart
abstract class MapCameraController {
  Future<void> zoomIn();
  Future<void> zoomOut();
  Future<void> moveTo(LatLng position, {double? zoom});
  Future<void> rotate(double angle);
  Future<void> setBearing(double bearing);
  Future<void> setPitch(double pitch);
  Future<void> fitBounds(LatLngBounds bounds);
  Future<double> getCurrentZoom();
}

class FlutterMapCameraController extends MapCameraController {
  // Implementation for 2D map
}

class MapboxCameraController extends MapCameraController {
  // Implementation for 3D map
}
```

**Lines Saved**: ~100-150 lines
**Estimated Time**: 4-5 hours

---

## Phase 4: Testing & Validation (TODO)

### Test Cases

1. **2D Map Controls**
   - [ ] All POI toggles work
   - [ ] Zoom in/out works
   - [ ] User location button works
   - [ ] Profile button works
   - [ ] Debug button works
   - [ ] Compass toggle works (native only)
   - [ ] Layer picker works
   - [ ] 3D switch works (native only)

2. **3D Map Controls**
   - [ ] All POI toggles work
   - [ ] Zoom in/out works
   - [ ] User location button works
   - [ ] Profile button works
   - [ ] Debug button works
   - [ ] Style picker works
   - [ ] Pitch picker works
   - [ ] 2D switch works (native only)

3. **Navigation Mode**
   - [ ] Audio toggle button appears
   - [ ] End navigation button appears
   - [ ] Bottom-right controls switch correctly
   - [ ] User location button hides
   - [ ] Profile button hides
   - [ ] POI toggles hide

4. **Data Loading**
   - [ ] POIs load on map move
   - [ ] Warnings load correctly
   - [ ] Debouncing works
   - [ ] Force reload works

---

## Phase 5: Final Cleanup (TODO)

### Code Removal

After implementing shared services, remove duplicate code from:

1. **map_screen.dart**:
   - Lines 228-370 (data loading)
   - Lines 1950-2315 (button controls)
   - Lines 1331-1360 (bearing logic)

2. **mapbox_map_screen_simple.dart**:
   - Lines 1350-1730 (button controls)
   - Lines 728-752 (bearing calculation)
   - Lines 1637-1645 (travel direction)

### Expected Final State

- **Total Lines**: ~4,500 (down from 6,207)
- **Duplication**: <300 lines (down from 1,200)
- **Shared Services**: 5-6 files
- **Maintenance**: Single source of truth for most functionality

---

## Timeline Estimate

| Phase | Time | Status |
|-------|------|--------|
| Phase 1: Shared UI Controls | 4 hours | ✅ DONE |
| Phase 2: Implement Shared Controls | 6 hours | ⏳ TODO |
| Phase 3: Extract Services | 12 hours | ⏳ TODO |
| Phase 4: Testing | 4 hours | ⏳ TODO |
| Phase 5: Cleanup | 2 hours | ⏳ TODO |
| **Total** | **28 hours** | **~3-4 days** |

---

## Priority Order

1. **HIGH**: Phase 2 - Implement shared controls (immediate value)
2. **HIGH**: MapDataLoader service (big impact, relatively easy)
3. **MEDIUM**: LocationHandler service (complex, platform-specific)
4. **LOW**: MapCameraController (nice-to-have, complex abstraction)

---

## Notes

- **Breaking Changes**: None if done carefully
- **Backward Compatibility**: Maintained throughout
- **Testing**: Essential after each phase
- **Rollback Strategy**: Git commits per phase allow easy rollback

---

## Success Metrics

- ✅ 75% reduction in duplicate code
- ✅ Both maps use same UI controls
- ✅ Bug fixes apply to both maps automatically
- ✅ New features deploy to both maps simultaneously
- ✅ Reduced build size
- ✅ Improved code maintainability
