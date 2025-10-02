# API Keys Setup Guide

## Overview
This app uses several third-party services for maps and features. You need to configure API keys to enable all functionality.

## Required API Keys

### 1. **Thunderforest** (for cycling maps)
**Used for:** OpenCycleMap, Cycle, and Outdoors tile layers

**Get your key:**
1. Go to https://www.thunderforest.com/
2. Create a free account
3. Get your API key from the dashboard
4. **Free tier:** 150,000 tiles/month

**Configure:**
- Open `lib/config/api_keys.dart`
- Replace `YOUR_THUNDERFOREST_API_KEY` with your actual key

---

### 2. **MapTiler** (for satellite and terrain)
**Used for:** Satellite and Terrain tile layers

**Get your key:**
1. Go to https://www.maptiler.com/
2. Create a free account
3. Get your API key from https://cloud.maptiler.com/account/keys/
4. **Free tier:** 100,000 tiles/month

**Configure:**
- Open `lib/config/api_keys.dart`
- Replace `YOUR_MAPTILER_API_KEY` with your actual key

---

### 3. **Mapbox** (for 3D maps)
**Used for:** All 3D map styles in the Mapbox 3D view

**Get your token:**
1. Go to https://account.mapbox.com/
2. Create a free account
3. Get your access token from https://account.mapbox.com/access-tokens/
4. **Free tier:** 50,000 map loads/month

**Configure:**
- Open `lib/config/api_keys.dart`
- Replace `YOUR_MAPBOX_ACCESS_TOKEN` with your actual token
- **Also** add to `ios/Runner/Info.plist`:
  ```xml
  <key>MBXAccessToken</key>
  <string>YOUR_MAPBOX_ACCESS_TOKEN</string>
  ```

---

### 4. **Firebase** (for community features)
**Used for:** POI markers and community warnings (currently disabled on web)

**Setup:**
1. Go to https://console.firebase.google.com/
2. Create a new project or use existing "popi-biking-zen-mode"
3. Add iOS app with bundle ID: `com.popibiking.zenmode`
4. Download `GoogleService-Info.plist` → place in `ios/Runner/`
5. Add Android app (if needed)
6. Enable Firestore Database:
   - Go to Firestore Database
   - Create database in production mode
   - Create collections: `cycling_pois` and `community_warnings`

**To re-enable Firebase on web:**
Currently Firebase is disabled on web (line 13-24 in `lib/main.dart`). To enable:
1. Change `if (!kIsWeb)` to `if (true)` in main.dart
2. Ensure `firebase_options.dart` has web configuration
3. Rebuild web version

---

### 5. **LocationIQ** (optional - for geocoding)
**Used for:** Address search (if implemented)

**Get your key:**
1. Go to https://locationiq.com/
2. Create a free account
3. Get your API key
4. **Free tier:** 5,000 requests/day

**Configure:**
- Open `lib/config/api_keys.dart`
- Replace `YOUR_LOCATIONIQ_API_KEY` with your actual key

---

## Current Configuration File

Edit this file: **`lib/config/api_keys.dart`**

```dart
class ApiKeys {
  static const String thunderforestApiKey = 'YOUR_THUNDERFOREST_API_KEY';
  static const String mapTilerApiKey = 'YOUR_MAPTILER_API_KEY';
  static const String mapboxAccessToken = 'YOUR_MAPBOX_ACCESS_TOKEN';
  static const String locationIqApiKey = 'YOUR_LOCATIONIQ_API_KEY';
}
```

## After Adding Keys

1. **Don't commit** `api_keys.dart` to public repositories
2. Add to `.gitignore`: `lib/config/api_keys.dart`
3. Rebuild the app:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## Testing Without Keys

Some layers work without API keys:
- ✅ **OpenStreetMap** - Always free
- ✅ **CyclOSM** - Always free
- ❌ **Thunderforest layers** - Require key
- ❌ **MapTiler layers** - Require key
- ❌ **Mapbox 3D** - Requires token

## Tile Layer Overview

| Layer | Provider | API Key Needed? | Free Tier |
|-------|----------|----------------|-----------|
| Standard (OSM) | OpenStreetMap | ❌ No | Unlimited |
| OpenCycleMap | Thunderforest | ✅ Yes | 150K/month |
| Cycle | Thunderforest | ✅ Yes | 150K/month |
| Outdoors | Thunderforest | ✅ Yes | 150K/month |
| CyclOSM | Community | ❌ No | Unlimited |
| Satellite | MapTiler | ✅ Yes | 100K/month |
| Terrain | MapTiler | ✅ Yes | 100K/month |
