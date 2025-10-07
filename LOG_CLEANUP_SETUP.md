# Log Cleanup Configuration

This app implements automatic cleanup of Firestore logs older than 2 hours.

## Current Implementation (Client-Side)

The app runs log cleanup on startup using `ApiLogger.initializeLogCleanup()`.

**How it works:**
- Runs when app starts (after Firebase initialization)
- Deletes logs older than 2 hours in batches of 500
- Recursive cleanup if more than 500 old logs exist
- Silently fails if Firestore unavailable (doesn't break app)

**Location:**
- Implementation: `lib/utils/api_logger.dart`
- Initialization: `lib/main.dart` (line 62)

**Limitations:**
- Only cleans up when a user opens the app
- Multiple users might trigger cleanup simultaneously (wasted operations)
- Not ideal for production at scale

## Recommended: Cloud Functions (Server-Side)

For production, use Firebase Cloud Functions with scheduled triggers:

### 1. Install Firebase Functions

```bash
npm install -g firebase-tools
firebase init functions
```

### 2. Create Scheduled Function

Create `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Run every hour to clean logs older than 2 hours
exports.cleanupOldLogs = functions.pubsub
  .schedule('every 1 hours')
  .timeZone('UTC')
  .onRun(async (context) => {
    const twoHoursAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 2 * 60 * 60 * 1000)
    );

    const logsRef = admin.firestore().collection('logs');
    const snapshot = await logsRef
      .where('timestamp', '<', twoHoursAgo)
      .limit(500)
      .get();

    if (snapshot.empty) {
      console.log('No old logs to delete');
      return null;
    }

    const batch = admin.firestore().batch();
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    console.log(`Deleted ${snapshot.size} old logs`);

    // If we deleted 500, there might be more - trigger another run
    if (snapshot.size === 500) {
      console.log('More logs to delete, will clean on next run');
    }

    return null;
  });
```

### 3. Deploy Function

```bash
firebase deploy --only functions
```

### 4. Remove Client-Side Cleanup

Once Cloud Functions is deployed, you can remove the client-side cleanup:

```dart
// In lib/main.dart, comment out this line:
// unawaited(ApiLogger.initializeLogCleanup(age: const Duration(hours: 2)));
```

## Firestore Security Rules

Add TTL index in Firestore console for better performance:

1. Go to Firebase Console > Firestore > Indexes
2. Create composite index:
   - Collection: `logs`
   - Fields: `timestamp` (Ascending), `__name__` (Ascending)

Add security rules in `firestore.rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Logs collection - write for authenticated users, read only own logs
    match /logs/{logId} {
      allow write: if request.auth != null;
      allow read: if request.auth != null &&
                     (request.auth.uid == resource.data.userId ||
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true);
    }
  }
}
```

## Monitoring

Check Cloud Functions logs:

```bash
firebase functions:log
```

Or in Firebase Console > Functions > Logs

## Cost Considerations

**Client-side cleanup:**
- Reads: ~500 per app startup (only when old logs exist)
- Deletes: ~500 per app startup (only when old logs exist)
- Cost: Minimal for low-traffic apps

**Cloud Functions cleanup:**
- Runs: 24 times per day (every hour)
- Reads: ~500 per run (only when old logs exist)
- Deletes: ~500 per run (only when old logs exist)
- Function invocations: 24/day (free tier: 2M/month)
- Cost: Essentially free under free tier

**Recommendation:** Start with client-side, migrate to Cloud Functions if app scales.
