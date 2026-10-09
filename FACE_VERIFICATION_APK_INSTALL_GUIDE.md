# Face Verification Fixes - APK Installation Guide

## Date: September 23, 2026

## ✅ APK Built Successfully!

**Location:** `C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk`  
**Size:** 197.6 MB  
**Build Time:** 58.8 seconds

---

## What's New in This Build

### 🎯 Three Critical Fixes

1. **Reduced Attempts: 10 → 4**
   - Learners now get exactly 4 face verification attempts
   - All UI messages show "Attempt X of 4"

2. **Cancel Exits Clock-in**
   - When user cancels face enrollment, clock-in stops immediately
   - No signature pad shown after cancel
   - User returns to learner selection screen

3. **No Re-enrollment Dialog**
   - After 4 failed attempts, simple error message shown
   - Directs user to contact facilitator
   - No confusing re-enrollment offers

---

## Installation Steps

### Step 1: Connect Your Device

**Option A: USB Connection (Recommended)**
```powershell
# 1. Enable USB Debugging on your Android device:
#    Settings → About Phone → Tap "Build Number" 7 times
#    Settings → Developer Options → Enable "USB Debugging"

# 2. Connect device via USB cable

# 3. Verify connection:
adb devices
```

Expected output:
```
List of devices attached
ABC123XYZ    device
```

**Option B: Wireless Connection**
```powershell
# 1. Connect device to same WiFi as PC
# 2. Get device IP address (Settings → About → Status → IP)
# 3. Connect wirelessly:
adb connect 192.168.x.xxx:5555
```

---

### Step 2: Clean Old App Cache (CRITICAL!)

This removes all old face data, settings, and cached files:

```powershell
# Option 1: Full uninstall + reinstall (RECOMMENDED)
adb uninstall com.rlmss.rlmss
adb install "C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk"

# Option 2: Clear cache but keep app data
adb shell pm clear com.rlmss.rlmss

# Option 3: Clear only cache (keeps user data)
adb shell pm clear com.rlmss.rlmss --cache-only
```

**⚠️ IMPORTANT:** Option 1 (uninstall + reinstall) is recommended for testing the face verification fixes because it ensures:
- All old face enrollments are cleared
- No cached embeddings interfere with testing
- Fresh start for all learners

---

### Step 3: Install New APK

**Method 1: Using ADB (from PowerShell)**
```powershell
# Navigate to project folder
cd C:\projects\rlmss

# Install APK
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Expected output:
```
Performing Streamed Install
Success
```

**Method 2: Manual Installation**
1. Copy APK to device (USB/cloud/email)
2. Open file manager on device
3. Tap app-release.apk
4. Allow installation from unknown sources if prompted
5. Tap "Install"

---

### Step 4: Verify Installation

```powershell
# Check app is installed
adb shell pm list packages | Select-String "rlmss"
```

Expected output:
```
package:com.rlmss.rlmss
```

---

## Testing Checklist

After installation, test all three fixes:

### ✅ Test 1: Cancel During Enrollment
1. Open app and login
2. Go to Backup Clock-In Page
3. Select learner without face enrolled
4. Click "Cancel" on enrollment prompt
5. **Verify:** Returns to learner list (NO signature pad)

### ✅ Test 2: 4 Attempts Limit
1. Select learner with enrolled face
2. Deliberately fail verification (look away)
3. Count attempts
4. **Verify:** Exactly 4 attempts, then error message

### ✅ Test 3: No Re-enrollment Dialog
1. Fail all 4 attempts
2. **Verify:** Error says "contact facilitator" (NO re-enrollment offer)

---

## Troubleshooting

### Issue: "adb: device unauthorized"
**Solution:**
1. Check device screen for authorization prompt
2. Tap "Allow" and check "Always allow from this computer"
3. Run `adb devices` again

### Issue: "INSTALL_FAILED_UPDATE_INCOMPATIBLE"
**Solution:**
```powershell
# Uninstall old version first
adb uninstall com.rlmss.rlmss
# Then install new version
adb install build\app\outputs\flutter-apk\app-release.apk
```

### Issue: "device not found"
**Solution:**
1. Verify USB cable is data cable (not charge-only)
2. Try different USB port
3. Restart ADB server:
   ```powershell
   adb kill-server
   adb start-server
   adb devices
   ```

### Issue: Installation successful but app crashes
**Solution:**
1. Clear app data:
   ```powershell
   adb shell pm clear com.rlmss.rlmss
   ```
2. Restart device
3. Try again

---

## Quick Commands Reference

```powershell
# Check connected devices
adb devices

