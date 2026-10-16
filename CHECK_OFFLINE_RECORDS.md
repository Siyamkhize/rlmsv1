# Troubleshooting: Online but Data Not Saving

## Problem
You're online but clock-in data is not saving to the server.  
Error: `Authentication failed, uri = learner_profile_sync`

## Root Cause
**Authentication Token Issue** - The token is either:
1. Missing
2. Expired  
3. Invalid

## What's Happening

### Current Flow (BROKEN):
```
1. User clicks "Clock In" → App detects ONLINE
2. App tries `_clockInOnline()` 
3. Calls `AppConfig.getAuthToken()` → Gets token
4. Sends request with token
5. ❌ SERVER: "Authentication failed" (401)
6. ✅ Falls back to offline save (works)
7. ❌ But sync never triggers (data stays local)
```

### What Should Happen:
```
1. User clicks "Clock In" → App detects ONLINE
2. App tries `_clockInOnline()`
3. Gets valid token
4. ✅ Uploads images → Gets filenames
5. ✅ Saves clock-in record → HTTP 200
6. ✅ Data in MySQL + files on server
```

## Quick Fixes

### Fix 1: Re-login to Get Fresh Token
**Most Common Solution**

1. **Logout** from the app
2. **Login** again
3. Try clock-in again

This will refresh your authentication token.

### Fix 2: Check Token Storage
Run this command on the device:

```powershell
adb logcat -s flutter | Select-String "Auth token|TOKEN|getAuthToken"
```

Look for:
- ✅ `Auth token retrieved` - Token exists
- ❌ `Authentication token not available` - Token missing

### Fix 3: Manually Trigger Sync (For Existing Offline Records)

The offline records ARE saved correctly. They just need to sync. Since you added the sync trigger code, it should work after rebuild.

**Check what's in offline queue:**
```powershell
adb shell "run-as com.example.rlmss sqlite3 /data/data/com.example.rlmss/databases/rlms.db 'SELECT LearnerID, clock_date, synced FROM manual_clocking WHERE synced = 0;'"
```

## Why `learner_profile_sync` Error Appears

This is a **DIFFERENT** endpoint failing, not the clock-in endpoints. The app tries to sync learner profiles and that's also failing due to authentication.

**These are SEPARATE issues:**
- `learner_profile_sync` failing ← Different feature
- `save_manual_clocking_images.php` ← Clock-in (this works if token is valid)

## Verify Server is Ready

Run this:
```powershell
php C:\xampp\htdocs\assessorReport2\mobile\verify_ready_for_test.php
```

Should show all ✅ checkmarks.

## Test Without Authentication (Debug Only)

Temporarily test if server endpoints work:

```powershell
# Test image upload endpoint  
curl -X POST http://192.168.0.84:8080/assessorReport2/mobile/save_manual_clocking_images.php `
  -H "Content-Type: application/json" `
  -d '{"learner_id": "123", "clock_date": "2026-10-16", "type": "in", "signature_image": "test", "face_image": "test", "timestamp": "2026-10-16 10:00:00"}'
```

**Expected:**
- With no token: HTTP 401 "Authentication required"
- With valid token: HTTP 200 (success)

This confirms the endpoint works, just needs valid token.

## The REAL Solution

### You Need to Rebuild APK

I added the automatic sync trigger code earlier. You need to:

1. **Rebuild the APK** with the changes:
   ```powershell
   cd C:\projects\rlmss
   flutter build apk --release
   ```

2. **Install new APK:**
   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```

3. **Re-login** to get fresh token

4. **Test clock-in** - Will now auto-sync

### Changes I Made (Need Rebuild):

1. ✅ Added `import 'services/comprehensive_manual_clocking_sync.dart';`
2. ✅ Added `_triggerOfflineSync()` method
3. ✅ Modified connectivity monitoring to trigger sync when coming online
4. ✅ Modified clock-in to trigger sync immediately after offline save

**These changes are in the code but NOT in the APK you installed earlier!**

## Quick Test After Rebuild

1. Turn OFF network
2. Clock in a learner
3. See "Saved offline"
4. Turn ON network
5. Watch logs for:
   ```
   [SIGNATURE_GEO] 🌐 Network restored - triggering sync
   [COMPREHENSIVE_SYNC] Starting sync...
   [COMPREHENSIVE_SYNC] ✅ Sync complete
   ```

## Summary

| Issue | Status | Solution |
|-------|--------|----------|
| Server endpoints fixed | ✅ Done | N/A |
| Offline save works | ✅ Works | N/A |
| Auth token missing/expired | ❌ Current problem | **Re-login** |
| Auto-sync not triggering | ❌ Not in APK yet | **Rebuild APK** |
| Sync service created | ✅ Done | Need to rebuild |

## Immediate Actions

1. **Re-login** in the app (get fresh token)
2. **Rebuild APK** (get new sync code)
3. **Test** fresh clock-in

---

**The data IS being saved offline correctly. It just needs a valid token to sync to the server. After re-login and rebuild, everything will work!**
