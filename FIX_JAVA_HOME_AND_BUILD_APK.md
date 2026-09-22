# Fix JAVA_HOME and Build Fresh APK

**Date**: September 21, 2026  
**Issue**: JAVA_HOME pointing to `\bin` directory causing Gradle build failures  
**Solution**: Fix JAVA_HOME permanently and rebuild with clean cache

---

## Problem

```
ERROR: JAVA_HOME is set to an invalid directory: C:\Program Files\Java\jdk-17.0.12\bin
```

**Root Cause**: JAVA_HOME should point to the JDK root directory, not the `\bin` subdirectory.

---

## Solution 1: Automated Fix (Recommended)

Run the batch script that fixes everything automatically:

```cmd
cd c:\projects\rlmss
fix_gradle_and_build.bat
```

This script will:
1. ✓ Set JAVA_HOME correctly for the session
2. ✓ Stop all Gradle daemons
3. ✓ Clean Flutter build cache
4. ✓ Remove corrupted Gradle cache
5. ✓ Build fresh release APK

---

## Solution 2: Manual Fix (If automated fails)

### Step 1: Fix JAVA_HOME Permanently

**Option A: Using Windows Settings UI** (Recommended)

1. Press `Win + R`, type `sysdm.cpl`, press Enter
2. Click **Advanced** tab → **Environment Variables**
3. Under **User variables**, find `JAVA_HOME`
4. Click **Edit**
5. Change value from:
   ```
   C:\Program Files\Java\jdk-17.0.12\bin  ❌ WRONG
   ```
   To:
   ```
   C:\Program Files\Java\jdk-17.0.12  ✅ CORRECT
   ```
6. Click **OK** on all dialogs
7. **IMPORTANT**: Close and reopen any terminal/PowerShell windows

**Option B: Using PowerShell** (Quick fix)

```powershell
[System.Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Java\jdk-17.0.12', 'User')
```

Then close and reopen PowerShell/VS Code.

### Step 2: Verify JAVA_HOME

Open a **NEW** PowerShell window and run:

```powershell
$env:JAVA_HOME
```

Should output:
```
C:\Program Files\Java\jdk-17.0.12
```

NOT:
```
C:\Program Files\Java\jdk-17.0.12\bin  ❌
```

### Step 3: Clear Corrupted Gradle Cache

The Gradle cache has corrupted metadata files. Delete it:

```powershell
# Close VS Code and any terminals first!

# Remove Gradle cache
Remove-Item -Path "$env:USERPROFILE\.gradle" -Recurse -Force

# Clean Flutter build
cd c:\projects\rlmss
flutter clean
```

### Step 4: Build Fresh APK

```powershell
cd c:\projects\rlmss
flutter build apk --release
```

Expected output:
```
Running Gradle task 'assembleRelease'...
✓ Built build\app\outputs\flutter-apk\app-release.apk (XX.XMB)
```

---

## Solution 3: Nuclear Option (Last Resort)

If both solutions above fail:

### 1. Restart Computer
This ensures all Java/Gradle processes are fully terminated and file handles released.

### 2. Verify JAVA_HOME After Restart

```powershell
$env:JAVA_HOME
# Should be: C:\Program Files\Java\jdk-17.0.12
```

### 3. Manually Delete Gradle Cache

Use File Explorer with **Admin rights**:

1. Open File Explorer as Administrator
2. Navigate to: `C:\Users\SIYABONGA MKHIZE\.gradle`
3. Delete the entire `.gradle` folder
4. If it says "file in use", restart computer and try again

### 4. Clean and Rebuild

```powershell
cd c:\projects\rlmss
flutter clean
flutter pub get
flutter build apk --release
```

---

## Verification Checklist

After building, verify:

- [ ] APK exists at: `c:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk`
- [ ] APK size is reasonable (50-100 MB typically)
- [ ] No Gradle errors during build
- [ ] JAVA_HOME correctly set

Check APK details:

```powershell
Get-Item "c:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk" | Select-Object Name, Length, LastWriteTime
```

---

## Installation to Phone

Once APK is built successfully:

### Option 1: ADB Install (If phone connected)

```powershell
flutter install --release
```

Or:

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### Option 2: Manual Transfer

1. Copy `app-release.apk` to phone storage
2. On phone: Open Files app → tap APK → Install
3. Enable "Install from unknown sources" if prompted

---

## What's Fixed in This APK

✅ Face recognition enrollment and verification  
✅ Evidence data saved to `learner_clocking_evidence` table  
✅ Offline face verification fallback  
✅ Better JSON error handling for PHP responses  
✅ All face photos, GPS, signatures saved as evidence  

---

## Troubleshooting

### "Access denied" when deleting Gradle cache

**Solution**: Close ALL applications that might use Java/Gradle:
- VS Code
- Android Studio
- IntelliJ IDEA
- Any terminal windows
- Flutter DevTools

Then try again, or restart computer.

### "flutter: command not found"

**Solution**: Run in PowerShell (not CMD):

```powershell
flutter doctor
```

If still not found, add Flutter to PATH or use full path:

```powershell
C:\path\to\flutter\bin\flutter build apk --release
```

### Build succeeds but APK doesn't install

**Symptoms**: "App not installed" or "Parse error"

**Solution**:
1. Uninstall old version from phone first
2. Enable "Unknown sources" in Settings → Security
3. Check phone has enough storage (100+ MB free)
4. Try: `adb install -r -d build\app\outputs\flutter-apk\app-release.apk`

### Gradle still failing after all fixes

**Last Resort**:

```powershell
# Completely reset Flutter
flutter clean
flutter pub cache repair
flutter pub get
flutter doctor -v

# Build with verbose output
flutter build apk --release --verbose
```

---

## Summary

**Quick Fix**:
```cmd
cd c:\projects\rlmss
fix_gradle_and_build.bat
```

**Manual Fix**:
1. Fix JAVA_HOME → `C:\Program Files\Java\jdk-17.0.12` (no `\bin`)
2. Delete `%USERPROFILE%\.gradle`
3. `flutter clean`
4. `flutter build apk --release`

**Result**: Fresh APK with face recognition fixes at:
```
c:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `$env:JAVA_HOME` | Check current JAVA_HOME |
| `flutter clean` | Clear Flutter build cache |
| `flutter pub get` | Get dependencies |
| `flutter build apk --release` | Build release APK |
| `flutter devices` | Check connected devices |
| `flutter install --release` | Install APK to connected phone |
| `adb devices` | List connected Android devices |

---

**Status**: Ready to build fresh APK with face recognition fixes ✅
