# Testing Checklist - v4.1.0
# Enhanced Hazard System & Multi-Profile Routing

**Version:** 4.1.0
**Date:** 2025-11-20
**Tester:** _________________
**Platform:** [ ] PWA/Web  [ ] iOS  [ ] Android

---

## 🎯 Pre-Testing Setup

- [ ] Run `flutter pub get`
- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`
- [ ] Create Firestore indexes (via Firebase Console or CLI)
- [ ] Clear browser cache (for PWA testing)
- [ ] Sign in with test account
- [ ] Verify app version shows v4.1.0

---

## 1️⃣ Enhanced Hazard System - Voting & Verification

### Voting Functionality
- [ ] **Create a test hazard** (use long-press on map)
  - Type: Pothole
  - Severity: Medium
  - Note hazard ID for testing

- [ ] **Upvote hazard**
  - Tap hazard marker → Opens detail dialog
  - Click upvote button (👍)
  - Verify upvote count increases to 1
  - Verify button turns purple (active state)
  - Verify vote score shows "+1" in green

- [ ] **Attempt duplicate upvote**
  - Click upvote again
  - Verify no change (already voted)
  - Check for "already upvoted" message

- [ ] **Switch to downvote**
  - Click downvote button (👎)
  - Verify upvote count decreases to 0
  - Verify downvote count increases to 1
  - Verify downvote button turns purple
  - Verify vote score shows "-1" in red

- [ ] **Switch back to upvote**
  - Click upvote button
  - Verify downvote count decreases to 0
  - Verify upvote count increases to 1
  - Verify vote score shows "+1" in green

### Verification System
- [ ] **Verify hazard (User 1)**
  - Click "Verify" button
  - Verify counter shows "1/3"
  - Verify button disappears (already verified)
  - Verify success message: "Verification added (1/3)"

- [ ] **Sign in with 2nd test account**
  - Sign out from User 1
  - Sign in with User 2
  - Find same hazard
  - Click "Verify" button
  - Verify counter shows "2/3"

- [ ] **Sign in with 3rd test account**
  - Sign out from User 2
  - Sign in with User 3
  - Find same hazard
  - Click "Verify" button
  - Verify green checkmark badge appears: "✓ Verified"
  - Verify success message: "Verified! This hazard is now community-verified."
  - Verify badge visible on map marker (if applicable)

### Status Management
- [ ] **Mark hazard as resolved (Reporter only)**
  - Sign in as the user who created the hazard
  - Open hazard detail dialog
  - Verify "MARK AS RESOLVED" button appears (green)
  - Click button
  - Verify confirmation dialog appears
  - Click "CONFIRM"
  - Verify status badge changes to "Resolved" (blue)
  - Verify success message

- [ ] **Verify non-reporter cannot resolve**
  - Sign in as different user
  - Open same hazard
  - Verify "MARK AS RESOLVED" button does NOT appear

- [ ] **Status badge colors**
  - Active: Green background ✅
  - Resolved: Blue background 🔵
  - Disputed: Orange background 🟠
  - Expired: Grey background ⚪

### Time Display
- [ ] **Time since report**
  - Create new hazard
  - Verify shows "just now"
  - Wait 2+ minutes, refresh
  - Verify shows "X min ago"
  - Create hazard, set system time +1 day
  - Verify shows "1 day ago"

---

## 2️⃣ Enhanced Hazard Types & Auto-Expiration

### New Hazard Types
- [ ] **Report each hazard type** (verify emoji and label):
  - [ ] 🕳️ Pothole (30 days)
  - [ ] 🚧 Construction (60 days)
  - [ ] ⚠️ Dangerous Intersection (90 days)
  - [ ] 🛤️ Poor Surface (30 days)
  - [ ] 🪨 Debris (7 days)
  - [ ] 🚗 Traffic Hazard (14 days)
  - [ ] ⛰️ Steep Section (90 days)
  - [ ] 💧 Flooding (7 days)
  - [ ] ❓ Other (30 days)

### Auto-Expiration
- [ ] **Create Flooding hazard** (7-day expiration)
  - Note creation date
  - Verify `expiresAt` field in Firestore (7 days from now)

- [ ] **Create Steep Section hazard** (90-day expiration)
  - Note creation date
  - Verify `expiresAt` field in Firestore (90 days from now)

- [ ] **Verify expiration calculation**
  - Open Firestore console
  - Check each hazard type has correct expiration date
  - Formula: reportedAt + expirationDays

### Severity Levels (Critical Removed)
- [ ] **Verify only 3 severity levels**:
  - [ ] Low (Green)
  - [ ] Medium (Yellow/Orange)
  - [ ] High (Orange/Red)
  - [ ] ❌ Critical should NOT appear

---

## 3️⃣ Multi-Profile Routing & Carousel

### Route Calculation
- [ ] **Calculate multi-profile routes**
  - Long-press destination → "Calculate a route to"
  - Verify loading indicator appears
  - Verify all 3 routes calculate in parallel
  - Wait for route carousel dialog

### Carousel UI
- [ ] **Carousel display**
  - Verify horizontal swipeable carousel appears
  - Verify 3 cards visible (swipe to see each):
    - [ ] 🚗 Car Route (Red card)
    - [ ] 🚴 Bike Route (Green card)
    - [ ] 🚶 Foot Route (Blue card)

- [ ] **Swipe navigation**
  - Swipe left to see next profile
  - Swipe right to see previous profile
  - Verify smooth animation
  - Verify page indicators (dots) update
  - Current page dot: Blue/Purple
  - Other dots: Grey

### Route Card Information
- [ ] **Verify each card shows**:
  - [ ] Profile icon (🚗 🚴 🚶)
  - [ ] Profile label (Car/Bike/Foot Route)
  - [ ] Description text
  - [ ] Distance (X.XX km)
  - [ ] Duration (XX min)
  - [ ] Hazard count (if hazards on route)
  - [ ] Colored border matching profile

### Route Selection
- [ ] **Select Car route**
  - Swipe to Car card
  - Verify page indicator on position 0
  - Click "START NAVIGATION"
  - Verify navigation starts with car route
  - Stop navigation

- [ ] **Verify last used profile saved**
  - Open profile settings
  - Verify "Last Used Profile" shows "🚗 Car"

- [ ] **Next route calculation auto-selects last used**
  - Calculate new route
  - Verify carousel opens to Car route (page 0)
  - Swipe to Bike route, start navigation
  - Calculate another route
  - Verify carousel opens to Bike route (page 1)

### Empty State
- [ ] **Test no routes available**
  - Calculate route to unreachable location
  - Verify empty state message appears
  - Verify "No routes available" text
  - Verify "CLOSE" button works

---

## 4️⃣ Audio Announcements

### Setup
- [ ] **Enable audio alerts**
  - Open profile screen (top-right button)
  - Scroll to "Preferences" section
  - Verify "Audio Alerts" toggle exists
  - Turn toggle ON (should be blue/purple)

- [ ] **Test audio**
  - Verify "Test" button (▶️) appears when enabled
  - Click test button
  - Verify audio plays: "Audio announcements are working correctly."
  - Verify toast message: "Playing test announcement..."

### During Navigation
- [ ] **Create test hazard 200m ahead on route**
  - Start navigation on a route
  - Long-press 200m ahead on route
  - Create hazard: Pothole, High severity

- [ ] **100m announcement test**
  - Continue navigating toward hazard
  - When ~100m away, verify audio plays
  - Expected: "Warning. High severity Pothole ahead. Verified by community." (if verified)
  - Or: "Warning. High severity Pothole ahead."

- [ ] **No duplicate announcements**
  - Continue past hazard
  - Turn around and approach again
  - Verify NO second announcement (already announced)

- [ ] **Disable audio alerts**
  - Stop navigation
  - Open profile settings
  - Toggle audio alerts OFF
  - Start navigation again
  - Approach hazard at 100m
  - Verify NO audio announcement plays

### Multiple Hazards
- [ ] **Test multiple hazards**
  - Create 3 hazards on route (300m, 200m, 100m ahead)
  - Start navigation
  - Verify each announces at 100m threshold
  - Verify no duplicates

---

## 5️⃣ User Preferences & Profile Settings

### Appearance Mode
- [ ] **Test appearance selector**
  - Open profile screen
  - Find "Appearance" preference card
  - Verify dropdown shows current mode
  - Select "🔄 System Default"
  - Refresh app, verify system theme applied
  - Select "☀️ Light Mode"
  - Verify light theme applied
  - Select "🌙 Dark Mode"
  - Verify dark theme applied (if implemented)

### Default Route Profile
- [ ] **Test default profile selector**
  - Open profile screen
  - Find "Default Route Profile" card
  - Verify current selection shown
  - Change to "🚗 Car"
  - Calculate route
  - Verify Car route pre-selected (if no last used)
  - Change to "🚴 Bike"
  - Verify updates in Firestore

### Last Used Profile
- [ ] **Auto-save last used**
  - Calculate route, select Foot route
  - Start navigation
  - Stop navigation
  - Open profile settings
  - Verify "Last Used Profile" shows "🚶 Foot"
  - Calculate new route
  - Verify carousel opens to Foot route

### Preference Persistence
- [ ] **Verify preferences persist**
  - Set appearance: Dark
  - Set audio alerts: OFF
  - Set default profile: Car
  - Close app completely
  - Reopen app
  - Check profile settings
  - Verify all preferences retained

---

## 6️⃣ Database Migration (If Existing Data)

### Dry Run Test
- [ ] **Run migration in dry-run mode**
  ```dart
  import 'package:popi_biking_fresh/utils/firebase_migration.dart';
  await FirebaseMigration.migrateAll(dryRun: true);
  ```
  - Verify console logs show what WOULD be changed
  - Verify Firestore data unchanged
  - Check log count matches expected hazards

### Real Migration
- [ ] **Run actual migration**
  ```dart
  await FirebaseMigration.migrateAll(dryRun: false);
  ```
  - Verify success message in console
  - Open Firestore console
  - Check random hazard documents
  - Verify new fields exist:
    - [ ] upvotes: 0
    - [ ] downvotes: 0
    - [ ] verifiedBy: []
    - [ ] userVotes: {}
    - [ ] status: "active"
    - [ ] expiresAt: (timestamp based on type)

### Post-Migration Verification
- [ ] **Test old hazards work**
  - Open existing (migrated) hazard
  - Verify detail dialog opens
  - Verify voting buttons appear
  - Try upvoting
  - Verify works correctly

- [ ] **Test mixed hazards**
  - Create new hazard (has all fields)
  - Open old hazard (migrated)
  - Open new hazard
  - Verify both display correctly

---

## 7️⃣ Integration Tests

### Complete User Flow 1: New Hazard with Community Engagement
1. [ ] Sign in as User A
2. [ ] Create Pothole hazard
3. [ ] Upvote own hazard
4. [ ] Sign in as User B
5. [ ] Find hazard, upvote it
6. [ ] Verify hazard
7. [ ] Sign in as User C
8. [ ] Downvote hazard
9. [ ] Sign in as User D
10. [ ] Verify hazard (should show verified badge)
11. [ ] Sign in as User A (reporter)
12. [ ] Mark as resolved
13. [ ] Verify status badge shows "Resolved"

### Complete User Flow 2: Multi-Profile Navigation
1. [ ] Sign in
2. [ ] Set default profile to Bike
3. [ ] Enable audio alerts
4. [ ] Calculate route to destination
5. [ ] Verify carousel opens to Bike (middle)
6. [ ] Swipe to Car route
7. [ ] Verify hazard count shown on each card
8. [ ] Start navigation with Car route
9. [ ] Verify last used profile saved as Car
10. [ ] Approach hazard at 100m
11. [ ] Verify audio announcement plays
12. [ ] Complete navigation
13. [ ] Calculate new route
14. [ ] Verify carousel opens to Car (last used)

### Complete User Flow 3: Settings & Preferences
1. [ ] Sign in
2. [ ] Open profile screen
3. [ ] Change appearance to Light
4. [ ] Toggle audio alerts OFF
5. [ ] Set default profile to Foot
6. [ ] Test audio (should work even when toggle off)
7. [ ] Close app
8. [ ] Reopen app
9. [ ] Verify preferences retained
10. [ ] Start navigation
11. [ ] Verify no audio (alerts disabled)

---

## 8️⃣ Edge Cases & Error Handling

### Voting Edge Cases
- [ ] **Vote without sign-in**
  - Sign out
  - Open hazard
  - Verify voting buttons disabled/hidden

- [ ] **Rapid voting**
  - Click upvote rapidly (5 times)
  - Verify only 1 vote counted
  - Verify no errors in console

### Network Issues
- [ ] **Offline vote**
  - Disconnect network
  - Try to vote
  - Verify error message shown
  - Reconnect
  - Vote again, verify works

### Data Validation
- [ ] **Invalid hazard type**
  - In Firestore, manually set type to "invalid"
  - Open hazard in app
  - Verify app doesn't crash
  - Verify default emoji shown

---

## 9️⃣ Performance Tests

### Route Calculation Speed
- [ ] **Multi-profile performance**
  - Start timer
  - Calculate multi-profile routes
  - Stop timer when carousel appears
  - Expected: < 5 seconds for all 3 routes
  - Note actual time: _______ seconds

### Map Performance
- [ ] **Many hazards on map**
  - Create 20+ hazards in visible area
  - Verify map doesn't lag
  - Zoom in/out smoothly
  - Toggle hazard visibility on/off

### Audio Performance
- [ ] **Multiple rapid announcements**
  - Create 5 hazards 110m, 105m, 100m, 95m, 90m apart
  - Navigate through all
  - Verify each announces without overlap
  - Verify no crashes

---

## 🔟 PWA-Specific Tests (Web)

### PWA Installation
- [ ] **Install as PWA**
  - Open in Chrome/Edge
  - Click install button
  - Verify app installs
  - Open as standalone app

### PWA Features
- [ ] **Offline functionality**
  - Install PWA
  - Disconnect network
  - Open app
  - Verify cached data loads

- [ ] **Responsive design**
  - Test on mobile screen (375px)
  - Test on tablet (768px)
  - Test on desktop (1920px)
  - Verify carousel adapts

### Browser Compatibility
- [ ] Chrome (Desktop)
- [ ] Chrome (Mobile)
- [ ] Safari (Desktop)
- [ ] Safari (Mobile)
- [ ] Firefox
- [ ] Edge

---

## 1️⃣1️⃣ iOS-Specific Tests (When Ready)

### iOS Native Features
- [ ] TTS audio quality on iOS
- [ ] Haptic feedback (if implemented)
- [ ] iOS notification permissions (if applicable)
- [ ] Background audio during navigation
- [ ] App switching during navigation

### iOS Gestures
- [ ] Swipe carousel with iOS gestures
- [ ] Pinch-to-zoom on map
- [ ] 3D touch on hazard markers (if supported)

---

## 🐛 Bug Report Template

**Found a bug?** Use this template:

```
**Bug Title:** [Brief description]

