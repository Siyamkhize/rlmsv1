# Quick Fix: Restart Device to Initialize ML Kit

## The Problem
You're seeing: **"Failed to scan document: DocScanException: ERROR_MLKITCONTEXT_HAS_NOT_BEEN_INITIALIZED"**

This happens because the ML Kit Document Scanner module needs to be downloaded and initialized by Google Play Services after a new APK is installed.

## The Solution (Takes 2 minutes)

### Step 1: Restart the Device
1. **Press and hold** the power button on device RZ8X306F7TZ
2. Select **Restart** (or Power off, then power on)
3. Wait for the device to fully boot up

### Step 2: Test the Scanner
1. **Open the RLMSS app**
2. **Navigate to** learner 6246
3. **Tap "Upload"** for Qualifications document
4. **Scanner should now open** successfully ✅

## Why This Works

When you install a new APK:
- Google Play Services detects the app now needs ML Kit Document Scanner
- It downloads the ML Kit module in the background (~5-10MB)
- But the module isn't fully registered until you restart

**After restart:**
- ML Kit module is properly registered
- MlKitInitProvider initializes automatically
- Scanner works normally

## If Restart Doesn't Fix It

### Try Option 1: Update Google Play Services
1. Open **Google Play Store**
2. Search for "**Google Play Services**"
3. If update available → tap **Update**
4. **Restart device** again after update
5. Test scanner

### Try Option 2: Clear Google Play Services Cache
1. **Settings** → **Apps** → **Google Play Services**
2. **Storage** → **Clear Cache** (NOT Clear Data)
3. **Restart device**
4. Open app and test

---

**Most likely solution:** Just restart the device and it will work! 🎯
