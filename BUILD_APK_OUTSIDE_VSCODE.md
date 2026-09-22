# Build APK Outside VS Code (File Lock Solution)

**Error**: `The file is being used by another program` (errno 1224)  
**Cause**: VS Code/Kiro IDE has file handles open on project files  
**Solution**: Build from a standalone terminal outside VS Code

---

## Quick Solution

### Step 1: Close VS Code/Kiro IDE Completely

1. Save all your work
2. Close **all VS Code windows**
3. Check Task Manager - make sure "Code.exe" is not running
4. If it's still running, end the process

### Step 2: Open Standalone PowerShell

1. Press `Win + R`
2. Type `powershell`
3. Press Enter

### Step 3: Run Build Script

In the standalone PowerShell window:

```powershell
cd c:\projects\rlmss
.\fix_gradle_and_build.bat
```

Or manually:

```powershell
cd c:\projects\rlmss

# Set JAVA_HOME
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"

# Clean
flutter clean

# Build
flutter build apk --release
```

---

## Alternative: Build with VS Code Closed to File

If you want to keep VS Code open but avoid file locks:

### Option 1: Close All Editors

1. In VS Code: Press `Ctrl+K W` (close all editors)
2. Wait 10 seconds for indexer to release files
3. Run build command in VS Code terminal

### Option 2: Exclude Windows Folder from Indexing

Add to `.gitignore` or `.vscodeignore`:

```
windows/flutter/generated_plugins.cmake
```

Then restart VS Code.

### Option 3: Disable Antivirus Temporarily

Some antivirus programs lock files during scanning:

1. Open Windows Security
2. Virus & threat protection → Manage settings
3. Turn off Real-time protection (temporarily)
4. Run build
5. Re-enable protection

---

## If Still Failing

### Check What's Locking the File

```powershell
# Install handle.exe (SysInternals)
# Download from: https://learn.microsoft.com/en-us/sysinternals/downloads/handle

# Run to find what's locking the file
handle.exe generated_plugins.cmake
```

### Nuclear Option: Restart Computer

1. Save all work
2. Restart Windows
3. Don't open VS Code
4. Open standalone PowerShell
5. Run build script

---

## Recommended Build Process

**For development** (with VS Code open):
```powershell
# In VS Code terminal
flutter run --release
```

**For production APK** (VS Code closed):
```powershell
# In standalone PowerShell
cd c:\projects\rlmss
flutter build apk --release
```

---

## Expected Output

When successful:

```
Running Gradle task 'assembleRelease'...
✓ Built build\app\outputs\flutter-apk\app-release.apk (65.2MB)
```

APK will be at:
```
c:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk
```

---

## After Build Success

### Install to Phone

**Option 1: ADB (phone connected via USB)**
```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

**Option 2: Manual Copy**
1. Copy APK to phone storage
2. Open Files app on phone
3. Tap APK file
4. Allow "Install from unknown sources"
5. Install

---

## Prevention

To avoid this issue in future:

1. **Close all editors** before building APK
2. **Build from standalone terminal** for release builds
3. **Use `flutter run`** for development (not `flutter build`)
4. **Exclude Windows folder** if building Windows apps

---

## Summary

**Problem**: VS Code locks `generated_plugins.cmake`  
**Quick Fix**: Close VS Code → Open standalone PowerShell → Run build  
**Best Practice**: Always build release APKs outside IDE  

---

**Ready to build!** Just close VS Code and run the script.
