# Build Instructions

Quick reference for building APKs for the RLMS Flutter app.

---

## 🚀 Quick Build Commands

### Easy Way (Recommended)

**Build Production APK:**
```powershell
.\build_production.ps1
```

**Build All 3 Flavors:**
```powershell
.\build_all_flavors.ps1
```

These scripts:
- ✅ Set Java Home automatically
- ✅ Clean Gradle cache
- ✅ Build with proper configuration
- ✅ Show build summary

---

## 🔧 Manual Build Commands

If you prefer manual control:

### Production Flavor
```powershell
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
flutter build apk --release --flavor production -t lib/main.dart
```

### Staging Flavor
```powershell
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
flutter build apk --release --flavor staging -t lib/main.dart
```

### Local Flavor
```powershell
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
flutter build apk --release --flavor local -t lib/main.dart
```

---

## 📦 Build Output

**APK Location:** `build\app\outputs\flutter-apk\`

| Flavor | APK Filename | Package ID | Size |
|--------|--------------|------------|------|
| Production | `app-productionRelease.apk` | `com.example.rlmss` | ~71 MB |
| Staging | `app-stagingRelease.apk` | `com.example.rlmss.staging` | ~71 MB |
| Local | `app-localRelease.apk` | `com.example.rlmss.local` | ~71 MB |

---

## ⚠️ Important Notes

### Why Clean Gradle Cache?

The build requires Java 17, but Gradle caches the Java home path from gradle.properties. 
If you don't clean the cache before building, you'll get:

```
FAILURE: Build failed with an exception.
* What went wrong:
Value 'C:\Program Files\Java\jdk-17.0.12' given for org.gradle.java.home 
Gradle property is invalid (Java home supplied is invalid)
```

**Solution:** Clean `android\.gradle` before each build OR set `$env:JAVA_HOME` in the same command.

### Why Flutter Shows "Exit Code 1"?

Flutter CLI sometimes reports `exit code 1` even when the build succeeds. 

**How to verify success:**
1. Check if the message shows: `Copied APK to: ...`
2. Verify the APK exists: `Test-Path build\app\outputs\flutter-apk\app-*.apk`

If the APK exists, the build was successful regardless of exit code.

---

## 🔍 Verification

**Check if APK was built:**
```powershell
Get-ChildItem build\app\outputs\flutter-apk\*.apk | 
  Select-Object Name, 
    @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB, 2)}}, 
    LastWriteTime
```

**Install on device:**
```bash
adb install build\app\outputs\flutter-apk\app-productionRelease.apk
```

---

## 🛠️ Build Environment

| Component | Version |
|-----------|---------|
| Java | JDK 17.0.12 |
| Flutter | 3.24.0 |
| Gradle | 8.4 |
| Android Gradle Plugin | 8.3.0 |
| Kotlin | 1.9.24 |
| compileSdk | 35 |
| targetSdk | 35 |
| minSdk | 23 |

---

## 🐛 Troubleshooting

### "Java home supplied is invalid"

**Solution:**
```powershell
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
# Then run your build command
```

### "There is not enough space on the disk"

**Check disk space:**
```powershell
Get-PSDrive C | Select-Object @{Name="Free(GB)";Expression={[math]::Round($_.Free/1GB, 2)}}
```

**Clean up:**
```powershell
# Clean build artifacts
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\app\build -ErrorAction SilentlyContinue

# Clean temp files
Remove-Item -Recurse -Force $env:TEMP\* -ErrorAction SilentlyContinue
```

### Build is slow

**Typical build times:**
- First build: 5-7 minutes (downloads dependencies)
- Subsequent builds: 4-6 minutes
- With clean cache: 5-7 minutes

**Speed tips:**
- Keep Gradle cache (don't clean unless necessary)
- Use SSD for project
- Ensure at least 4GB free disk space

---

## 📝 Product Flavors

Each flavor can have different configurations:

### Current Configuration
All three flavors currently use the same settings, with only the application ID and version name differing:

```gradle
local {
    applicationIdSuffix ".local"
    versionNameSuffix "-local"
}

staging {
    applicationIdSuffix ".staging"
    versionNameSuffix "-staging"
}

production {
    // No suffix - clean production ID
}
```

### Future Configuration
You can differentiate flavors by adding to `android/app/build.gradle`:

```gradle
productFlavors {
    local {
        buildConfigField "String", "API_URL", '"http://localhost:8000"'
        buildConfigField "String", "ENV_NAME", '"Development"'
        resValue "string", "app_name", "RLMS Dev"
    }
    
    staging {
        buildConfigField "String", "API_URL", '"https://staging-api.rlms.com"'
        buildConfigField "String", "ENV_NAME", '"Staging"'
        resValue "string", "app_name", "RLMS Staging"
    }
    
    production {
        buildConfigField "String", "API_URL", '"https://api.rlms.com"'
        buildConfigField "String", "ENV_NAME", '"Production"'
        resValue "string", "app_name", "RLMS"
    }
}
```

---

## 🚀 CI/CD Integration

The same build commands work in GitHub Actions:

**Workflows configured:**
- `.github/workflows/dart.yml` - Builds all 3 flavors
- `.github/workflows/comprehensive-cicd.yml` - Full pipeline with security

**Matrix builds in CI/CD:**
```yaml
strategy:
  matrix:
    flavor: [local, staging, production]
```

Builds all 3 flavors in parallel on GitHub runners.

---

## 📚 Additional Resources

- **Product Flavors:** `android/app/build.gradle`
- **Gradle Properties:** `android/gradle.properties`
- **Flutter Config:** `pubspec.yaml`
- **CI/CD Docs:** `.agents/tasks/CI_CD_FLAVOR_READINESS.md`
- **Build Reports:** `.agents/tasks/PRODUCTION_BUILD_SUCCESS.md`

---

**Last Updated:** November 23, 2026  
**Version:** 1.0.6+8
