# Clear App Cache and Install New APK with Strict 0.95 Face Verification
# This script will:
# 1. Wait for device to connect
# 2. Clear all app data (including face embeddings cache)
# 3. Install the new APK with strict verification

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Clear Cache & Install APK Script" -ForegroundColor Cyan
Write-Host "Strict 0.95 Face Verification" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Package name
$packageName = "com.example.rlmss"
$apkPath = "C:\projects\rlmss\android\app\build\outputs\apk\release\app-release.apk"

# Check if APK exists
if (-not (Test-Path $apkPath)) {
    Write-Host "ERROR: APK not found at $apkPath" -ForegroundColor Red
    exit 1
}

Write-Host "[1/4] Checking for connected device..." -ForegroundColor Yellow
adb devices

$deviceCheck = adb devices | Select-String -Pattern "device$"
if (-not $deviceCheck) {
    Write-Host "No device connected. Please connect your device and enable USB debugging." -ForegroundColor Red
    Write-Host "Waiting for device to connect..."
    adb wait-for-device
    Write-Host "Device connected!" -ForegroundColor Green
}

Write-Host ""
Write-Host "[2/4] Clearing app data (removes old face embeddings)..." -ForegroundColor Yellow
adb shell pm clear $packageName
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ App data cleared successfully" -ForegroundColor Green
} else {
    Write-Host "! App may not be installed yet (this is OK for first install)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[3/4] Installing new APK..." -ForegroundColor Yellow
adb install -r $apkPath
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ APK installed successfully" -ForegroundColor Green
} else {
    Write-Host "✗ Installation failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/4] Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "What was updated:" -ForegroundColor Cyan
Write-Host "  • Face verification threshold: 0.95 (STRICT)" -ForegroundColor White
Write-Host "  • RAW cosine similarity scoring" -ForegroundColor White
Write-Host "  • Quality check before verification" -ForegroundColor White
Write-Host "  • Identical PHP ↔ Dart logic" -ForegroundColor White
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Testing Instructions:" -ForegroundColor Yellow
Write-Host "1. Enroll your face as a learner" -ForegroundColor White
Write-Host "2. Clock in with YOUR face (should PASS)" -ForegroundColor White
Write-Host "3. Try to clock out with DIFFERENT person (should FAIL)" -ForegroundColor White
Write-Host "4. Clock out with YOUR face (should PASS)" -ForegroundColor White
Write-Host ""

