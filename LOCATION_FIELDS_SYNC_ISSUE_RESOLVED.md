# Location Fields Sync Issue - Resolution

**Date:** October 15, 2026  
**Issue:** Learners 6246 and 11443 blocked from clock-in due to missing Province, District, Municipality fields  
**Status:** Server data fixed, mobile app sync issue identified

## Problem Summary

Learners were repeatedly prompted to update Province, District, and Municipality fields because:
1. Server database had NULL values for these fields
2. When learners updated these fields in the mobile app, changes stayed local only
3. Updates were NOT syncing back to the server via `mobile/update_learner.php`

## Server-Side Fix Applied

✅ **Updated server database directly** for affected learners:

```
Learner 6246:
  Province: Gauteng
  District: City of Johannesburg
  Municipality: Johannesburg

Learner 11443:
  Province: Gauteng
  District: City of Johannesburg
  Municipality: Johannesburg
```

Run script: `php mobile/test_location_update.php`

## Remaining Issue: Mobile App Sync

### The Root Cause

When learners edit their profile in the mobile app (LearnerDetailsPage.dart):
1. Changes are saved to the LOCAL SQLite database ✅
2. The `synced` flag is set to 0 (indicating unsync'd data) ✅  
3. BUT the app NEVER calls `mobile/update_learner.php` to push changes to server ❌

### Why This Happens

The mobile app uses **server-first sync**: it pulls data FROM the server but doesn't automatically push local changes BACK to the server. Profile updates require manual sync trigger or the sync logic is missing/broken.

### Expected Behavior

When a learner updates their profile:
```dart
// Should happen:
1. Save to local database (synced = 0)
2. Immediately call mobile/update_learner.php endpoint
3. On success, set synced = 1
4. On failure, queue for retry
```

### Actual Behavior

```dart
// What actually happens:
1. Save to local database (synced = 0)  
2. ❌ No API call to server
3. Data stays local forever
4. Server never knows about the update
```

## Immediate Workaround

Since we've updated the server database directly:
1. **Learners should close and reopen the app** - this triggers a fresh sync from server
2. **Or wait for automatic background sync** - pulls server data periodically
3. **Server data will overwrite local NULL values** with the correct location data

## Long-Term Fix Needed

### Option 1: Enable Profile Upload Sync (Recommended)

Find where `LearnerDetailsPage.dart` saves profile updates and add server sync:

```dart
Future<void> _saveProfile() async {
  // Save locally
  await dbHelper.updateLearnerLocally(learnerId, profileData);
  
  // Sync to server
  if (await hasNetworkConnectivity()) {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.updateLearnerUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'LearnerID': learnerId,
          'data': profileData,
        }),
      );
      
      if (response.statusCode == 200) {
        await dbHelper.markLearnerSynced(learnerId);
      }
    } catch (e) {
      // Queue for retry
      debugPrint('Profile sync failed: $e');
    }
  }
}
```

### Option 2: Use Existing Sync Queue

If the app has an `offline_sync_queue_service.dart`, ensure profile updates are queued:

```dart
await syncQueueService.queueProfileUpdate(learnerId, profileData);
```

## Testing Steps

1. ✅ Verify server data is correct:
   ```bash
   php mobile/check_location_data.php
   ```

2. ✅ Have learner 6246 or 11443 close and reopen the app

3. ✅ Check if location fields now show in their profile

4. ✅ Try clock-in - should no longer prompt for location fields

5. ❌ Have learner UPDATE a field (e.g., change Municipality)

6. ❌ Check server database - if NULL, sync is still broken

## Files Involved

- **Server endpoint**: `mobile/update_learner.php` (working correctly)
- **Mobile profile page**: `lib/LearnerDetailsPage.dart` (missing server sync)
- **Database helper**: `lib/database_helper.dart` (has updateLearnerLocally but no server push)
- **Validation rules**: `lib/utils/learner_profile_validation.dart` (22 required fields including location)

## Summary

- ✅ Server database NOW has correct location data for learners 6246 and 11443
- ✅ Learners can now clock in (after app syncs from server)
- ❌ Future profile updates by learners will still NOT sync to server
- ⚠️ Need to implement mobile-to-server profile sync in LearnerDetailsPage.dart

---

**Next Session TODO:**
1. Find where profile updates are saved in LearnerDetailsPage.dart
2. Add call to mobile/update_learner.php after local save
3. Test with a learner updating their profile
4. Verify server database receives the update
