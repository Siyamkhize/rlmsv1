@echo off
echo ========================================
echo Clean Build - Post Disk Cleanup
echo ========================================

REM Set environment
set GRADLE_USER_HOME=C:\temp\.gradle
set JAVA_HOME=C:\Program Files\Java\jdk-17.0.12

REM Kill any existing processes
echo Stopping processes...
taskkill /F /IM java.exe 2>nul
taskkill /F /IM gradle.exe 2>nul
timeout /t 2 /nobreak >nul

REM Get dependencies first
echo Getting Flutter dependencies...
flutter pub get

REM Build with reduced memory settings
echo Building APK with optimized memory...
flutter build apk --debug --target-platform android-arm64 --android-skip-build-dependency-validation

if %ERRORLEVEL% EQU 0 (
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo APK Location: build\app\outputs\flutter-apk\
    dir build\app\outputs\flutter-apk\*.apk
    echo ========================================
) else (
    echo ========================================
    echo BUILD FAILED - Error code: %ERRORLEVEL%
    echo ========================================
)

pause