# API Logging System

## Overview

The app uses a hybrid logging approach with **Crashlytics** and **Firestore** to track API calls and application logs.

## Logging Strategy

### Production Mode (Release)
- ✅ **API calls** → Logged to Firestore `logs` collection
- ✅ **API errors** → Logged to Crashlytics (non-fatal errors)
- ❌ **Debug/Info logs** → NOT logged (zero overhead)

### Debug Mode (Development)
- ✅ **All logs** (debug, info, warning, error, API) → Logged to Firestore
- ✅ **Errors** → Logged to Crashlytics
- ✅ **Console output** → Via AppLogger (debugPrint)

## API Logger Usage

```dart
import '../utils/api_logger.dart';

// Log API calls (always logged, even in production)
await ApiLogger.logApiCall(
  endpoint: 'graphhopper/route',
  method: 'POST',
  url: uri.toString(),
  parameters: {'start': '...', 'end': '...'},
  statusCode: response.statusCode,
  responseBody: response.body,
  error: statusCode != 200 ? 'HTTP $statusCode' : null,
  durationMs: stopwatch.elapsedMilliseconds,
);

// Log general application logs (debug mode only)
await ApiLogger.logDebug('Debug message', tag: 'TAG', data: {...});
await ApiLogger.logInfo('Info message', tag: 'TAG', data: {...});
await ApiLogger.logWarning('Warning message', tag: 'TAG', data: {...});
await ApiLogger.logError('Error message', tag: 'TAG', error: e, stackTrace: st);
```

## Firestore Schema

### Collection: `logs`

```json
{
  "type": "api",           // "api", "debug", "info", "warning", "error"
  "level": "info",         // "debug", "info", "warning", "error"
  "message": "POST graphhopper/route",
  "tag": "ROUTING",        // Optional tag
  "data": {
    "endpoint": "graphhopper/route",
    "method": "POST",
    "url": "https://...",
    "parameters": {...},
    "statusCode": 200,
    "responseBody": "...",
    "error": null,
    "durationMs": 523
  },
  "timestamp": Timestamp,
  "clientTimestamp": "2025-01-15T10:30:45.123Z",
  "userId": "abc123",
  "platform": "android",
  "mode": "release"
}
```

## Viewing Logs

### Firebase Console (Production)
1. Go to **Firebase Console** → **Firestore Database**
2. Navigate to `logs` collection
3. Filter by:
   - `type == "api"` - API calls only
   - `level == "error"` - Errors only
   - `userId == "..."` - Specific user
   - `timestamp` - Date range

### Crashlytics (Errors)
1. Go to **Firebase Console** → **Crashlytics**
2. View **Non-fatal errors** for API failures
3. Breadcrumbs show recent API calls before crash

### Debug Mode (Development)
```dart
// Fetch recent API logs
final logs = await ApiLogger.getRecentApiLogs(limit: 50);
for (var log in logs) {
  print('${log['timestamp']}: ${log['message']}');
}
```

## Data Retention

**Firestore logs** should be cleaned up regularly to avoid costs:

### Option 1: Manual Cleanup
Run this query periodically:
```javascript
// Delete logs older than 7 days
const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
db.collection('logs')
  .where('timestamp', '<', cutoff)
  .get()
  .then(snapshot => {
    snapshot.forEach(doc => doc.ref.delete());
  });
```

### Option 2: Cloud Function (Recommended)
```javascript
exports.cleanupOldLogs = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const snapshot = await admin.firestore()
      .collection('logs')
      .where('timestamp', '<', cutoff)
      .limit(500)
      .get();

    const batch = admin.firestore().batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();

    return null;
  });
```

### Option 3: TTL Policy (Future)
Firebase may add TTL policies - check for updates

## Security Rules

See `firestore.rules`:
- ✅ Anyone can **create** logs (anonymous + authenticated)
- ✅ Users can **read** only their own logs
- ❌ Clients **cannot** update/delete logs

## Cost Estimation

### Firestore (assuming 1000 active users/day)
- **API calls**: ~5-10 logs per session = 10,000 writes/day
- **Cost**: ~$0.18/day = $5.40/month (free tier: 20k writes/day)
- **Storage**: ~10MB/week (with 7-day retention)

### Crashlytics
- ✅ **Free** (unlimited crash reports and non-fatal errors)

## Tips

1. **Monitor costs**: Check Firebase Console → Usage
2. **Enable cleanup**: Set up Cloud Function for auto-delete
3. **Filter important logs**: Use `level == "error"` for alerts
4. **Rate limiting**: Consider sampling API logs in production if costs increase
