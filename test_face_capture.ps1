# Quick test script for smart face capture
# Usage: .\test_face_capture.ps1

Write-Host "`n=== SMART FACE CAPTURE TEST ===" -ForegroundColor Cyan

Write-Host "`n1. Checking device connection..." -ForegroundColor Yellow
$device = adb devices | Select-String "RZ8X10CKD0B"
if ($device) {
    Write-Host "✓ Device RZ8X10CKD0B connected" -ForegroundColor Green
} else {
    Write-Host "✗ Device not found! Connect RZ8X10CKD0B" -ForegroundColor Red
    exit 1
}

Write-Host "`n2. Checking if app is installed..." -ForegroundColor Yellow
$app = adb -s RZ8X10CKD0B shell pm list packages | Select-String "za.co.fsd.rlmss"
if ($app) {
    Write-Host "✓ App installed" -ForegroundColor Green
} else {
    Write-Host "✗ App not installed!" -ForegroundColor Red
    exit 1
}

Write-Host "`n3. Starting app..." -ForegroundColor Yellow
adb -s RZ8X10CKD0B shell am start -n za.co.fsd.rlmss/.MainActivity
Start-Sleep -Seconds 2
Write-Host "✓ App launched" -ForegroundColor Green

Write-Host "`n=== TEST INSTRUCTIONS ===" -ForegroundColor Cyan
Write-Host @"

On the device:
1. Login as a facilitator
2. Go to Clock In page
3. Select any learner
4. Tap 'Manual Clock In' or 'Take Photo'
5. The smart camera should open

WATCH FOR:
→ 6 check chips at top (turn green as rules pass)
→ Oval border color: White → Orange → Green
→ Hint message updates as you adjust
→ Progress ring when all checks pass

TEST EACH SCENARIO (see SMART_FACE_CAPTURE_TESTING_GUIDE.md):
□ Lighting: dark, bright, normal
□ Distance: too far, too close, perfect
□ Position: off-center, centered
□ Head angle: tilted, straight
□ Eyes: closed, open
□ Multiple people in frame
□ Hold still for 1 second

IF ISSUES OCCUR:
1. Note which check fails incorrectly
2. Check the testing guide for solutions
3. Adjust thresholds in the .dart file
4. Rebuild with: flutter build apk --release
5. Reinstall with: adb install -r build\app\outputs\flutter-apk\app-release.apk

MONITORING LOGS:
"@

Write-Host "`n4. Monitoring app logs (Ctrl+C to stop)..." -ForegroundColor Yellow
Write-Host "Look for [SMART_FRAMED_CAMERA] or [SMART_CAMERA] tags`n" -ForegroundColor Gray

adb -s RZ8X10CKD0B logcat -s "flutter:*" "*:E" | Select-String "SMART|CAMERA|ML"