**Severity:** [ ] Critical  [ ] High  [ ] Medium  [ ] Low

**Steps to Reproduce:**
1.
2.
3.

**Expected Result:**
[What should happen]

**Actual Result:**
[What actually happened]

**Screenshots/Logs:**
[Attach if available]

**Platform:** [ ] PWA  [ ] iOS  [ ] Android
**Browser/OS:** [e.g., Chrome 120, iOS 17.2]
**User Account:** [Test account used]

**Related Feature:**
[ ] Voting/Verification
[ ] Multi-Profile Routing
[ ] Audio Announcements
[ ] User Preferences
[ ] Other: __________
```

---

## ✅ Testing Sign-Off

**Total Tests:** 150+
**Tests Passed:** _____
**Tests Failed:** _____
**Bugs Found:** _____

**Overall Status:** [ ] PASS  [ ] FAIL  [ ] NEEDS WORK

**Tester Signature:** _________________
**Date Completed:** _________________

**Notes:**
_______________________________________________
_______________________________________________
_______________________________________________

---

## 📝 Additional Notes for Tester

### Test Accounts Needed
Create at least 4 test accounts for voting/verification tests:
- test1@example.com
- test2@example.com
- test3@example.com
- test4@example.com

### Firebase Console Access
You'll need Firestore access to verify:
- Migration results
- Field values (upvotes, expiresAt, etc.)
- Security rule enforcement

### Recommended Testing Order
1. Basic hazard CRUD (create, view, edit, delete)
2. Voting & verification
3. Multi-profile routing
4. Audio announcements
5. User preferences
6. Integration flows
7. Edge cases

### Time Estimate
- Quick smoke test: ~30 minutes
- Comprehensive test: ~3-4 hours
- Full regression: ~6-8 hours

---

**Happy Testing! 🚴‍♂️**
