@echo off
echo ========================================
echo   RLMSS Ultra Low Memory Build
echo   (For 4GB RAM systems)
echo ========================================
echo.

:: Close any running Java processes to free memory
echo [1/7] Killing Java processes to free memory...
taskkill /F /IM "java.exe" >nul 2>&1
taskkill /F /IM "gradle*.exe" >nul 2>&1

:: Clean everything first
echo [2/7] Deep cleaning project...
flutter clean >nul
if exist "build" rmdir /s /q "build" >nul 2>&1
if exist "android\.gradle" rmdir /s /q "android\.gradle" >nul 2>&1
if exist "%USERPROFILE%\.gradle\caches" rmdir /s /q "%USERPROFILE%\.gradle\caches" >nul 2>&1

:: Set ultra-low memory limits
echo [3/7] Setting ultra-low memory limits...
set GRADLE_OPTS=-Xmx384m -XX:MaxMetaspaceSize=96m -XX:+UseSerialGC -XX:+UseStringDeduplication
set JAVA_OPTS=-Xmx384m -XX:MaxMetaspaceSize=96m
set _JAVA_OPTIONS=-Xmx384m -XX:MaxMetaspaceSize=96m

:: Get dependencies
echo [4/7] Getting dependencies...
flutter pub get

:: Build with absolute minimal settings - ARM64 only
echo [5/7] Building APK (ARM64, minimal memory)...
echo This may take 10-20 minutes on low memory systems...
flutter build apk --release --target-platform android-arm64 --tree-shake-icons --obfuscate --split-debug-info=debug-info

:: Check if build succeeded
if exist "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" (
    echo [6/7] SUCCESS: APK built!
    echo [7/7] APK Location: build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
    echo.
    dir "build\app\outputs\flutter-apk\*.apk" /B
) else (
    echo [6/7] FAILED: Build failed - insufficient memory
    echo [7/7] Try closing more applications and run again
)

echo.
echo Build process complete.
pause