# Uninstall old app (clears ALL data)
adb uninstall com.rlmss.rlmss

# Install new APK (use -r to replace existing)
adb install -r build\app\outputs\flutter-apk\app-release.apk

# Clear app cache only (keeps login data)
adb shell pm clear com.rlmss.rlmss

# View app logs in real-time
adb logcat | Select-String "FACE"

# Take screenshot
adb shell screencap -p /sdcard/screenshot.png
adb pull /sdcard/screenshot.png

# Check app version
adb shell dumpsys package com.rlmss.rlmss | Select-String "versionName"
```

---

## For Multiple Devices

If installing on multiple devices:

```powershell
# List all connected devices
adb devices

# Install to specific device
adb -s ABC123XYZ install -r build\app\outputs\flutter-apk\app-release.apk

# Or use loop for multiple devices
adb devices | Select-String -Pattern "device$" | ForEach-Object {
    $device = ($_ -split '\s+')[0]
    Write-Host "Installing on $device..."
    adb -s $device install -r build\app\outputs\flutter-apk\app-release.apk
}
```

---

## Alternative: Share APK via File/Cloud

If ADB doesn't work:

1. **Copy APK to shared location:**
   ```powershell
   Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "C:\Users\Public\rlmss-face-fix.apk"
   ```

2. **Share via:**
   - USB drive
   - Google Drive
   - Email
   - WhatsApp
   - Bluetooth

3. **Install manually on each device:**
   - Open file on device
   - Tap to install
   - Allow unknown sources if prompted

---

## Verify Face Verification Changes

After installation, check console logs:

```powershell
# Monitor face verification logs
adb logcat | Select-String "FACE|BACKUP_CLOCKIN"
```

Look for these log patterns:

**Cancel during enrollment:**
```
[BACKUP_CLOCKIN] Face enrollment cancelled - stopping clock-in
```

**4 attempts:**
```
[FACE] Verification attempt 1 of 4
[FACE] Verification attempt 2 of 4
[FACE] Verification attempt 3 of 4
[FACE] Verification attempt 4 of 4
[FACE] All 4 verification attempts failed
```

**No re-enrollment:**
- Should NOT see: "Re-enrollment Required"
- Should see: "Please contact your facilitator"

---

## Clean Installation (Recommended for Testing)

For best testing results, do a completely clean installation:

```powershell
# 1. Backup data if needed (optional)
adb backup -f backup.ab com.rlmss.rlmss

# 2. Completely remove old app
adb uninstall com.rlmss.rlmss

# 3. Clear any residual files
adb shell rm -rf /sdcard/Android/data/com.rlmss.rlmss
adb shell rm -rf /sdcard/Android/obb/com.rlmss.rlmss

# 4. Install fresh APK
adb install build\app\outputs\flutter-apk\app-release.apk

# 5. Launch app
adb shell am start -n com.rlmss.rlmss/.MainActivity
```

---

## Post-Installation Testing

1. **Login with test account**
2. **Test Cancel behavior** (Test 1 in checklist)
3. **Test 4 attempts limit** (Test 2 in checklist)
4. **Test no re-enrollment** (Test 3 in checklist)
5. **Check console logs** match expectations
6. **Verify performance** (see FACE_VERIFICATION_TEST_PLAN.md)

---

## Support Files

- **Test Plan:** `FACE_VERIFICATION_TEST_PLAN.md`
- **Implementation Details:** `FACE_VERIFICATION_FIXES_FINAL.md`
- **Modified File:** `lib/backup_clock_in_page.dart`

---

## Need Help?

If you encounter issues:

1. Check device is properly connected: `adb devices`
2. Check app is installed: `adb shell pm list packages | Select-String rlmss`
3. View app logs: `adb logcat | Select-String "FACE"`
4. Try clean installation (uninstall + reinstall)
5. Restart device and try again

---

## Success Indicators

✅ Installation successful when:
- `adb install` shows "Success"
- App icon appears on device
- App launches without crashing
- Login works
- All three fixes work as expected

---

## Version Information

- **Build Date:** September 23, 2026
- **APK Size:** 197.6 MB
- **Build Type:** Release
- **Target Platform:** Android
- **Main Changes:** Face verification (4 attempts, cancel behavior, no re-enrollment)

---

## Ready to Install!

1. Connect your device
2. Run the commands in Step 2 & 3
3. Test using the checklist
4. Report results

Good luck! 🚀
