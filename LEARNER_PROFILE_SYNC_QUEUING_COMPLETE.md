# Learner Profile Sync - Queuing and Lazy Loading Implementation

**Date:** October 16, 2026  
**Status:** ✅ COMPLETE

## Problem
Background sync of learner profiles was causing rate limiting errors when trying to sync all unsynced learners at once:
```
HttpException: Rate limited, uri = learner_profile_sync
```

## Solution Implemented

### 1. **Lazy Loading** - Prevent Memory Issues
- **Before:** Loaded ALL unsynced learners from database (could be thousands)
- **After:** Loads only 20 records at a time (configurable via `maxToSync` parameter)
- Uses `LIMIT` clause in SQL query to prevent loading excessive records
- Orders by `LearnerID ASC` for consistent processing

### 2. **Batch Processing** - Prevent Rate Limiting
- **Before:** Tried to sync all learners in one go
- **After:** Processes records in batches of 5 (configurable via `batchSize` parameter)
- Adds 500ms delay between batches
- Adds 100ms delay between individual requests within a batch

### 3. **Queue Management**
- Processes records sequentially, not all at once
- Respects server rate limits by spacing out requests
- Provides feedback when more records exist to be synced

## Technical Changes

### File: `lib/database_helper.dart`

**Function Signature Updated:**
```dart
Future<void> syncUnsyncedLearnerProfiles({int batchSize = 5, int maxToSync = 20})
```

**Key Improvements:**
1. **Lazy Loading Query:**
   ```dart
   final unsyncedLearners = await db.query(
     'learnerdetails',
     where: 'synced = ?',
     whereArgs: [0],
     limit: maxToSync,  // NEW: Limit records loaded
     orderBy: 'LearnerID ASC',  // NEW: Consistent ordering
   );
   ```

2. **Batch Queuing Logic:**
   ```dart
   // Track batch count
   int batchCount = 0;
   
   for (var i = 0; i < unsyncedLearners.length; i++) {
     // ... sync logic ...
     
     batchCount++;
     if (batchCount >= batchSize && i < unsyncedLearners.length - 1) {
       // 500ms delay between batches
       await Future.delayed(Duration(milliseconds: 500));
       batchCount = 0;
     } else if (i < unsyncedLearners.length - 1) {
       // 100ms delay between individual requests
       await Future.delayed(Duration(milliseconds: 100));
     }
   }
   ```

3. **Continuation Feedback:**
   ```dart
   if (unsyncedLearners.length == maxToSync && syncedCount > 0) {
     debugPrint('[SYNC-LEARNER-PROFILE] More unsynced records may exist. Run sync again to continue.');
   }
   ```

## How It Works

### Sync Flow:
1. **Query Phase:** Load up to 20 unsynced learners (lazy loading)
2. **Check Connectivity:** Verify internet connection
3. **Batch Processing:** 
   - Process 5 learners
   - Wait 500ms (batch delay)
   - Process next 5 learners
   - Wait 500ms (batch delay)
   - Continue until all 20 are processed
4. **Between Requests:** 100ms delay between each individual sync request
5. **Continue:** If 20 records were synced, more may exist - run sync again

### Example Timeline:
```
Learner 1 → wait 100ms
Learner 2 → wait 100ms
Learner 3 → wait 100ms
Learner 4 → wait 100ms
Learner 5 → wait 500ms (BATCH COMPLETE)
Learner 6 → wait 100ms
Learner 7 → wait 100ms
...and so on
```

## Rate Limiting Prevention

### Before:
- ❌ Tried to sync ALL learners immediately
- ❌ No delays between requests
- ❌ Flooded server with requests
- ❌ Triggered rate limiter: `Rate limited`

### After:
- ✅ Syncs maximum 20 learners per run
- ✅ 500ms delay between batches (5 learners)
- ✅ 100ms delay between individual requests
- ✅ Respects server rate limits
- ✅ Prevents flooding

## Benefits

1. **No Rate Limiting Errors** - Requests are spaced out properly
2. **Memory Efficient** - Only loads 20 records at a time
3. **Server Friendly** - Doesn't flood the server with requests
4. **Reliable** - Syncs will complete without hitting rate limits
5. **Configurable** - Can adjust batch size and max records if needed
6. **Progress Tracking** - Provides feedback on sync status

## Configuration Options

The sync function accepts optional parameters:

```dart
// Default usage (5 per batch, max 20 total)
await dbHelper.syncUnsyncedLearnerProfiles();

// Custom batch size and limit
await dbHelper.syncUnsyncedLearnerProfiles(
  batchSize: 3,  // 3 learners per batch
  maxToSync: 10, // Max 10 learners total
);
```

## Testing

### Device: RZ8X306F7TZ
### Date: October 16, 2026

**Before Fix:**
```
[HTTP_CLIENT] Error: HttpException: Rate limited, uri = learner_profile_sync
```

**After Fix:**
```
[SYNC-LEARNER-PROFILE] Starting lazy sync (batch: 5, max: 20)
[SYNC-LEARNER-PROFILE] Found 20 unsynced learner profiles
[SYNC-LEARNER-PROFILE] Batch complete (5 records), waiting 500ms...
[SYNC-LEARNER-PROFILE] Successfully synced 20/20 learner profiles
[SYNC-LEARNER-PROFILE] More unsynced records may exist. Run sync again to continue.
```

## Related Fixes

1. **Auth Token Fix** (Earlier Today)
   - Added `Authorization: Bearer` token to sync requests
   - Fixed authentication errors
   - File: `lib/database_helper.dart`

2. **Photo/Signature Sync Icons** (Earlier Today)
   - Icons now show orange (unsynced) or green (synced)
   - Match clock-in sync status
   - File: `lib/signature_geofence_clock_in_page.dart`

## APK Details

**Build:** app-release.apk  
**Size:** 71.5MB  
**Build Time:** 353.7 seconds  
**Installed:** October 16, 2026

## Git Commit

**Commit:** 963603e  
**Message:** "Implement queuing and lazy loading for learner profile sync"  
**Pushed:** origin/development

## Future Enhancements

If needed, we can:
1. Make batch size and max limit configurable via app settings
2. Add a background scheduler to run sync periodically
3. Add progress notifications for long-running syncs
4. Implement exponential backoff if rate limiting still occurs
5. Add sync queue persistence across app restarts

## Conclusion

✅ Rate limiting issues resolved  
✅ Memory efficient lazy loading implemented  
✅ Proper queuing with batch delays  
✅ Server-friendly request spacing  
✅ All changes committed and pushed to repository  
✅ APK built and installed successfully

The app will now sync learner profiles reliably without triggering rate limits!
