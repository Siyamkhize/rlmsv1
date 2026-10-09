@echo off
title RLMSS Swap Build - Extreme Memory Conservation
echo ================================================
echo   SWAP BUILD - USES DISK AS MEMORY
echo   For systems with very limited RAM
echo ================================================
echo.

echo WARNING: This build method is VERY SLOW but uses minimal RAM
echo It may take 45-90 minutes to complete.
echo.
pause

:: Create temporary swap directory
if not exist "C:\temp\gradle_swap" mkdir "C:\temp\gradle_swap"

:: Set ultra-minimal memory with aggressive swapping
echo [1/6] Setting swap-based memory limits...
set GRADLE_OPTS=-Xmx128m -XX:MaxMetaspaceSize=32m -XX:+UseSerialGC -XX:+AggressiveOpts -Djava.io.tmpdir=C:\temp\gradle_swap
set JAVA_OPTS=-Xmx128m -XX:MaxMetaspaceSize=32m -Djava.io.tmpdir=C:\temp\gradle_swap
set _JAVA_OPTIONS=-Xmx128m -XX:MaxMetaspaceSize=32m

:: Clear everything aggressively
echo [2/6] Deep system cleanup...
flutter clean >nul
taskkill /F /IM "java.exe" >nul 2>&1
taskkill /F /IM "gradle*.exe" >nul 2>&1
if exist "build" rmdir /s /q "build" >nul 2>&1
if exist "android\.gradle" rmdir /s /q "android\.gradle" >nul 2>&1
if exist "%USERPROFILE%\.gradle" rmdir /s /q "%USERPROFILE%\.gradle" >nul 2>&1
timeout /t 3 >nul

:: Get dependencies
echo [3/6] Getting dependencies with minimal cache...
flutter pub get --no-precompile

:: Build with absolute minimal memory usage
echo [4/6] Starting ultra-conservative build...
echo This will be VERY slow - please be patient!
echo.

flutter build apk ^
  --release ^
  --target-platform android-arm64 ^
  --no-tree-shake-icons ^
  --no-obfuscate ^
  --verbose

:: Cleanup swap files
echo [5/6] Cleaning up temporary files...
if exist "C:\temp\gradle_swap" rmdir /s /q "C:\temp\gradle_swap" >nul 2>&1

:: Check results
echo [6/6] Checking results...
if exist "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" (
    echo ✓ SUCCESS! Swap build completed!
    echo APK: build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
) else (
    echo ✗ FAILED: Even swap build failed
    echo Your system needs more virtual memory or RAM upgrade
    echo.
    echo ALTERNATIVES:
    echo 1. Use the PHP dashboard for manual clocking evidence
    echo 2. Build on a different computer with more RAM
    echo 3. Use cloud build services
)

pause