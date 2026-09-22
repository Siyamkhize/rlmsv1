@echo off
echo ===== Fixing JAVA_HOME and cleaning Gradle cache =====

REM Set JAVA_HOME for this session
set JAVA_HOME=C:\Program Files\Java\jdk-17.0.12
echo JAVA_HOME set to: %JAVA_HOME%

REM Stop any running Gradle daemons
echo Stopping Gradle daemons...
cd /d "%~dp0android"
call gradlew --stop 2>nul

REM Wait a moment for processes to release file handles
timeout /t 3 /nobreak >nul

REM Clean Flutter build
echo Cleaning Flutter build...
cd /d "%~dp0"
call flutter clean

REM Remove Gradle cache completely
echo Removing Gradle cache...
rd /s /q "%USERPROFILE%\.gradle" 2>nul

echo.
echo ===== Cache cleared! Now building APK =====
echo.

REM Build the release APK
call flutter build apk --release

echo.
if errorlevel 1 (
    echo ===== BUILD FAILED =====
    pause
    exit /b 1
) else (
    echo ===== BUILD SUCCESSFUL! =====
    echo APK location: build\app\outputs\flutter-apk\app-release.apk
    pause
    exit /b 0
)
