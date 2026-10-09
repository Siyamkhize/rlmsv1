@echo off
title RLMSS Emergency Build - 4GB RAM System
echo ================================================
echo   EMERGENCY BUILD FOR 4GB RAM SYSTEMS
echo   This will attempt minimal memory usage
echo ================================================
echo.

:: Kill all Java processes to free memory
echo [1/8] Freeing up system memory...
taskkill /F /IM "java.exe" >nul 2>&1
taskkill /F /IM "gradle*.exe" >nul 2>&1
taskkill /F /IM "chrome.exe" >nul 2>&1
taskkill /F /IM "msedge.exe" >nul 2>&1
timeout /t 2 >nul

:: Clear system cache
echo [2/8] Clearing system caches...
flutter clean >nul
if exist "build" rmdir /s /q "build" >nul 2>&1
if exist "android\.gradle" rmdir /s /q "android\.gradle" >nul 2>&1
if exist "%USERPROFILE%\.gradle\caches" rmdir /s /q "%USERPROFILE%\.gradle\caches" >nul 2>&1
if exist "%LOCALAPPDATA%\Android\Sdk\.temp" rmdir /s /q "%LOCALAPPDATA%\Android\Sdk\.temp" >nul 2>&1

:: Set absolute minimum memory limits
echo [3/8] Setting minimal memory allocation...
set GRADLE_OPTS=-Xmx256m -XX:MaxMetaspaceSize=48m -XX:+UseSerialGC -XX:+UseStringDeduplication -XX:+UseCompressedOops -XX:+AggressiveOpts
set JAVA_OPTS=-Xmx256m -XX:MaxMetaspaceSize=48m -XX:+UseSerialGC
set _JAVA_OPTIONS=-Xmx256m -XX:MaxMetaspaceSize=48m
set FLUTTER_CACHE_DIR=%TEMP%\flutter_cache
set ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk

:: Clean dependencies
echo [4/8] Getting fresh dependencies...
flutter pub get

:: Pre-build setup
echo [5/8] Preparing build environment...
cd android
call gradlew clean --no-daemon --quiet --offline >nul 2>&1
cd ..

:: Attempt build with minimal resources
echo [6/8] Attempting APK build (this may take 15-30 minutes)...
echo WARNING: Do not use computer for other tasks during build!
echo.

flutter build apk --release ^
  --target-platform android-arm64 ^
  --tree-shake-icons ^
  --obfuscate ^
  --split-debug-info=debug-info ^
  --no-pub ^
  --no-tree-shake-icons

:: Check results
echo.
echo [7/8] Checking build results...
if exist "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" (
    echo [8/8] ✓ SUCCESS! APK built successfully!
    echo.
    echo APK Location: build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
    echo APK Size:
    dir "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" | find "app-arm64-v8a-release.apk"
    echo.
    echo You can now install this APK on Android devices.
) else (
    echo [8/8] ✗ FAILED: Build unsuccessful
    echo.
    echo TROUBLESHOOTING STEPS:
    echo 1. Close ALL other applications
    echo 2. Increase virtual memory in Windows settings
    echo 3. Try running: .\swap_build.bat
    echo 4. Consider using the web dashboard instead
    echo.
    echo The manual clocking evidence dashboard is available at:
    echo c:\projects\rlmss\manual_clocking_evidence_dashboard.php
)

echo.
echo Build process complete.
pause