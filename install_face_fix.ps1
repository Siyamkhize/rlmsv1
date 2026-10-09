# Face Verification Fix - Automated Installation Script
# Date: September 23, 2026

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RLMSS Face Verification Fix Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if ADB is available
Write-Host "Checking ADB installation..." -ForegroundColor Yellow
$adbPath = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adbPath) {
    Write-Host "ERROR: ADB not found in PATH!" -ForegroundColor Red
    Write-Host "Please install Android SDK Platform Tools" -ForegroundColor Red
    exit 1
}
Write-Host "✓ ADB found: $($adbPath.Source)" -ForegroundColor Green
Write-Host ""

# Check for connected devices
Write-Host "Checking for connected devices..." -ForegroundColor Yellow
$devices = adb devices | Select-String "device$"
if ($devices.Count -eq 0) {
    Write-Host "ERROR: No devices connected!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "1. Enable USB Debugging on your device" -ForegroundColor White
    Write-Host "2. Connect device via USB" -ForegroundColor White
    Write-Host "3. Accept the authorization prompt on device" -ForegroundColor White
    Write-Host "4. Run this script again" -ForegroundColor White
    exit 1
}

$deviceCount = $devices.Count
Write-Host "✓ Found $deviceCount device(s)" -ForegroundColor Green
Write-Host ""

# Show device list
Write-Host "Connected devices:" -ForegroundColor Cyan
adb devices -l
Write-Host ""

# Confirm installation
Write-Host "This script will:" -ForegroundColor Yellow
Write-Host "1. UNINSTALL the old RLMSS app (removes all data!)" -ForegroundColor White
Write-Host "2. CLEAN all app cache and face data" -ForegroundColor White
Write-Host "3. INSTALL the new APK with face verification fixes" -ForegroundColor White
Write-Host ""
Write-Host "WARNING: All face enrollments will be deleted!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Installation cancelled." -ForegroundColor Yellow
    exit 0
}
Write-Host ""

# Step 1: Uninstall old app
Write-Host "Step 1: Uninstalling old app..." -ForegroundColor Yellow
$uninstallResult = adb uninstall com.rlmss.rlmss 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Old app uninstalled successfully" -ForegroundColor Green
} else {
    Write-Host "⚠ App might not be installed (this is OK)" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Clean residual files
Write-Host "Step 2: Cleaning residual files..." -ForegroundColor Yellow
adb shell rm -rf /sdcard/Android/data/com.rlmss.rlmss 2>&1 | Out-Null
adb shell rm -rf /sdcard/Android/obb/com.rlmss.rlmss 2>&1 | Out-Null
Write-Host "✓ Residual files cleaned" -ForegroundColor Green
Write-Host ""

# Step 3: Install new APK
Write-Host "Step 3: Installing new APK..." -ForegroundColor Yellow
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"

if (-not (Test-Path $apkPath)) {
    Write-Host "ERROR: APK not found at $apkPath" -ForegroundColor Red
    Write-Host "Please run: flutter build apk --release" -ForegroundColor Yellow
    exit 1
}

Write-Host "APK Location: $apkPath" -ForegroundColor White
$apkSize = (Get-Item $apkPath).Length / 1MB
Write-Host "APK Size: $([math]::Round($apkSize, 2)) MB" -ForegroundColor White
Write-Host ""
Write-Host "Installing... (this may take 30-60 seconds)" -ForegroundColor Yellow

$installResult = adb install $apkPath 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ APK installed successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Installation failed!" -ForegroundColor Red
    Write-Host "Error: $installResult" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 4: Launch app
Write-Host "Step 4: Launching app..." -ForegroundColor Yellow
adb shell am start -n com.rlmss.rlmss/.MainActivity 2>&1 | Out-Null
Start-Sleep -Seconds 2
Write-Host "✓ App launched" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Three fixes applied:" -ForegroundColor White
Write-Host "   1. Learner attempts reduced: 10 → 4" -ForegroundColor White
Write-Host "   2. Cancel button exits clock-in" -ForegroundColor White
Write-Host "   3. No re-enrollment dialog" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Login to the app" -ForegroundColor White
Write-Host "2. Test face verification (see FACE_VERIFICATION_TEST_PLAN.md)" -ForegroundColor White
Write-Host "3. Report any issues" -ForegroundColor White
Write-Host ""
Write-Host "To view app logs:" -ForegroundColor Yellow
Write-Host "   adb logcat | Select-String 'FACE'" -ForegroundColor White
Write-Host ""
