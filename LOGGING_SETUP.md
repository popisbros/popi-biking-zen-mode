# Logging and Crash Reporting Setup

This document explains how to set up and verify the logging and crash reporting system for Wike Flutter.

## System Overview

The app has two logging systems:

1. **AppLogger** - Console logging and in-app debug overlay
2. **ApiLogger** - Production logging to Firestore and Crashlytics

## Components

### 1. AppLogger (`lib/utils/app_logger.dart`)

- **Debug Mode**: Prints to console with timestamps and emojis
- **Release Mode**: Logs stored in memory buffer (accessible via debug overlay)
- **Crashlytics**: Errors automatically sent to Firebase Crashlytics

Usage:
```dart
AppLogger.info('User logged in');
AppLogger.error('Failed to load', error: e, stackTrace: stackTrace);
AppLogger.api('Calling GraphHopper API', data: {'endpoint': '/route'});
```

### 2. ApiLogger (`lib/utils/api_logger.dart`)

- **All Modes**: API calls logged to Firestore `logs` collection
- **All Modes**: Errors sent to Crashlytics with full context
- **Debug Mode**: Additional debug logs to Firestore

API calls are logged with:
- HTTP method, endpoint, URL
- Request parameters
- Response status code and body
- Error messages
- Duration in milliseconds

## Setup Instructions

### Step 1: Deploy Firestore Rules

