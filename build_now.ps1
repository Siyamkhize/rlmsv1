# RLMSS Emergency Build - PowerShell Version
# For 4GB RAM Systems

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  EMERGENCY BUILD FOR 4GB RAM SYSTEMS" -ForegroundColor Yellow
Write-Host "  This will attempt minimal memory usage" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Free system memory
Write-Host "[1/8] Freeing up system memory..." -ForegroundColor Green
Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name "gradle*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Step 2: Clear caches
Write-Host "[2/8] Clearing system caches..." -ForegroundColor Green
flutter clean | Out-Null
if (Test-Path "build") { Remove-Item "build" -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path "android\.gradle") { Remove-Item "android\.gradle" -Recurse -Force -ErrorAction SilentlyContinue }
$gradleCache = "$env:USERPROFILE\.gradle\caches"
if (Test-Path $gradleCache) { Remove-Item $gradleCache -Recurse -Force -ErrorAction SilentlyContinue }

# Step 3: Set memory limits
Write-Host "[3/8] Setting minimal memory allocation..." -ForegroundColor Green
$env:GRADLE_OPTS = "-Xmx320m -XX:MaxMetaspaceSize=64m -XX:+UseSerialGC -XX:+UseStringDeduplication -XX:+UseCompressedOops"
$env:JAVA_OPTS = "-Xmx320m -XX:MaxMetaspaceSize=64m"
$env:_JAVA_OPTIONS = "-Xmx320m -XX:MaxMetaspaceSize=64m"

# Step 4: Get dependencies
Write-Host "[4/8] Getting dependencies..." -ForegroundColor Green
flutter pub get

# Step 5: Pre-build setup
Write-Host "[5/8] Preparing build environment..." -ForegroundColor Green
Set-Location "android"
& .\gradlew clean --no-daemon --quiet 2>$null
Set-Location ".."

# Step 6: Build APK
Write-Host "[6/8] Attempting APK build (this may take 15-30 minutes)..." -ForegroundColor Green
Write-Host "WARNING: Do not use computer for other tasks during build!" -ForegroundColor Red
Write-Host ""

try {
    flutter build apk --release --target-platform android-arm64 --tree-shake-icons --obfuscate --split-debug-info=debug-info
    
    # Step 7: Check results
    Write-Host ""
    Write-Host "[7/8] Checking build results..." -ForegroundColor Green
    
    $apkPath = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
    if (Test-Path $apkPath) {
        Write-Host "[8/8] SUCCESS! APK built successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "APK Location: $apkPath" -ForegroundColor Cyan
        $apkSize = (Get-Item $apkPath).Length / 1MB
        Write-Host "APK Size: $([math]::Round($apkSize, 2)) MB" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "You can now install this APK on Android devices." -ForegroundColor Green
    } else {
        Write-Host "[8/8] FAILED: Build unsuccessful" -ForegroundColor Red
        Write-Host ""
        Write-Host "TROUBLESHOOTING STEPS:" -ForegroundColor Yellow
        Write-Host "1. Close ALL other applications" -ForegroundColor White
        Write-Host "2. Increase virtual memory in Windows settings" -ForegroundColor White
        Write-Host "3. Try running: .\swap_build.bat" -ForegroundColor White
        Write-Host "4. Consider using the web dashboard instead" -ForegroundColor White
    }
} catch {
    Write-Host "Build failed with error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Build process complete." -ForegroundColor Cyan