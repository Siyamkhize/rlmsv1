@echo off
echo ========================================
echo Final APK Build - Gradle 8.5 + Optimizations
echo ========================================

REM Set environment
set GRADLE_USER_HOME=C:\temp\.gradle
set JAVA_HOME=C:\Program Files\Java\jdk-17.0.12

REM Kill any existing processes
echo Stopping Java/Gradle processes...
taskkill /F /IM java.exe 2>nul
taskkill /F /IM gradle.exe 2>nul
timeout /t 3 /nobreak >nul

REM Clean up locks
echo Cleaning locks...
del /Q /F "%GRADLE_USER_HOME%\caches\journal-1\journal-1.lock" 2>nul
del /Q /F "%GRADLE_USER_HOME%\daemon\*\registry.bin.lock" 2>nul

REM Build APK
echo Building APK (ARM64 only)...
flutter build apk --debug --target-platform android-arm64 --android-skip-build-dependency-validation

if %ERRORLEVEL% EQU 0 (
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo APK Location: build\app\outputs\flutter-apk\
    dir build\app\outputs\flutter-apk\*.apk
    echo ========================================
) else (
    echo ========================================
    echo BUILD FAILED - Check output above
    echo ========================================
)

pause