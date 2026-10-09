# Clear App Data to Fix Learners Sync Issue

## Problem
Only 8 out of 25 learners are showing in Backup Clock-In page because the app's local SQLite database has stale/incomplete data from a previous sync.

## Root Cause
The app caches learners in its local SQLite database. When you first opened the Backup Clock-In page, it downloaded only 8 learners due to the pagination bug. Even though we fixed the server endpoint, the app is still showing those 8 cached learners from the local database instead of re-downloading all 25.

## Solution: Clear App Data

### Option 1: Clear Data via Phone Settings (RECOMMENDED)
1. Go to **Settings** on your phone
2. Tap **Apps** or **Applications**
3. Find and tap **RLMSS** app
4. Tap **Storage**
5. Tap **Clear Data** (or "Clear Storage")
6. Confirm the action
7. Open the RLMSS app again
8. Log in
9. Navigate to Backup Clock-In for classID 790
10. **ALL 25 learners** should now sync and appear

### Option 2: Uninstall and Reinstall
1. Long-press the **RLMSS** app icon
2. Tap **Uninstall**
3. Confirm uninstall
4. Install the APK: `app-release-learners-sync-fix-20261001_1007.apk`
5. Open the app and log in
6. Navigate to Backup Clock-In
7. **ALL 25 learners** should now sync

### Option 3: ADB Command (If phone is connected to PC)
```powershell
adb shell pm clear fa.rlms.app
```

## What Fixed in the Code

### Server Fix (mobile/get_learners.php)
**Before:**
- Default pagination: pageSize=30
- App called endpoint without pagination params
- Still applied pagination (30 learners limit)
- ClassID 790 with 25 learners → Only 8 synced

**After:**
- When NO pagination params → Returns ALL learners
- When WITH pagination params → Still supports pagination
- ClassID 790 with 25 learners → ALL 25 will sync

## Verify the Fix Works

After clearing app data, check the Backup Clock-In page:

**Expected Result:**
```
✅ ALL 25 learners for classID 790 appear in the list
✅ Can scroll through all learners
✅ Can search for any learner by name or ID
```

**If still showing 8 learners:**
- Check you're connected to the internet
- Check server endpoint returns all 25 (run test script below)
- Check app is using correct server (rlms.rlms.co.za)

## Test Server Returns All Learners

Upload `mobile/test_class_790_learners.php` to your server and visit:
```
https://rlms.rlms.co.za/mobile/test_class_790_learners.php
```

This will show:
- How many learners exist in database for classID 790
- How many learners the API endpoint returns
- List of all learners with names and IDs

## Summary

1. **Problem**: Stale local database cache (only 8 learners)
2. **Fix**: Server endpoint now returns ALL learners (not paginated)
3. **Action**: Clear app data to force fresh sync
4. **Result**: All 25 learners will appear in Backup Clock-In

## Notes

- This issue affects ALL classes, not just 790
- Once you clear app data, ALL classes will re-sync correctly
- Login credentials are cleared too (need to log in again)
- Offline clocking records are NOT affected (they're synced to server)
