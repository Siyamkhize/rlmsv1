# 🎯 FIX: Android Studio JDK Version Mismatch

**Error**: Incompatible Gradle JVM version  
**Issue**: Gradle 8.7 needs Java 8-21, but Java 25 is selected  
**Solution**: Change to JDK 17

---

## ✅ EXACT STEPS IN ANDROID STUDIO

### Method 1: Use the Error Banner (Easiest)

1. Look at the error message in Android Studio
2. You should see a clickable link or dropdown that says:
   - **"Change Gradle JDK location"** or
   - **"Select JDK"** or  
   - **"Gradle Settings"**
3. **Click it**
4. Select: **JDK 17** (`C:\Program Files\Java\jdk-17.0.12`)
5. Click **OK** or **Apply**
6. Android Studio will re-sync automatically

---

### Method 2: Through Settings (If no link)

1. **File → Settings** (or **Ctrl + Alt + S**)
2. Navigate to: **Build, Execution, Deployment → Build Tools → Gradle**
3. Look for: **Gradle JDK**
4. Click the dropdown
5. Select: **17** or **jdk-17.0.12**
6. Click **OK**
7. **File → Sync Project with Gradle Files**

---

### Method 3: Project Structure

1. **File → Project Structure** (or **Ctrl + Alt + Shift + S**)
2. Go to: **SDK Location**
3. Under **JDK location** or **Gradle Settings**:
   - Set JDK to: `C:\Program Files\Java\jdk-17.0.12`
4. Click **Apply** then **OK**
5. **File → Sync Project with Gradle Files**

---

## 🔍 What to Select

Look for these in the JDK dropdown:

✅ **Correct Options** (choose ONE):
- `17` (temurin-17.x.x)
- `jdk-17.0.12`
- `JDK 17`
- Any Java 17 version

❌ **Wrong Options** (DON'T choose):
- `25` or `Java 25`
- `21+` or anything above 21
- `Gradle JDK` (if it shows 25)

---

## 📝 After Selecting JDK 17

1. Wait for Gradle Sync to complete
2. You should see: "Gradle sync finished" in bottom status bar
3. Then: **Build → Build Bundle(s) / APK(s) → Build APK(s)**

---

## ⚠️ If Metadata Error Still Appears

Even with JDK 17, you may still get metadata.bin errors due to antivirus interference.

### Option A: Invalidate Caches
1. **File → Invalidate Caches / Restart**
2. Select: **Invalidate and Restart**
3. After restart, try build again

### Option B: Clean Project
1. **Build → Clean Project**
2. Wait for clean to finish
3. **Build → Rebuild Project**
4. Then **Build → Build APK(s)**

### Option C: Stop Gradle Daemon
1. Open **Terminal** in Android Studio (bottom panel)
2. Run: `.\gradlew --stop`
3. Close Android Studio
4. Delete: `C:\Users\SIYABONGA MKHIZE\.gradle` folder
5. Reopen Android Studio
6. Let it re-sync
7. Try build again

---

## 🎯 Quick Visual Guide

```
Android Studio
└── File
    ├── Settings (Ctrl+Alt+S)
    │   └── Build, Execution, Deployment
    │       └── Build Tools
    │           └── Gradle
    │               └── Gradle JDK: [Select 17 here]
    │
    └── Sync Project with Gradle Files
```

---

## ✨ Expected Result

Once JDK 17 is selected and sync completes:
- ✅ No more "Incompatible Gradle JVM" error
- ✅ Gradle sync should succeed
- ✅ Build → Build APK should work

---

## 🔄 If Build Still Fails with Metadata Error

This means antivirus is blocking Gradle cache writes.

**Temporary Fix**:
1. Temporarily disable Windows Defender Real-Time Protection
2. Try build in Android Studio
3. Re-enable protection after build

**Permanent Fix**:
1. Add exclusion for `.gradle` folder (requires Admin):
   - Open Windows Security
   - Virus & threat protection
   - Manage settings
   - Add exclusion
   - Folder: `C:\Users\SIYABONGA MKHIZE\.gradle`

---

## 📱 After Successful Build

APK will be at:
```
c:\projects\rlmss\android\app\build\outputs\apk\release\app-release.apk
```

Install with:
```powershell
adb install "c:\projects\rlmss\android\app\build\outputs\apk\release\app-release.apk"
```

Your phone (RZ8X10CKD0B) is connected and ready!

---

**Status**: 🎯 **SELECT JDK 17 IN ANDROID STUDIO NOW**
