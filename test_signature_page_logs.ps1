# Monitor signature clock-in page logs
# Run this while opening the signature clock-in page on device

Write-Host "Monitoring logs for signature clock-in page..." -ForegroundColor Cyan
Write-Host "Open the app and navigate to signature clock-in for class 134" -ForegroundColor Yellow
Write-Host ""

adb -s RZ8X306F7TZ logcat -s flutter:I | Select-String -Pattern "\[SIGNATURE_GEO\]"
