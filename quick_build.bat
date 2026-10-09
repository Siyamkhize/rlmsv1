@echo off
title Quick Safe Build - RLMSS
echo ================================================
echo   SAFE FLUTTER BUILD - GRADLE LOCK PREVENTION
echo ================================================
echo.

echo [1/6] Killing Java and Gradle processes...
taskkill /F /IM java.exe >nul 2>&1
taskkill /F /IM gradle.exe >nul 2>&1
echo Done.

echo [2/6] Removing Gradle locks...
if exist "%USERPROFILE%\.gradle\daemon" rmdir /s /q "%USERPROFILE%\.gradle\daemon" >nul 2>&1
if exist "%USERPROFILE%\.gradle\caches\journal-1" rmdir /s /q "%USERPROFILE%\.gradle\caches\journal-1" >nul 2>&1
echo Done.

echo [3/6] Cleaning project cache...
if exist "android\.gradle" rmdir /s /q "android\.gradle" >nul 2>&1
flutter clean >nul
echo Done.

echo [4/6] Setting memory limits...
set GRADLE_OPTS=-Xmx320m -XX:MaxMetaspaceSize=64m -XX:+UseSerialGC
set JAVA_OPTS=-Xmx320m -XX:MaxMetaspaceSize=64m
echo Done.

echo [5/6] Getting dependencies...
flutter pub get
echo Done.

echo [6/6] Building DEBUG APK...
echo This will take 5-10 minutes. Please wait...
flutter build apk --debug --target-platform android-arm64

echo.
if exist "build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk" (
    echo SUCCESS! Debug APK built successfully.
    echo Location: build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk
    dir "build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk"
) else (
    echo FAILED! Build was unsuccessful.
    echo Try closing other applications and running again.
)

echo.
pause