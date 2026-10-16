# Token Debug APK Installed - October 16, 2026

## Summary
Installed fresh APK with enhanced token logging to diagnose authentication issue.

## What Was Added

### Enhanced Token Logging
Added detailed logging at two critical points:

#### 1. During Login (lib/main.dart)
When server returns auth_token, the app now logs:
```
[LOGIN] ✅ Auth token saved successfully
[LOGIN] Token length: XX
[LOGIN] Token first 16 chars: XXXXXXXXXXXXXXXX...
[LOGIN] Token last 16 chars: ...XXXXXXXXXXXXXXXX
```

#### 2. During Token Retrieval (lib/config.dart)
When any endpoint retrieves the token, logs:
```
[AUTH] ✅ Token retrieved from storage
[AUTH] Token length: XX
[AUTH] Token first 16 chars: XXXXXXXXXXXXXXXX...
[AUTH] Token last 16 chars: ...XXXXXXXXXXXXXXXX
```

## Build Details
- **Built:** October 16, 2026 09:28 (5 minutes ago)
- **Size:** 71.5MB
- **Build Time:** 302.7 seconds
- **Location:** `C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk`
- **Installed On:** Device RZ8X306F7TZ
- **Status:** ✅ Successfully Installed

## Testing Instructions

### Step 1: Clear App Data (IMPORTANT)
To start fresh without old tokens:
```
Settings → Apps → RLMSS → Storage → Clear Data
```
OR uninstall and reinstall:
```
adb -s RZ8X306F7TZ uninstall com.nkatelelo.rlms
adb -s RZ8X306F7TZ install -r "app-release.apk"
```

### Step 2: Login Fresh
1. Open the app
2. Log in with user 148 credentials
3. **LOOK FOR THESE LOGS** in Android logcat or app output:
   ```
   [LOGIN] ✅ Auth token saved successfully
   [LOGIN] Token length: 64
   [LOGIN] Token first 16 chars: XXXXXXXXXXXXXXXX...
   [LOGIN] Token last 16 chars: ...XXXXXXXXXXXXXXXX
   ```

### Step 3: Try Clock-In
1. Navigate to learner clock-in page
2. Select a learner
3. Capture photo and signature
4. Click "Clock In"
5. **LOOK FOR THESE LOGS:**
   ```
   [AUTH] ✅ Token retrieved from storage
   [AUTH] Token length: 64
   [AUTH] Token first 16 chars: XXXXXXXXXXXXXXXX...
   [AUTH] Token last 16 chars: ...XXXXXXXXXXXXXXXX
   [SIGNATURE_GEO] ✅ Auth token retrieved
   [SIGNATURE_GEO] 📤 Sending image upload request...
   [SIGNATURE_GEO] 📥 Upload response status: XXX
   [SIGNATURE_GEO] 📥 Upload response body: {...}
   ```

### Step 4: Report Back
**Tell me these values:**
1. The full token from `[LOGIN]` logs (all 64 characters)
2. The full token from `[AUTH]` logs (all 64 characters)
3. The HTTP status code from `[SIGNATURE_GEO] 📥 Upload response status`
4. The response body from `[SIGNATURE_GEO] 📥 Upload response body`

## Expected Behavior

### If Token Matches Database ✅
- Status: 200
- Response: `{"success":true,"files":{...}}`
- Clock-in succeeds
- Data saves to MySQL
- Images save to folders

### If Token Mismatch ❌
- Status: 401
- Response: `{"success":false,"message":"Invalid or expired token"}`
- We'll see the EXACT token the device is sending
- We can compare with database hash

## How to View Logs

### Option 1: Android Studio
1. Open Android Studio
2. View → Tool Windows → Logcat
3. Filter by: `package:com.nkatelelo.rlms`
4. Search for: `[LOGIN]` or `[AUTH]` or `[SIGNATURE_GEO]`

### Option 2: ADB Command Line
```bash
# Real-time logs
adb -s RZ8X306F7TZ logcat -s flutter:V

# Filter for our tags
adb -s RZ8X306F7TZ logcat | findstr "[LOGIN] [AUTH] [SIGNATURE_GEO]"

# Save logs to file
adb -s RZ8X306F7TZ logcat > device_logs.txt
```

### Option 3: App Console (if visible)
Some Flutter apps show debug prints in a console or debug panel.

## Server-Side Debug Endpoint

We also have a server diagnostic:
```
http://192.168.0.84:8080/assessorReport2/mobile/debug_auth_header.php
```

This endpoint shows:
- Exact token received from device
- Token hash calculation
- Database lookup result
- Whether authentication would succeed

## Database Reference

Current valid token for user 148:
```
Hash: 4e5fb410bf0ca148999ddfecc39a40714b2ddf1e3601a0d430572eeffbb3386f
Created: 2026-10-16 09:11:56
Expires: 2026-10-23 09:11:56
Status: ✅ Valid and Active
```

The RAW token that hashes to this is what should be in the app.

## What We're Trying to Determine

### Question 1: Does login return a token?
- If `[LOGIN]` logs appear → YES
- If no `[LOGIN]` logs → Server not returning token

### Question 2: Is the token stored correctly?
- Compare `[LOGIN]` token with `[AUTH]` token
- Should be identical

### Question 3: Is the token current?
- Take the token from logs
- Hash it: `echo -n "TOKEN_HERE" | sha256sum`
- Compare with database hash
- Should match `4e5fb410bf0ca148999ddfecc39a40714b2ddf1e3601a0d430572eeffbb3386f`

### Question 4: What does server receive?
- The `debug_auth_header.php` endpoint will show us

## Next Steps After Testing

### Scenario A: New token from login works
✅ **Issue resolved** - Fresh login fixed it
- User just needed to log out/in
- Update documentation

### Scenario B: Token still doesn't match
❌ **Deeper investigation needed**
- Check if server is returning token in login response
- Verify SharedPreferences is working
- Check if another login endpoint is being used

### Scenario C: No token logs appear
❌ **Critical issue**
- Token not being saved during login
- Or token not being retrieved for requests
- Need to check login flow

---

**APK ready for testing. Report back with log output!**