The Firestore security rules must be deployed to allow log writes:

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Deploy Firestore rules
firebase deploy --only firestore:rules
```

**Verify deployment:**
1. Open [Firebase Console](https://console.firebase.google.com/)
2. Select project: `popi-biking-zen-mode`
3. Go to Firestore Database → Rules
4. Verify you see the `logs` collection rules:
   ```
   match /logs/{logId} {
     allow create: if true;
     allow read: if isSignedIn() && request.auth.uid == resource.data.userId;
     allow update, delete: if false;
   }
   ```

### Step 2: Add Crashlytics dSYM Upload to XCode

The `ios/upload_symbols.sh` script automatically uploads dSYM files to Crashlytics after each build.

**To add to XCode:**

1. Open `ios/Runner.xcodeproj` in XCode
2. Select the **Runner** target
3. Go to **Build Phases** tab
4. Click **+** → **New Run Script Phase**
5. Drag the new phase to be AFTER "Embed Frameworks"
6. Rename it to: **"Upload Crashlytics Symbols"**
7. Add this script:
   ```bash
   "${PROJECT_DIR}/upload_symbols.sh"
   ```
8. In **Input Files**, add:
   ```
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
   $(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
   ```

**What this does:**
- Automatically uploads dSYM files after Release/Profile builds
- Skips Debug builds (for faster development)
- Enables crash symbolication in Firebase Crashlytics

### Step 3: Verify Logging Works

After deploying rules and rebuilding:

1. **Test Firestore Logging:**
   - Run the app and trigger a route calculation
   - Check XCode console for:
     - `📝 [FIRESTORE DEBUG] Attempting to write log to Firestore`
     - `✅ [FIRESTORE DEBUG] Successfully wrote log to Firestore`
   - If you see `❌ [FIRESTORE DEBUG] Failed`, check the error message

2. **Check Firestore Database:**
   - Open Firebase Console → Firestore Database
   - Look for `logs` collection
   - You should see documents with:
     - `type: 'api'`
     - `endpoint: 'graphhopper/route'`
     - `statusCode`, `responseBody`, `durationMs`

3. **Check Crashlytics:**
   - Open Firebase Console → Crashlytics
   - Go to **Non-fatals** tab
   - Look for errors with "API Error" in the title
   - You should see breadcrumb logs leading up to errors

## Troubleshooting

### Logs Not Appearing in Firestore

**Symptoms:** Console shows `❌ [FIRESTORE DEBUG] Failed to log to Firestore`

**Solutions:**

1. **Check Firestore Rules Are Deployed:**
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Verify Firebase Initialization:**
   - Check that Firebase is initialized in `lib/main.dart`
   - Look for `await Firebase.initializeApp()`

3. **Check Network Connectivity:**
   - Firestore requires internet connection
   - Test on real device with cellular/wifi

4. **Check Firebase Project:**
   - Verify `GoogleService-Info.plist` has correct `PROJECT_ID`
   - Should be: `popi-biking-zen-mode`

### Crashlytics Not Receiving Crashes

**Symptoms:** Crashes show as "unprocessed" in Crashlytics

**Solutions:**

1. **Upload dSYMs Manually:**
   ```bash
   # Find your archive
   cd ~/Library/Developer/Xcode/Archives

   # Find the latest .xcarchive, then:
   cd [your-archive].xcarchive/dSYMs

   # Upload to Crashlytics
   /path/to/Pods/FirebaseCrashlytics/upload-symbols \
     -gsp /path/to/GoogleService-Info.plist \
     -p ios \
     Runner.app.dSYM
   ```

2. **Verify Build Script Runs:**
   - In XCode: Product → Scheme → Edit Scheme
   - Ensure LaunchAction `buildConfiguration` is "Release"
   - Check Build log for "Uploading dSYM files to Crashlytics"

3. **Wait for Processing:**
   - Crashlytics can take 10-15 minutes to process uploads
   - Check back later if crashes are recent

### Mapbox XCFramework Warnings

**Expected Behavior:**
- You'll see warnings: "Upload Symbols Failed for MapboxCommon.framework"
- **This is normal** - Mapbox doesn't include dSYMs
- These warnings don't prevent app submission
- Mapbox crashes will show as unsymbolicated (rare)

## Monitoring in Production

### Daily Checks

1. **Crashlytics Dashboard:**
   - Check for new crashes or spikes
   - Review non-fatal errors for API issues

2. **Firestore Logs Collection:**
   - Query for recent errors:
     ```
     logs.where('level', '==', 'error')
         .orderBy('timestamp', 'desc')
         .limit(50)
     ```

3. **API Call Success Rate:**
   - Query `logs` collection for `type == 'api'`
   - Check `statusCode` distribution
   - Monitor `durationMs` for performance

### Log Cleanup

Logs auto-cleanup on app startup (configured to keep last 2 hours):

```dart
// In lib/main.dart
await ApiLogger.initializeLogCleanup(age: const Duration(hours: 2));
```

**To change retention period:**
- Edit `lib/main.dart`
- Change `Duration(hours: 2)` to desired duration
- Logs older than this will be deleted on app startup

**Production Best Practice:**
- Set up Cloud Functions scheduled trigger for cleanup
- Prevents relying on client-side cleanup
- Example Cloud Function (not included):
  ```javascript
  exports.cleanupOldLogs = functions.pubsub
    .schedule('every 24 hours')
    .onRun(async (context) => {
      // Delete logs older than 7 days
    });
  ```

## Debug Console Messages

With the debug logging added, you'll see these messages in XCode console:

### Route Calculation
- `🚦 [ROUTE DEBUG]` - Route calculation started
- `🌐 [ROUTING DEBUG]` - API key status
- `📡 [ROUTING DEBUG]` - API responses for Car/Bike/Foot
- `📊 [ROUTE DEBUG]` - Routes returned count
- `🚨 [ROUTE DEBUG]` - Errors

### Firestore Logging
- `📝 [FIRESTORE DEBUG]` - Attempting to write
- `✅ [FIRESTORE DEBUG]` - Write successful
- `❌ [FIRESTORE DEBUG]` - Write failed

These `print()` statements work in **all build modes** including Release.

## Questions?

If logs aren't appearing or Crashlytics isn't working:

1. Check this guide's troubleshooting section
2. Review XCode console for error messages
3. Verify Firebase Console shows correct project
4. Test with a fresh build after deploying rules

---

Last updated: 2025-01-04
