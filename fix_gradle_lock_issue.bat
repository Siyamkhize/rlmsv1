@echo off
title Fix Gradle Lock Issue
echo ================================================
echo   GRADLE LOCK TIMEOUT FIX
echo   Resolving journal cache lock issue
echo ================================================
echo.

echo [1/6] Stopping all Gradle and Java processes...
taskkill /F /IM "java.exe" >nul 2>&1
taskkill /F /IM "gradle.exe" >nul 2>&1
taskkill /F /IM "gradlew.exe" >nul 2>&1
echo Done.

echo [2/6] Waiting for processes to fully terminate...
timeout /t 3 >nul

echo [3/6] Removing Gradle daemon lock files...
if exist "%USERPROFILE%\.gradle\daemon" (
    echo Cleaning daemon directory...
    rmdir /s /q "%USERPROFILE%\.gradle\daemon" >nul 2>&1
)

echo [4/6] Removing Gradle cache locks...
if exist "%USERPROFILE%\.gradle\caches\journal-1\journal-1.lock" (
    echo Removing journal cache lock...
    del /f /q "%USERPROFILE%\.gradle\caches\journal-1\journal-1.lock" >nul 2>&1
)

if exist "%USERPROFILE%\.gradle\caches" (
    echo Cleaning cache locks...
    del /f /q "%USERPROFILE%\.gradle\caches\*\*.lock" >nul 2>&1
    del /f /q "%USERPROFILE%\.gradle\caches\*\*\*.lock" >nul 2>&1
)

echo [5/6] Cleaning project Gradle cache...
cd /d c:\projects\rlmss
if exist "android\.gradle" (
    rmdir /s /q "android\.gradle" >nul 2>&1
    echo Project cache cleared.
)

echo [6/6] Testing Gradle functionality...
cd android
call gradlew clean --no-daemon --offline >nul 2>&1
if %errorlevel% equ 0 (
    echo SUCCESS: Gradle is now working!
) else (
    echo WARNING: Gradle may still have issues
)
cd ..

echo.
echo ================================================
echo   FIX COMPLETE
echo ================================================
echo.
echo Gradle lock issue should now be resolved.
echo You can now try building your app again.
echo.
pause