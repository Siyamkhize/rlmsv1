@echo off
echo ========================================
echo APK Build with Gradle in C:\temp\
echo ========================================

REM Set Gradle to use C:\temp\
set GRADLE_USER_HOME=C:\temp\.gradle

REM Kill any existing Gradle processes
echo Stopping any existing Gradle/Java processes...
taskkill /F /IM java.exe 2>nul
taskkill /F /IM gradle.exe 2>nul
timeout /t 2 /nobreak >nul

REM Clear any existing Gradle locks in both locations
echo Cleaning up Gradle locks...
del /Q /F "C:\Users\SIYABONGA MKHIZE\.gradle\caches\journal-1\journal-1.lock" 2>nul
del /Q /F "C:\temp\.gradle\caches\journal-1\journal-1.lock" 2>nul
del /Q /F "C:\Users\SIYABONGA MKHIZE\.gradle\daemon\*\registry.bin.lock" 2>nul
del /Q /F "C:\temp\.gradle\daemon\*\registry.bin.lock" 2>nul

REM Clean Flutter
echo Cleaning Flutter...
flutter clean

REM Get dependencies
echo Getting dependencies...
flutter pub get

REM Build APK with minimal memory settings
echo Building APK (ARM64 only, minimal memory)...
flutter build apk --debug --target-platform android-arm64 --verbose

echo ========================================
echo Build complete! Check build\app\outputs\flutter-apk\
echo ========================================
pause