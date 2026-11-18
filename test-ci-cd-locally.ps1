# Local CI/CD Test Script
# This simulates what GitHub Actions will run

Write-Host "========================================"
Write-Host "   RLMSS CI/CD Local Test Script"
Write-Host "========================================"
Write-Host ""

$errors = 0

# Test 1: Flutter Analyze
Write-Host "Test 1: Running Flutter Analyze..."
flutter analyze --no-fatal-infos > analysis.log 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[PASS] Flutter Analyze - No errors found!"
} else {
    Write-Host "[FAIL] Flutter Analyze"
    Get-Content analysis.log | Select-String "error -"
    $errors++
}
Write-Host ""

# Test 2: Security Audit
Write-Host "Test 2: Running Security Audit..."
if (Test-Path "scripts/security-audit-simple.sh") {
    bash scripts/security-audit-simple.sh
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PASS] Security Audit!"
    } else {
        Write-Host "[FAIL] Security Audit"
        $errors++
    }
} else {
    Write-Host "[SKIP] Security audit script not found"
}
Write-Host ""

# Test 3: Unit Tests
Write-Host "Test 3: Running Unit Tests..."
flutter test --reporter=expanded
if ($LASTEXITCODE -eq 0) {
    Write-Host "[PASS] Unit Tests!"
} else {
    Write-Host "[FAIL] Unit Tests"
    $errors++
}
Write-Host ""

# Test 4: Build APK (Debug)
Write-Host "Test 4: Building Debug APK..."
flutter build apk --debug
if ($LASTEXITCODE -eq 0) {
    Write-Host "[PASS] Debug APK Build!"
    $apkPath = "build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $apkPath) {
        $apkSize = (Get-Item $apkPath).Length / 1MB
        Write-Host "   APK Size: $([math]::Round($apkSize, 2)) MB"
    }
} else {
    Write-Host "[FAIL] Debug APK Build"
    $errors++
}
Write-Host ""

# Summary
Write-Host "========================================"
Write-Host "           TEST SUMMARY"
Write-Host "========================================"
if ($errors -eq 0) {
    Write-Host "[SUCCESS] ALL TESTS PASSED!"
    Write-Host "Your code is ready for CI/CD pipeline!"
} else {
    Write-Host "[FAILED] $errors test(s) failed"
    Write-Host "Please fix the issues before pushing."
}
Write-Host ""
Write-Host "GitHub Actions will run these same checks when you push."
Write-Host "View at: github.com/Siyamkhize/rlmsv1/actions"
Write-Host ""

exit $errors
