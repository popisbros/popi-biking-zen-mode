# Database Migration Guide - Enhanced Hazard System v4.0.0

## Overview

This guide explains how to migrate your existing Firebase data to support the new enhanced hazard system with voting, verification, and status management.

---

## What's Being Added

### Community Warnings (Hazards)

**New Fields:**
- `upvotes` (int) - Number of upvotes
- `downvotes` (int) - Number of downvotes
- `verifiedBy` (array of strings) - List of user IDs who verified this hazard
- `userVotes` (map) - Tracks individual user votes (userId → 'up' or 'down')
- `status` (string) - Current status: 'active', 'resolved', 'disputed', 'expired'
- `expiresAt` (timestamp) - Auto-calculated based on hazard type

**New Hazard Types:**
- `dangerous_intersection`
- `debris`
- `steep`
- `flooding`

**Expiration Rules by Type:**
- Construction: 60 days
- Traffic hazard: 14 days
- Flooding: 7 days
- Steep: 90 days (permanent terrain)
- Poor surface: 30 days
- Debris: 7 days
- Pothole: 30 days
- Dangerous intersection: 90 days (permanent infrastructure)
- Other: 30 days (default)

### User Profiles

**New Fields:**
- `lastUsedRouteProfile` (string, nullable) - Last selected profile in multi-route view
- `appearanceMode` (string) - 'system', 'light', or 'dark'
- `audioAlertsEnabled` (boolean) - Enable/disable audio hazard alerts during navigation

---

## Migration Options

### Option 1: Automatic Migration (Recommended)

Use the built-in migration utility in the app.

#### Step 1: Dry Run (Test)

```dart
import 'package:popi_biking_fresh/utils/firebase_migration.dart';

// Test the migration without making changes
await FirebaseMigration.migrateAll(
  dryRun: true,
  onProgress: (message) => print(message),
);
```

This will show you what would be changed without actually modifying the database.

#### Step 2: Run Real Migration

```dart
// Apply the migration
await FirebaseMigration.migrateAll(
  dryRun: false,
  onProgress: (message) => print(message),
);
```

#### Where to Run

You can run this migration from:
1. **Debug Menu** - Add a debug button to trigger migration
2. **Startup Check** - Run once on app startup (use shared_preferences to track)
3. **Firebase Console** - Using Dart CLI script

### Option 2: Manual Firebase Console Update

If you prefer to update records manually:

#### For Hazards

1. Go to Firebase Console → Firestore
2. Select `communityWarnings` collection
3. For each document, add these fields:
   ```json
   {
     "upvotes": 0,
     "downvotes": 0,
     "verifiedBy": [],
     "userVotes": {},
     "status": "active",
     "expiresAt": <calculate based on type>
   }
   ```

#### For User Profiles

1. Select `users` collection
2. For each document, add:
   ```json
   {
     "lastUsedRouteProfile": null,
     "appearanceMode": "system",
     "audioAlertsEnabled": true
   }
   ```

### Option 3: Cloud Function (Best for Production)

Create a Cloud Function to run the migration:

```javascript
// functions/src/index.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const migrateHazards = functions.https.onRequest(async (req, res) => {
  const db = admin.firestore();
  const snapshot = await db.collection('communityWarnings').get();

  const batch = db.batch();
  let count = 0;

  snapshot.docs.forEach(doc => {
    const data = doc.data();
    if (!data.upvotes) {
      batch.update(doc.ref, {
        upvotes: 0,
        downvotes: 0,
        verifiedBy: [],
        userVotes: {},
        status: 'active',
        expiresAt: calculateExpiration(data.type, data.reportedAt)
      });
      count++;
    }
  });

  await batch.commit();
  res.json({ migrated: count });
});
```

---

## Post-Migration Steps

### 1. Update Firestore Security Rules

Deploy the updated `firestore.rules`:

```bash
firebase deploy --only firestore:rules
```

### 2. Create Firestore Indexes

Required composite indexes for efficient queries:

```
Collection: communityWarnings
- status (Ascending) + reportedAt (Descending)
- expiresAt (Ascending)
- latitude (Ascending) + longitude (Ascending)
```

Create via Firebase Console:
1. Go to Firestore → Indexes
2. Click "Create Index"
3. Add the fields above

Or use `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "communityWarnings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "reportedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "communityWarnings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "expiresAt", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "communityWarnings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "latitude", "order": "ASCENDING" },
        { "fieldPath": "longitude", "order": "ASCENDING" }
      ]
    }
  ]
}
```

Deploy with:
```bash
firebase deploy --only firestore:indexes
```

### 3. Verify Migration

Run these queries in Firebase Console to verify:

**Check migrated hazards:**
```
communityWarnings where upvotes >= 0
```

**Check active hazards:**
```
communityWarnings where status == 'active'
```

**Check user profiles:**
```
users where appearanceMode exists
```

---

## Rollback Plan

If you need to rollback the migration:

### For Hazards

Remove the new fields:

```dart
await FirebaseFirestore.instance
  .collection('communityWarnings')
  .get()
  .then((snapshot) {
    for (var doc in snapshot.docs) {
      doc.reference.update({
        'upvotes': FieldValue.delete(),
        'downvotes': FieldValue.delete(),
        'verifiedBy': FieldValue.delete(),
        'userVotes': FieldValue.delete(),
        'status': FieldValue.delete(),
        'expiresAt': FieldValue.delete(),
      });
    }
  });
```

### For User Profiles

```dart
await FirebaseFirestore.instance
  .collection('users')
  .get()
  .then((snapshot) {
    for (var doc in snapshot.docs) {
      doc.reference.update({
        'lastUsedRouteProfile': FieldValue.delete(),
        'appearanceMode': FieldValue.delete(),
        'audioAlertsEnabled': FieldValue.delete(),
      });
    }
  });
```

---

## Testing Checklist

After migration, test these scenarios:

- [ ] Existing hazards display correctly
- [ ] Can upvote/downvote hazards
- [ ] Verification counter works (3 verifications = verified badge)
- [ ] Vote score calculated correctly (upvotes - downvotes)
- [ ] Status updates work (reporter can mark as resolved)
- [ ] New hazards get proper expiration dates
- [ ] User profiles load without errors
- [ ] Appearance mode persists
- [ ] Audio alerts setting persists
- [ ] Last used route profile saves automatically

---

## Support

If you encounter issues during migration:

1. **Check migration logs** - Look for error messages in the console
2. **Verify Firestore rules** - Ensure they're deployed correctly
3. **Check indexes** - Make sure composite indexes are created
4. **Test with dry run** - Always test before real migration

---

## Next Steps

After successful migration, you can:

1. Enable the new UI features for voting and verification
2. Add hazard type filters by status
3. Implement automatic expiration cleanup (Cloud Function)
4. Add analytics to track community engagement

---

**Migration Created:** 2025-11-07
**App Version:** v4.0.0
