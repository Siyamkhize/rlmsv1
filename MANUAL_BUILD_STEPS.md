# 🔧 Manual APK Build Steps - Gradle Issue Workaround

**Date**: September 14, 2026  
**Issue**: Gradle cache corruption with metadata.bin files  
**Status**: Requires manual intervention

---

## ⚠️ Problem

```
Could not read workspace metadata from C:\Users\SIYABONGA MKHIZE\.gradle\caches\8.7\kotlin-dsl\...\metadata.bin
```

This is a known Gradle/Kotlin DSL caching issue that occurs on some systems.

---

## 🛠️ Solution: Manual Build Steps

### Option 1: Use Android Studio (Recommended)

1. **Open Project in Android Studio**
   - Launch Android Studio
   - Open: `c:\projects\rlmss\android`

2. **Sync Gradle**
   - File → Sync Project with Gradle Files
   - Wait for sync to complete

3. **Build APK**
   - Build → Generate Signed Bundle / APK
   - Select APK
   - Choose release configuration
   - Click Build

4. **APK Location**
   - `c:\projects\rlmss\android\app\build\outputs\apk\release\app-release.apk`

---

### Option 2: Gradle Command Line (Direct)

Open PowerShell as Administrator:

```powershell
# Navigate to android folder
cd c:\projects\rlmss\android

# Run Gradle directly (bypasses Flutter)
.\gradlew clean
.\gradlew assembleRelease
```

**APK Location**: `app\build\outputs\apk\release\app-release.apk`

---

### Option 3: Fix Gradle Daemon

```powershell
# Stop all Gradle daemons
cd c:\projects\rlmss\android
.\gradlew --stop

# Clear Gradle cache completely
Remove-Item -Recurse -Force "$env:USERPROFILE\.gradle"

# Run as Administrator and try again
flutter build apk --release
```

---

### Option 4: Build with Visual Studio Code

1. Open VS Code
2. Open folder: `c:\projects\rlmss`
3. Open Terminal (Ctrl + `)
4. Run:
   ```powershell
   flutter clean
   flutter pub get
   flutter build apk --release --no-shrink
   ```

---

## 🎯 After You Get the APK

### Install on Connected Phone:

```powershell
# Your phone is already connected (device: RZ8X10CKD0B)
adb install c:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk

# OR if built with Gradle directly:
adb install c:\projects\rlmss\android\app\build\outputs\apk\release\app-release.apk
```

---

## ✅ What's Ready in This Build

Once you successfully build, the APK will have:

✅ **Local Dev Config** - Points to `http://192.168.0.84:8080`  
✅ **Query Queue Service** - Max 3 concurrent API requests  
✅ **Lazy Loading** - Pagination for learner lists  
✅ **Security Fixes** - Authentication, rate limiting  
✅ **All Existing Features**  

---

## ⚠️ CRITICAL FINDING: System-Wide Gradle Issue

**Root Cause Identified**: Multiple metadata.bin files corrupting during Gradle cache writes.  
**Affected**: `transforms-4` and `kotlin-dsl` cache folders  
**Likely Causes**:
- Antivirus intercepting file writes
- Disk I/O errors
- File system corruption
- Permission issues

### Possible Fixes:

1. **Disable Antivirus Temporarily**
   - Add exclusion for `C:\Users\SIYABONGA MKHIZE\.gradle`
   - Try build again

2. **Run PowerShell as Administrator**
   ```powershell
   # Right-click PowerShell → Run as Administrator
   cd c:\projects\rlmss
   flutter build apk --release
   ```

3. **Check Disk Health**
   ```powershell
   chkdsk C: /f
   ```

4. **Use Different Cache Location**
   ```powershell
   $env:GRADLE_USER_HOME = "D:\.gradle"  # If D: drive exists
   flutter build apk --release
   ```

## 🐛 Alternative: Build on Another Machine

If the issue persists, consider:

1. **Clone repo on another PC**:
   ```powershell
   git clone https://github.com/Siyamkhize/RLMS.git
   cd RLMS
   git checkout development
   flutter pub get
   flutter build apk --release
   ```

2. **Use GitHub Actions** (if configured)
3. **Use a CI/CD service** (CodeMagic, Codemagic, etc.)

---

## 📝 Technical Details

### What Causes This:

- Gradle metadata corruption during download
- File system permissions issues
- Antivirus interfering with Gradle cache
- Disk full during cache write (though now resolved)

### Why Flutter Clean Doesn't Fix It:

- `flutter clean` only clears Flutter's build folder
- Doesn't touch Gradle's user cache in `~/.gradle`
- Metadata files can remain corrupted

---

## 🔍 Diagnostic Commands

Check if Gradle is working:

```powershell
cd c:\projects\rlmss\android
.\gradlew tasks
```

Check disk space (need 10GB+ free):

```powershell
Get-PSDrive C | Select-Object Free
```

Check Java version:

```powershell
java -version
```

---

## ✨ Quick Summary

**Fastest Solution**: Use Android Studio to build the APK  
**Alternative**: Run `.\gradlew assembleRelease` directly in `android` folder  
**Then**: Install with `adb install <path-to-apk>`

---

**All code changes are committed and ready**. You just need to successfully build the APK! 🚀

**Commit**: `3378550`  
**Branch**: `development`  
**Status**: ⏸️ **WAITING FOR SUCCESSFUL BUILD**
