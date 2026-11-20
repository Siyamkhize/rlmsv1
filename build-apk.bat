@echo off
REM Build script for Flutter APK with correct Java version
REM Sets JAVA_HOME to JDK 17 required by Android Gradle Plugin 8.3.0

echo Setting JAVA_HOME to JDK 17...
set JAVA_HOME=C:\Program Files\Java\jdk-17.0.12
set PATH=%JAVA_HOME%\bin;%PATH%

echo.
echo Java version:
java -version

echo.
echo Building Flutter APK (Production Release)...
flutter build apk --release --flavor production -t lib/main.dart

echo.
if %ERRORLEVEL% EQU 0 (
    echo ✅ Build successful!
    echo APK location: build\app\outputs\flutter-apk\app-production-release.apk
) else (
    echo ❌ Build failed with error code %ERRORLEVEL%
)

pause
