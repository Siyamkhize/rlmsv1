@echo off
title Device Explorer Database Access Fix
echo ================================================
echo   DEVICE EXPLORER DATABASE ACCESS FIX
echo   Resolving "Access is denied" errors
echo ================================================
echo.

echo [1/6] Stopping conflicting processes...
taskkill /F /IM "*sqlite*" >nul 2>&1
taskkill /F /IM "DB Browser*" >nul 2>&1
echo Done.

echo [2/6] Clearing Android Studio cache...
set CACHE_DIR=%LOCALAPPDATA%\Google\AndroidStudio2025.2.1\device-explorer
if exist "%CACHE_DIR%" (
    rmdir /s /q "%CACHE_DIR%\samsung*" >nul 2>&1
    echo Cache cleared.
) else (
    echo Cache directory not found.
)

echo [3/6] Checking device connection...
adb devices

echo [4/6] Installing debug build...
cd /d c:\projects\rlmss
flutter install --debug

echo [5/6] Extracting database via ADB...
if not exist "C:\temp" mkdir "C:\temp"
echo Extracting main database...
adb exec-out run-as com.example.rlmss cat databases/local_data.db > C:\temp\local_data.db 2>nul
echo Extracting WAL file...
adb exec-out run-as com.example.rlmss cat databases/local_data.db-wal > C:\temp\local_data.db-wal 2>nul
echo Extracting shared memory file...
adb exec-out run-as com.example.rlmss cat databases/local_data.db-shm > C:\temp\local_data.db-shm 2>nul

echo [6/6] Verifying extraction...
if exist "C:\temp\local_data.db" (
    echo SUCCESS: Database extracted to C:\temp\local_data.db
    dir "C:\temp\local_data.db*" /B
) else (
    echo FAILED: Could not extract database
)

echo.
echo ================================================
echo   NEXT STEPS
echo ================================================
echo.
echo 1. Open C:\temp\local_data.db in DB Browser for SQLite
echo 2. OR try Device Explorer again in Android Studio
echo 3. OR use Database Inspector in App Inspection
echo.
echo If extraction failed:
echo 1. Ensure device is connected (adb devices)
echo 2. Confirm debug build is installed
echo 3. Run Android Studio as administrator
echo.
pause